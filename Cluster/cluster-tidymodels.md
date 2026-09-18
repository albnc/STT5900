# Análise de Agrupamento em R — abordagem tidymodels

**STT5900 · Departamento de Engenharia de Transportes · EESC/USP**
Prof. Dr. André Luiz Barbosa Nunes da Cunha

> Mesmo procedimento do arquivo [`cluster-padrao.md`](cluster-padrao.md)
> — agrupamento hierárquico e k-means sobre `mtcars` — agora com
> `tidymodels` + `tidyclust`. Leia o outro arquivo primeiro: os conceitos
> (distância, *linkage*, escolha de *k*) estão lá e não se repetem aqui.

---

## 1. Por que trocar `kmeans()` por um *workflow*

A versão clássica funciona, mas espalha o procedimento em objetos soltos: uma
matriz padronizada aqui, um `hclust` ali, um `kmeans` acolá. Três problemas
aparecem assim que o trabalho sai do `mtcars`:

| Problema na versão clássica | O que o `tidymodels` faz |
|---|---|
| `scale()` é aplicado uma vez e a regra se perde — não dá para repetir em dados novos | A **receita** guarda média e desvio-padrão e os reaplica com `predict()` |
| Trocar k-means por hierárquico exige reescrever tudo | Troca-se só a **especificação do modelo**; receita e *workflow* ficam |
| Escolher *k* é feito no olho, com o banco inteiro | `tune_cluster()` + reamostragem avaliam *k* com métrica declarada |
| Saídas com formatos diferentes (`$cluster`, `cutree`) | `extract_cluster_assignment()` e `extract_centroids()` para qualquer modelo |

O ganho decisivo é o primeiro: a padronização deixa de ser um passo manual e passa
a fazer parte do modelo. Em agrupamento isso importa menos do que em aprendizado
supervisionado (não há divisão treino/teste obrigatória), mas o hábito se transfere
— e é o mesmo *workflow* que você usará nas aulas de regressão e classificação.

```r
install.packages(c("tidymodels", "tidyclust", "GGally", "factoextra"))
```

```r
library(tidymodels)
library(tidyclust)
library(GGally)
library(factoextra)

tidymodels_prefer()   # evita conflitos de nomes com stats e MASS
set.seed(27)
```

---

## 2. Os dados

```r
df <- mtcars
df |> ggpairs()
```

`tidyclust` trabalha com `data.frame`/`tibble`, não com matriz. Os nomes de linha
de `mtcars` (`"Mazda RX4"`) são preservados no `data.frame`, mas somem em `tibble` —
se quiser conservá-los para os gráficos, transforme-os em coluna e exclua-a da
receita:

```r
df <- mtcars |>
  tibble::rownames_to_column("modelo")
```

---

## 3. Receita — o pré-processamento como objeto

```r
cluster_recipe <-
  recipe(~ ., data = df) |>       # sem lado esquerdo: não há variável resposta
  update_role(modelo, new_role = "id") |>   # identificador, não preditor
  step_zv(all_predictors()) |>              # remove variáveis de variância zero
  step_normalize(all_predictors())          # z-score: média 0, desvio 1
```

Três pontos que costumam gerar dúvida:

- **`recipe(~ .)`** — a fórmula sem lado esquerdo é a marca do problema não
  supervisionado. Não há `y`.
- **`step_zv()`** — variável constante tem desvio-padrão zero; `step_normalize()`
  dividiria por zero e devolveria `NaN`. O passo é barato e evita o erro.
- **`step_normalize()`** — equivale a `scale(center = TRUE, scale = TRUE)`, mas a
  regra fica **armazenada** na receita. Para min-max, use `step_range()`.

Inspecione o que a receita faz antes de usá-la:

```r
cluster_recipe |> prep() |> bake(new_data = NULL) |> summary()
```

Passos úteis quando o banco cresce:

```r
# step_pca(all_predictors(), num_comp = 3)     # colinearidade → componentes
# step_dummy(all_nominal_predictors())         # categóricas → binárias
# step_impute_median(all_numeric_predictors()) # faltantes
```

---

## 4. k-means

### Especificação, *workflow* e ajuste

```r
kmeans_spec <-
  k_means(num_clusters = 3) |>
  set_engine("stats", nstart = 25)   # nstart continua sendo obrigatório

clust_wf <-
  workflow() |>
  add_recipe(cluster_recipe) |>
  add_model(kmeans_spec)

clust_fit <- fit(clust_wf, data = df)
```

O `fit()` executa, na ordem: prepara a receita, padroniza, ajusta o k-means.
A regra de padronização fica dentro de `clust_fit` — não é preciso guardar `df_std`.

### Extraindo resultados

```r
extract_cluster_assignment(clust_fit)   # tibble com .cluster
extract_centroids(clust_fit)            # centroides na escala padronizada
extract_fit_summary(clust_fit)          # WSS, tamanhos, tudo de uma vez

clustered <- augment(clust_fit, new_data = df)   # dados originais + .cluster
```

`augment()` é a função central: devolve o banco **original** com a coluna
`.cluster` acrescentada. É a partir dele que se faz toda a interpretação.

### Interpretação — na escala original

```r
perfil <- clustered |>
  group_by(.cluster) |>
  summarise(n = n(), across(where(is.numeric), mean), .groups = "drop")

perfil
```

```r
clustered |>
  ggplot(aes(wt, mpg, color = .cluster)) +
  geom_point(size = 3) +
  ggrepel::geom_text_repel(aes(label = modelo), size = 3, show.legend = FALSE) +
  labs(title = "k-means, k = 3", x = "Peso (1000 lb)", y = "Consumo (mpg)",
       color = "Grupo") +
  theme_minimal()
```

Para o gráfico em componentes principais, `factoextra` continua servindo:

```r
fviz_cluster(
  list(data    = clust_fit |> extract_recipe() |> bake(new_data = df) |>
                 select(where(is.numeric)),
       cluster = extract_cluster_assignment(clust_fit)$.cluster),
  ellipse.type = "euclid", repel = TRUE, ggtheme = theme_minimal()
)
```

---

## 5. Escolhendo *k* com reamostragem

Aqui está a diferença metodológica mais relevante em relação ao `fviz_nbclust()`.
Em vez de calcular a métrica uma única vez com o banco inteiro, avaliamos cada *k*
em várias reamostras e olhamos a **média e a variabilidade** — um *k* cuja silhueta
oscila muito entre reamostras não é uma escolha estável.

```r
kmeans_tune <-
  k_means(num_clusters = tune()) |>
  set_engine("stats", nstart = 25)

tune_wf <-
  workflow() |>
  add_recipe(cluster_recipe) |>
  add_model(kmeans_tune)

folds <- vfold_cv(df, v = 5)
grid_k <- tibble(num_clusters = 1:9)

res <- tune_cluster(
  tune_wf,
  resamples = folds,
  grid      = grid_k,
  metrics   = cluster_metric_set(sse_within_total, sse_ratio, silhouette_avg)
)

collect_metrics(res)
```

```r
collect_metrics(res) |>
  filter(.metric %in% c("sse_ratio", "silhouette_avg")) |>
  ggplot(aes(num_clusters, mean)) +
  geom_line() +
  geom_point(size = 2) +
  geom_errorbar(aes(ymin = mean - std_err, ymax = mean + std_err), width = 0.15) +
  facet_wrap(~ .metric, scales = "free_y") +
  scale_x_continuous(breaks = 1:9) +
  labs(x = "Número de grupos (k)", y = NULL) +
  theme_minimal()
```

As três métricas de `tidyclust`:

| Métrica | Leitura |
|---|---|
| `sse_within_total` | soma de quadrados dentro dos grupos — o "cotovelo" clássico |
| `sse_ratio` | WSS / SST; a versão normalizada, entre 0 e 1, comparável entre bancos |
| `silhouette_avg` | silhueta média; **maior é melhor** (as duas anteriores, menor é melhor) |

Escolhido o *k*, finalize:

```r
melhor_k <- select_best(res, metric = "silhouette_avg")
melhor_k

fit_final <- finalize_workflow_tailor(tune_wf, melhor_k) |> fit(data = df)
# em versões anteriores do tidyclust: finalize_workflow(tune_wf, melhor_k)
```

> As barras de erro do gráfico costumam contar mais que o ponto médio: se o
> intervalo de *k* = 3 e o de *k* = 4 se sobrepõem, prefira o **menor** *k* —
> é o princípio da parcimônia, e é a mesma lógica do `select_by_one_std_err()`
> usado em modelos supervisionados.

---

## 6. Agrupamento hierárquico

A troca de algoritmo custa **uma linha** — receita e *workflow* são os mesmos:

```r
hier_spec <-
  hier_clust(num_clusters = 3, linkage_method = "ward.D2") |>
  set_engine("stats")

hier_fit <-
  workflow() |>
  add_recipe(cluster_recipe) |>
  add_model(hier_spec) |>
  fit(data = df)

extract_cluster_assignment(hier_fit)
extract_centroids(hier_fit)
```

O dendrograma sai do objeto `hclust` interno:

```r
hier_fit |>
  extract_fit_engine() |>
  fviz_dend(k = 3, rect = TRUE, cex = 0.6)
```

`hier_clust()` também aceita `cut_height` em vez de `num_clusters`, quando o
critério for uma dissimilaridade máxima aceitável.

### Comparando as duas partições

```r
bind_cols(
  kmeans      = extract_cluster_assignment(clust_fit)$.cluster,
  hierarquico = extract_cluster_assignment(hier_fit)$.cluster
) |>
  count(kmeans, hierarquico) |>
  tidyr::pivot_wider(names_from = hierarquico, values_from = n, values_fill = 0)
```

> Os rótulos dos grupos são arbitrários: o grupo 1 de um método não corresponde
> necessariamente ao grupo 1 do outro. Leia a tabela procurando **concentração**
> (uma célula grande por linha), não a diagonal.

---

## 7. Vários modelos de uma vez — `workflow_set`

Quando houver mais de um pré-processamento e mais de um algoritmo, monte o
produto cartesiano em vez de repetir código:

```r
receitas <- list(
  zscore = cluster_recipe,
  pca    = cluster_recipe |> step_pca(all_predictors(), num_comp = 3)
)

modelos <- list(
  kmeans = k_means(num_clusters = tune()) |> set_engine("stats", nstart = 25),
  hier   = hier_clust(num_clusters = tune(), linkage_method = "ward.D2")
)

wfs <- workflow_set(preproc = receitas, models = modelos)

resultados <- wfs |>
  workflow_map("tune_cluster",
               resamples = folds,
               grid      = grid_k,
               metrics   = cluster_metric_set(silhouette_avg, sse_ratio),
               verbose   = TRUE)

rank_results(resultados, rank_metric = "silhouette_avg", select_best = TRUE)
```

Quatro combinações avaliadas sob o mesmo protocolo, com uma tabela de ranking ao
final. É esse o retorno de ter estruturado o procedimento como *workflow*.

---

## 8. Equivalências entre as duas abordagens

| Etapa | Clássico | tidymodels / tidyclust |
|---|---|---|
| Padronizar | `scale(df)` | `step_normalize()` na receita |
| Min-max | `scale(df, center = min, scale = max-min)` | `step_range()` |
| Remover constantes | manual | `step_zv()` |
| k-means | `kmeans(x, centers = 3, nstart = 25)` | `k_means(num_clusters = 3) \|> set_engine("stats", nstart = 25)` |
| Hierárquico | `hclust(dist(x), method = "ward.D2")` | `hier_clust(linkage_method = "ward.D2")` |
| Cortar árvore | `cutree(h, k = 3)` | `num_clusters = 3` na especificação |
| Atribuições | `km$cluster` / `cutree()` | `extract_cluster_assignment()` |
| Centroides | `km$centers` | `extract_centroids()` |
| Dados + grupo | `cbind(df, km$cluster)` | `augment(fit, new_data = df)` |
| Escolher *k* | `fviz_nbclust()` | `tune_cluster()` + `cluster_metric_set()` |
| Dendrograma | `plot(h)` / `fviz_dend(h)` | `extract_fit_engine() \|> fviz_dend()` |

---

## 9. Exercícios

1. Troque `step_normalize()` por `step_range()` na receita e refaça a escolha de
   *k*. A silhueta muda? E a partição final?
2. Acrescente `step_pca(num_comp = 2)` e compare a silhueta com a da receita sem
   PCA. Reduzir dimensão melhorou a separação ou apagou informação?
3. Rode o `workflow_set` da seção 7 e apresente `rank_results()`. Qual combinação
   vence e por qual margem? A margem é maior que o erro-padrão?
4. Aplique o *workflow* completo a `USArrests`, justificando *k* pela silhueta com
   reamostragem e **nomeando** cada grupo com base no `perfil`.
5. Compare a partição obtida aqui com a de `cluster-padrao.md` usando a tabela
   cruzada da seção 6. Elas coincidem? O que explicaria a diferença?

---

## Referências

- Hvitfeldt, E. *tidyclust: A Common API to Clustering*. <https://tidyclust.tidymodels.org/>
- Kuhn, M.; Silge, J. *Tidy Modeling with R*. O'Reilly, 2022. <https://www.tmwr.org/>
- Kassambara, A. *Practical Guide to Cluster Analysis in R*. STHDA, 2017.
- James, G. et al. *An Introduction to Statistical Learning*, cap. 12. Springer, 2021.
