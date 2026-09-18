# Análise de Agrupamento em R — abordagem clássica

**STT5900 · Departamento de Engenharia de Transportes · EESC/USP**
Prof. Dr. André Luiz Barbosa Nunes da Cunha

> Este material cobre o agrupamento (*clustering*) com as funções de base do R
> (`dist`, `hclust`, `kmeans`) e o pacote `factoextra` para visualização.
> A versão equivalente com `tidymodels`/`tidyclust` está em
> [`cluster-tidymodels.md`](cluster-tidymodels.md).

---

## 1. O problema

Agrupamento é **aprendizado não supervisionado**: não existe variável resposta.
O algoritmo não sabe se acertou — ele apenas particiona as observações de modo que
objetos do mesmo grupo sejam mais parecidos entre si do que com os dos outros grupos.

Três decisões definem o resultado, e **todas são do analista**, não do algoritmo:

| Decisão | Pergunta | Onde aparece no código |
|---|---|---|
| Escala das variáveis | O que significa "parecido"? | `scale()` |
| Medida de distância | Como medir a diferença? | `dist()`, `get_dist()` |
| Número de grupos | Quantos grupos existem? | `cutree(k=)`, `kmeans(centers=)` |

Se você mudar qualquer uma das três, muda o resultado. Não há resposta certa —
há resposta **justificável**. Documente as três escolhas em qualquer trabalho.

```r
library(dplyr)
library(ggplot2)
library(GGally)
library(factoextra)

set.seed(123)   # k-means é estocástico: sem semente, não há reprodutibilidade
```

---

## 2. Os dados

Usamos `mtcars`: 32 automóveis (*Motor Trend*, 1974), 11 variáveis numéricas.
Banco pequeno o bastante para inspecionar linha a linha e heterogêneo o bastante
para formar grupos com significado físico (esportivos, sedãs, econômicos).

```r
data("mtcars")
help(mtcars)          # sempre leia o dicionário antes de modelar

df <- mtcars
str(df)
summary(df)

df["Mazda RX4", ]     # seleção por nome da linha
df[1, ]               # por posição
```

### Inspeção visual antes de qualquer modelo

```r
pairs(df)             # matriz de dispersão — R base

df %>% ggpairs()      # + correlações e densidades marginais
```

O que procurar no `ggpairs()`:

- **Variáveis muito correlacionadas** (`disp`, `hp`, `wt`, `cyl` acima de 0,8):
  a distância euclidiana as conta várias vezes, dando peso extra ao "tamanho do motor".
- **Variáveis binárias disfarçadas de numéricas** (`vs`, `am`): distância euclidiana
  entre 0 e 1 não significa o mesmo que entre 100 e 200 cv.
- **Escalas incompatíveis**: `disp` vai a 472, `drat` fica entre 2,7 e 4,9.

---

## 3. Padronização — a etapa que não é opcional

A distância euclidiana soma diferenças ao quadrado. Sem padronizar, a variável de
maior amplitude domina tudo: em `mtcars`, `disp` (cilindrada) sozinha responde por
quase toda a distância, e o agrupamento vira um ranking de cilindrada.

### O que `scale()` faz

```r
x <- c(1, 2, 3, 4, 5, 6)

# padronização (z-score): média 0, desvio-padrão 1
scale(x, center = TRUE, scale = TRUE)
(x - mean(x)) / sd(x)                        # idêntico

# center = FALSE: divide pela raiz quadrada média, não pelo desvio-padrão
scale(x, center = FALSE, scale = TRUE)
sqrt(sum(x^2) / (length(x) - 1))             # este é o divisor usado

# normalização min-max: reescala para [0, 1]
scale(x, center = min(x), scale = max(x) - min(x))
(x - min(x)) / (max(x) - min(x))             # idêntico
```

`scale()` é genérico: `center` e `scale` aceitam qualquer vetor de constantes.
É isso que permite escrever a normalização min-max sem função auxiliar.

### Aplicando ao banco

```r
# z-score
df_std <- scale(df, center = TRUE, scale = TRUE)
summary(df_std)        # todas as médias ≈ 0

# min-max
df_norm <- scale(df,
                 center = apply(df, 2, min),
                 scale  = apply(df, 2, max) - apply(df, 2, min))
summary(df_norm)       # todas entre 0 e 1
```

### Funções próprias (para reuso)

```r
normalize <- function(var) (var - min(var)) / (max(var) - min(var))

standardize <- function(var) (var - mean(var)) / sd(var)

apply(mtcars, 2, normalize)
apply(mtcars, 2, standardize)
```

> **z-score ou min-max?** Use z-score quando as variáveis forem aproximadamente
> simétricas — é o padrão em agrupamento. Use min-max quando houver limites físicos
> conhecidos (percentuais, notas) ou quando quiser preservar zeros. Min-max é mais
> sensível a *outliers*, porque um único valor extremo define o denominador.

> **Atenção ao tipo devolvido.** `scale()` retorna uma **matriz**, não um
> `data.frame`. Funções que esperam `data.frame` (`ggpairs`, `aggregate`) exigem
> `as.data.frame(df_std)`.

---

## 4. Medidas de distância

```r
distance <- get_dist(df_std)          # euclidiana, o padrão
fviz_dist(distance)                   # mapa de calor da matriz de distâncias

distance_man <- get_dist(df_std, method = "manhattan")
distance_cor <- get_dist(df_std, method = "pearson")
```

| Medida | Quando usar |
|---|---|
| **Euclidiana** | Padrão. Variáveis contínuas, na mesma escala, sem *outliers* fortes. |
| **Manhattan** | Mais robusta a *outliers*; soma diferenças absolutas em vez de quadrados. |
| **Correlação** (Pearson) | Quando importa o **padrão** e não a magnitude — dois postos de contagem com perfis horários iguais mas volumes diferentes ficam próximos. |
| **Gower** | Quando há variáveis categóricas misturadas (`cluster::daisy`). |

No `fviz_dist()` procure **blocos escuros ao longo da diagonal**: são grupos
naturais. Se o mapa for um borrão homogêneo, provavelmente não há estrutura de
grupos nos dados — e nenhum algoritmo vai criar uma que não existe.

---

## 5. Agrupamento hierárquico

Começa com cada observação em seu próprio grupo e vai fundindo os mais próximos até
sobrar um só (método **aglomerativo**). O resultado é uma árvore — o dendrograma —
que contém **todas** as partições possíveis de 1 a *n* grupos ao mesmo tempo.

```r
hcluster <- hclust(distance, method = "complete")
hcluster

plot(hcluster, cex = 0.7, hang = -1)     # dendrograma em R base
fviz_dend(hcluster, k = 3, rect = TRUE)  # versão colorida do factoextra
```

### O parâmetro `method`: como medir a distância entre *grupos*

`dist()` mede a distância entre dois **pontos**. Para fundir grupos, é preciso
definir a distância entre dois **conjuntos** de pontos — é o que `method` faz:

| `method` | Regra | Efeito |
|---|---|---|
| `"single"` | menor distância entre membros | encadeia; forma grupos alongados |
| `"complete"` | maior distância entre membros | grupos compactos e de tamanho parecido |
| `"average"` | média das distâncias | meio-termo |
| `"ward.D2"` | minimiza o aumento da soma de quadrados interna | grupos esféricos e equilibrados; **o mais usado na prática** |

A escolha do *linkage* muda o dendrograma tanto quanto a escolha da distância.
Rode ao menos dois e verifique se a estrutura se mantém — **estabilidade é o melhor
indício de que os grupos são reais**.

### Cortando a árvore

```r
cut_cluster <- cutree(hcluster, k = 3)
table(cut_cluster)                        # tamanho de cada grupo

# quem está em cada grupo
split(rownames(df), cut_cluster)

mtcars[cut_cluster == 1, ] %>% ggpairs()
mtcars[cut_cluster == 2, ] %>% ggpairs()

# perfil médio de cada grupo — a etapa de interpretação
aggregate(mtcars, by = list(cluster = cut_cluster), FUN = mean)
```

Também é possível cortar por altura (`cutree(hcluster, h = 5)`), útil quando o
critério for uma dissimilaridade máxima aceitável, e não um número de grupos.

> O corte é feito nos dados **padronizados**, mas a interpretação usa os dados
> **originais** — só assim os perfis têm unidade física (cv, kg, mpg).

---

## 6. Quantos grupos?

Não existe teste de hipótese que decida. Existem três indicadores, e a boa prática
é olhar os três antes de escolher.

```r
fviz_nbclust(df_std, kmeans, method = "wss")        # cotovelo
fviz_nbclust(df_std, kmeans, method = "silhouette") # silhueta
fviz_nbclust(df_std, kmeans, method = "gap_stat")   # estatística gap
```

**Cotovelo (WSS)** — soma dos quadrados dentro dos grupos. Cai sempre que *k*
aumenta (com *k = n* ela é zero), então o que interessa é o **ponto de inflexão**,
onde acrescentar um grupo deixa de compensar. É o critério mais subjetivo.

**Silhueta** — para cada ponto, compara a distância média ao próprio grupo com a
distância média ao grupo vizinho mais próximo. Varia de −1 a 1:

- acima de 0,5: estrutura razoável;
- entre 0,25 e 0,5: estrutura fraca;
- abaixo de 0,25 ou negativa: os grupos praticamente não se distinguem.

**Gap** — compara a WSS observada com a de dados uniformes sem estrutura alguma.
É o único que admite a resposta *k = 1* (não há grupos). Custa caro (usa reamostragem).

> Quando os três discordarem — o que é comum —, prefira o *k* que produzir grupos
> **interpretáveis**. Um agrupamento que você não consegue nomear não serve para
> decisão, ainda que a silhueta seja ótima.

---

## 7. k-means

Algoritmo iterativo, em quatro passos:

1. sorteia *k* centroides;
2. atribui cada ponto ao centroide mais próximo;
3. recalcula cada centroide como a média do seu grupo;
4. repete 2–3 até as atribuições não mudarem.

```r
k <- 3
km.res <- kmeans(df_std, centers = k, nstart = 25)
print(km.res)
```

Dois argumentos merecem atenção:

- **`nstart = 25`** — repete o sorteio inicial 25 vezes e devolve a melhor solução.
  Com `nstart = 1` (o padrão!) o resultado depende do sorteio e pode ser um mínimo
  local ruim. **Use sempre `nstart` ≥ 25.**
- **`set.seed()`** — sem ele, duas execuções podem dar grupos diferentes.

### Saídas do objeto

```r
km.res$cluster       # vetor de atribuição
km.res$centers       # centroides (na escala padronizada)
km.res$size          # tamanho dos grupos
km.res$tot.withinss  # WSS total — a função-objetivo minimizada
km.res$betweenss / km.res$totss   # fração da variância explicada
```

### Visualização e interpretação

```r
fviz_cluster(km.res, data = df_std,
             ellipse.type = "euclid",
             star.plot = TRUE,
             repel = TRUE,
             ggtheme = theme_minimal())

# perfil médio na escala original — é aqui que os grupos ganham nome
aggregate(mtcars, by = list(cluster = km.res$cluster), FUN = mean)
```

`fviz_cluster()` projeta os dados nas duas primeiras componentes principais.
O eixo mostra quanto da variância cada componente explica — se a soma for baixa
(digamos, 60%), o gráfico é uma sombra grosseira da estrutura real.

### Comparando com o hierárquico

```r
table(hierarquico = cut_cluster, kmeans = km.res$cluster)
```

Alta concordância é um bom sinal: dois algoritmos com lógicas diferentes chegaram
à mesma partição. Discordância forte indica grupos mal separados.

---

## 8. Armadilhas frequentes

1. **Agrupar sem padronizar.** O erro mais comum. `kmeans(mtcars, 3)` produz grupos
   de cilindrada, não de perfil de veículo.
2. **`nstart = 1`.** Resultado irreprodutível e frequentemente subótimo.
3. **Achar que o algoritmo descobre o *k*.** Ele não descobre; ele obedece.
4. **Interpretar na escala padronizada.** "Centroide de `wt` = 1,2" não significa
   nada — reporte em quilos.
5. **Forçar grupos onde não há.** k-means sempre devolve *k* grupos, mesmo em ruído
   uniforme. Confira com a silhueta e com o `fviz_dist()`.
6. **Ignorar a colinearidade.** Variáveis redundantes contam duas vezes na distância.
   Considere PCA (`prcomp`) antes de agrupar.
7. **k-means com variáveis categóricas.** Média de categoria não existe. Use
   agrupamento hierárquico com distância de Gower, ou k-modes.

---

## 9. Exercícios

1. Repita todo o fluxo com `df_norm` (min-max) em vez de `df_std`. Os grupos mudam?
   Quantos veículos trocam de grupo? Use `table()` para comparar.
2. Compare os *linkages* `"complete"`, `"average"` e `"ward.D2"` com `fviz_dend()`.
   Qual produz grupos de tamanho mais equilibrado?
3. Aplique o fluxo ao banco `USArrests` (50 estados, 4 variáveis). Justifique o *k*
   com os três indicadores e **nomeie** cada grupo.
4. Remova `vs` e `am` (binárias) de `mtcars` e reagrupe. A estrutura se mantém?
   O que isso diz sobre usar variáveis binárias com distância euclidiana?
5. Rode `kmeans(df_std, 3, nstart = 1)` dez vezes sem `set.seed()` e registre
   `tot.withinss` em cada uma. Qual a amplitude? Por que `nstart` importa?

---

## Referências

- Kassambara, A. *Practical Guide to Cluster Analysis in R*. STHDA, 2017.
- James, G. et al. *An Introduction to Statistical Learning*, cap. 12. Springer, 2021.
- Hastie, T.; Tibshirani, R.; Friedman, J. *The Elements of Statistical Learning*, cap. 14. Springer, 2009.
- Documentação do `factoextra`: <https://rpkgs.datanovia.com/factoextra/>
