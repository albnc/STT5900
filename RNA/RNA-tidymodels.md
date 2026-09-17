# Redes Neurais em R — `tidymodels`

**STT5900 · Engenharia de Transportes · EESC-USP · 2026**

Os mesmos dois exemplos de [`RNA-simples`](RNA-simples.md) — `mtcars` e `iris` — agora no fluxo padrão do `tidymodels`.

Script: [`RNA-tidymodels`](RNA-tidymodels.md)

```r
install.packages("tidymodels")   # 80+ pacotes: instale ANTES da aula
```

```r
library(tidymodels)
tidymodels_prefer()   # resolve conflitos de nomes (filter, select, ...)
set.seed(2026)
```

> As saídas deste documento mostram o **formato** do resultado. Os valores mudam com a semente e a versão dos pacotes.

---

## Por que trocar `nnet()` direto por isto

1. A **receita** aprende a média e o desvio só no treino e reaplica no teste sozinha. Some a chance de vazamento de dados.
2. Trocar de modelo é trocar **uma linha**: `mlp()` → `rand_forest()` → `boost_tree()`.
3. As **métricas** vêm prontas e com nome padronizado.
4. O **workflow** salva receita e modelo juntos: quem receber o `.rds` não precisa saber como você escalonou nada.

### Equivalência

| `nnet` direto | `tidymodels` |
|---|---|
| `sample()` nas linhas | `initial_split()` · `training()` · `testing()` |
| `scale(center=, scale=)` | `step_normalize()` |
| `nnet(size=, decay=, linout=)` | `mlp(hidden_units=, penalty=)` + `set_mode()` |
| `predict()` + desfazer a escala | `augment()` — a escala volta sozinha |
| `rmse <- function(...)` | `metric_set(rmse, rsq, mae)` |
| `table(previsto, observado)` | `conf_mat()` |

### As sete etapas

```
[1] initial_split   [2] recipe   [3] model   [4] workflow
[5] fit   [6] augment   [7] métricas
```

Valem para qualquer modelo e qualquer banco de dados. É só isso que muda de aluno para aluno: os dados, nunca a estrutura.

---

# Parte 1 · `mtcars` — regressão

Prever `qsec` — tempo, em segundos, para percorrer 1/4 de milha.

## 1. `initial_split()`

Separa treino e teste em um objeto só.

```r
split  <- initial_split(mtcars, prop = 0.75)
treino <- training(split)
teste  <- testing(split)

c(treino = nrow(treino), teste = nrow(teste))
```

```
treino  teste
    24      8
```

## 2. `recipe()`

Uma lista de instruções de pré-processamento. Aprende no treino e reaplica, idêntica, no teste.

```r
receita <- recipe(qsec ~ mpg + cyl + disp + hp + wt, data = treino) |>
  step_normalize(all_numeric_predictors())

bake(prep(receita), new_data = NULL) |> head(3)   # o que a rede vai receber
```

Passos mais usados, na ordem em que entram na receita:

| passo | o que faz |
|---|---|
| `step_impute_median()` | preenche faltantes numéricos com a mediana do treino |
| `step_novel()` | reserva um nível para categorias que só aparecem no teste |
| `step_dummy()` | transforma categóricas em variáveis binárias |
| `step_zv()` | remove colunas constantes |
| `step_normalize()` | centra e escala — evita a saturação da ativação |

## 3. `mlp()`

A rede. `hidden_units` = `size`, `penalty` = `decay`, `epochs` = `maxit`.

```r
modelo <- mlp(hidden_units = 3, penalty = 0.01, epochs = 500) |>
  set_engine("nnet") |>      # quem faz a conta
  set_mode("regression")     # linout = TRUE vem junto, automático

translate(modelo)            # a chamada real ao nnet
```

```
nnet::nnet.formula(formula = missing_arg(), data = missing_arg(),
                   size = 3, decay = 0.01, maxit = 500,
                   trace = FALSE, linout = TRUE)
```

> O `parsnip` é um tradutor: você escreve sempre os nomes dele, e ele converte para os nomes do motor. Por isso trocar `nnet` por `brulee` não quebra o script.

## 4. `workflow()`

Junta receita e modelo. Na hora de prever, o pré-processamento vai junto — nada fica para trás.

```r
fluxo <- workflow() |>
  add_recipe(receita) |>
  add_model(modelo)
```

## 5. `fit()`

Treina. A semente importa: os pesos iniciais são aleatórios.

```r
set.seed(2026)
ajuste <- fit(fluxo, data = treino)

ajuste |> extract_fit_parsnip()     # o objeto nnet por baixo
```

## 6. `augment()`

Prevê e cola a coluna `.pred` nos dados de teste, já na escala original.

```r
predicoes <- augment(ajuste, new_data = teste)

predicoes |>
  select(qsec, .pred) |>
  mutate(erro = round(qsec - .pred, 2))
```

```
# A tibble: 8 x 3
   qsec  .pred   erro
  <dbl>  <dbl>  <dbl>
  ...
```

## 7. `metric_set()`

As métricas prontas. RMSE e MAE em segundos; R² adimensional.

```r
metricas <- metric_set(rmse, rsq, mae)

predicoes |> metricas(truth = qsec, estimate = .pred)
```

```
# A tibble: 3 x 3
  .metric .estimator .estimate
  <chr>   <chr>          <dbl>
1 rmse    standard         ...
2 rsq     standard         ...
3 mae     standard         ...
```

## + Baseline

Mesma receita, outro modelo: muda **uma linha**. É esse o ganho de usar `workflow`.

```r
fluxo_lm <- workflow() |>
  add_recipe(receita) |>
  add_model(linear_reg() |> set_engine("lm"))    # <- a única diferença

ajuste_lm <- fit(fluxo_lm, data = treino)
pred_lm   <- augment(ajuste_lm, new_data = teste)

bind_rows(
  predicoes |> rmse(qsec, .pred) |> mutate(modelo = "rede (mlp)"),
  pred_lm   |> rmse(qsec, .pred) |> mutate(modelo = "linear (lm)"),
  teste |> mutate(.pred = mean(treino$qsec)) |>
    rmse(qsec, .pred) |> mutate(modelo = "media (chute)")
) |> select(modelo, rmse = .estimate)
```

## + `ggplot()`

Observado × previsto. `coord_obs_pred()` força a mesma escala nos dois eixos.

```r
ggplot(predicoes, aes(qsec, .pred)) +
  geom_abline(linetype = "dashed", colour = "grey50") +
  geom_point(size = 3, colour = "steelblue") +
  coord_obs_pred() +
  labs(x = "qsec observado (s)", y = "qsec previsto (s)") +
  theme_minimal()
```

---

# Parte 2 · `iris` — classificação

O fluxo é o mesmo. Mudam três coisas:

| | regressão | classificação |
|---|---|---|
| alvo | numérico | `factor` |
| modo | `set_mode("regression")` | `set_mode("classification")` |
| `augment()` devolve | `.pred` | `.pred_class` + `.pred_<classe>` |

## 1. `initial_split(strata = )`

`strata` preserva a proporção das classes no treino e no teste.

```r
set.seed(2026)
split2  <- initial_split(iris, prop = 0.75, strata = Species)
treino2 <- training(split2)
teste2  <- testing(split2)

treino2 |> count(Species)
```

> Em classificação binária, o **primeiro nível** do fator é tratado como o evento de interesse. Confira com `levels(dados$alvo)` antes de ler qualquer sensibilidade.

## 2. `recipe()`

Mesma receita de antes: padronizar os preditores.

```r
receita2 <- recipe(Species ~ ., data = treino2) |>
  step_normalize(all_numeric_predictors())
```

## 3. `set_mode("classification")`

A única mudança relevante no modelo.

```r
modelo2 <- mlp(hidden_units = 5, penalty = 0.01, epochs = 500) |>
  set_engine("nnet") |>
  set_mode("classification")

fluxo2 <- workflow() |> add_recipe(receita2) |> add_model(modelo2)

set.seed(2026)
ajuste2 <- fit(fluxo2, data = treino2)
```

## 4. `augment()`

Devolve `.pred_class` e uma coluna de probabilidade por classe.

```r
predicoes2 <- augment(ajuste2, new_data = teste2)

predicoes2 |>
  select(Species, .pred_class, .pred_setosa, .pred_versicolor, .pred_virginica) |>
  head(4)
```

> Guarde as probabilidades: elas dizem o quanto o modelo está seguro. A classe prevista é só a probabilidade maior.

## 5. `conf_mat()`

A matriz de confusão. `summary()` devolve acurácia, kappa, sensibilidade e especificidade de uma vez.

```r
matriz <- predicoes2 |> conf_mat(truth = Species, estimate = .pred_class)
matriz

summary(matriz) |>
  filter(.metric %in% c("accuracy", "kap", "sens", "spec"))
```

```
            Truth
Prediction   setosa versicolor virginica
  setosa        ...
  versicolor    ...
  virginica     ...
```

```r
autoplot(matriz, type = "heatmap")   # a mesma matriz, em gráfico
```

## 6. `roc_auc()`

Usa as **probabilidades**, não a classe. Com mais de duas classes, passe todas as colunas.

```r
predicoes2 |> roc_auc(truth = Species,
                      .pred_setosa, .pred_versicolor, .pred_virginica)
```

> A ROC-AUC não depende do limiar de decisão nem da proporção das classes — por isso é preferível à acurácia em dados desbalanceados.

## 7. Comparar modelos

Mesma receita, mesmo split, mesma métrica. É assim que se diz "a rede foi melhor" com honestidade.

```r
candidatos <- list(
  "rede (mlp)"  = mlp(hidden_units = 5, penalty = 0.01, epochs = 500) |> set_engine("nnet"),
  "multinomial" = multinom_reg() |> set_engine("nnet")
  # "floresta"  = rand_forest(trees = 500) |> set_engine("ranger"),
  # "boosting"  = boost_tree(trees = 500)  |> set_engine("xgboost")
)

set.seed(2026)
purrr::map_dfr(candidatos, function(m) {
  aj <- workflow() |>
    add_recipe(receita2) |>
    add_model(set_mode(m, "classification")) |>
    fit(data = treino2)
  augment(aj, teste2) |> accuracy(Species, .pred_class)
}, .id = "modelo")
```

---

## Para mexer

| parâmetro | teste com | efeito de aumentar |
|---|---|---|
| `hidden_units` | 1, 3, 10, 30 | mais flexibilidade — e mais risco de decorar |
| `penalty` | 0, 0.01, 0.5 | modelo mais suave, menos sobreajuste |
| `epochs` | 50, 500, 5000 | erro de treino cai; o de teste, nem sempre |
| `set.seed()` | outro número | muda tudo — a rede não tem solução única |

## O que falta aqui

| falta | serve para |
|---|---|
| `vfold_cv()` + `tune_grid()` | escolher `hidden_units` e `penalty` **sem olhar o teste** |
| `last_fit()` | abrir o conjunto de teste uma única vez, no fim |
| `vip::vi_permute()` | medir a importância das variáveis |
| curvas de resposta | ler o que o modelo aprendeu, e não só o erro |

Está tudo no material completo da disciplina, [uma pasta acima](../).

---

Material didático · CC BY-NC-SA 4.0 · Código dos exemplos · MIT
Departamento de Engenharia de Transportes · EESC-USP · 2026
