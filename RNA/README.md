# Redes Neurais em R

**STT5900 · Engenharia de Transportes · EESC-USP · 2026**

Dois exemplos mínimos: prever um número (`mtcars`) e prever uma categoria (`iris`).
O mesmo problema resolvido de duas formas — com `nnet` direto e com `tidymodels`.

Scripts completos: [`RNA-simples.R`](RNA-simples.R) · [`RNA-tidymodels.R`](RNA-tidymodels.R)

---

## O que é uma rede neural

```
z = b + w1*x1 + w2*x2 + ... + wp*xp    # combinação linear
a = f(z)                                # ativação, não linear
```

Isso é um neurônio. A rede empilha neurônios em camadas e ajusta os pesos `w` para minimizar o erro. Sem a ativação não linear `f`, empilhar camadas dá apenas outra regressão linear.

**Três regras:**

1. **Escalonar as entradas.** Sem isso a ativação satura e a rede não aprende.
2. **Separar treino e teste.** Senão você mede a memória, não o modelo.
3. **Comparar com um modelo simples.** Sem baseline, um RMSE não significa nada.

---

# Parte A — `nnet` (base R)

Nada para instalar: o pacote `nnet` já vem com o R. As saídas abaixo foram geradas com `set.seed(2026)`.

```r
library(nnet)
set.seed(2026)
```

## A.1 · mtcars — regressão

Prever `qsec` — tempo, em segundos, para percorrer 1/4 de milha.

### 1. `sample()`

Sorteia 75% das linhas para treino; o resto é teste.

```r
dados  <- mtcars
n      <- nrow(dados)
i      <- sample(n, size = round(0.75 * n))
treino <- dados[i, ]
teste  <- dados[-i, ]

c(treino = nrow(treino), teste = nrow(teste))
```

```
treino  teste
    24      8
```

### 2. `scale()`

Padroniza com a média e o desvio **do treino**. Escalonar o banco inteiro antes de separar leva informação do teste para dentro do treino.

```r
media  <- apply(treino, 2, mean)
desvio <- apply(treino, 2, sd)

treino_esc <- as.data.frame(scale(treino, center = media, scale = desvio))
teste_esc  <- as.data.frame(scale(teste,  center = media, scale = desvio))
```

### 3. `nnet()`

Treina a rede. `size` = neurônios ocultos, `decay` = penalização dos pesos, `linout = TRUE` = saída linear (obrigatório em regressão).

```r
rede <- nnet(qsec ~ mpg + cyl + disp + hp + wt,
             data   = treino_esc,
             size   = 3,
             decay  = 0.01,
             linout = TRUE,
             maxit  = 500,
             trace  = FALSE)

summary(rede)$value      # erro final no treino
```

```
[1] 2.583914
```

### 4. `predict()`

Prevê no teste e desfaz a padronização para voltar a segundos.

```r
pred_esc <- predict(rede, teste_esc)
pred     <- pred_esc * desvio["qsec"] + media["qsec"]

resultado <- data.frame(
  observado = teste$qsec,
  previsto  = round(as.vector(pred), 2),
  erro      = round(teste$qsec - as.vector(pred), 2)
)
resultado
```

```
  observado previsto  erro
1     18.61    18.10  0.51
2     15.84    15.63  0.21
3     22.90    19.22  3.68
4     19.47    18.62  0.85
5     19.90    18.72  1.18
6     15.41    16.40 -0.99
7     15.50    13.83  1.67
8     14.60    15.67 -1.07
```

### 5. `rmse()` e `mae()`

Mede o erro. RMSE pune erros grandes; MAE é o erro absoluto médio. Os dois em segundos.

```r
rmse <- function(obs, prev) sqrt(mean((obs - prev)^2))
mae  <- function(obs, prev) mean(abs(obs - prev))

c(RMSE = rmse(resultado$observado, resultado$previsto),
  MAE  = mae(resultado$observado, resultado$previsto))
```

```
    RMSE      MAE
1.615371 1.270000
```

### 6. `lm()`

O baseline. Compara a rede com a regressão linear e com o chute da média.

```r
linear  <- lm(qsec ~ mpg + cyl + disp + hp + wt, data = treino)
pred_lm <- predict(linear, teste)

round(c(rede   = rmse(teste$qsec, resultado$previsto),
        linear = rmse(teste$qsec, pred_lm),
        media  = rmse(teste$qsec, mean(treino$qsec))), 3)
```

```
  rede linear  media
 1.615  1.598  2.716
```

> A linear empatou. Com 24 observações de treino, a rede não tem dados para justificar sua complexidade — e concluir isso é um resultado legítimo.

### 7. `plot()`

Observado × previsto. A linha tracejada é a previsão perfeita.

```r
plot(resultado$observado, resultado$previsto,
     xlab = "qsec observado (s)", ylab = "qsec previsto (s)",
     main = "Rede neural - mtcars", pch = 19, col = "steelblue")
abline(0, 1, lty = 2)
```

---

## A.2 · iris — classificação

Classificar a espécie a partir de 4 medidas de pétala e sépala.

### 1. Split por classe

Sorteia 75% **dentro de cada espécie**, para manter a proporção das classes.

```r
dados2  <- iris
i2      <- unlist(lapply(split(seq_len(nrow(dados2)), dados2$Species),
                         function(idx) sample(idx, round(0.75 * length(idx)))))
treino2 <- dados2[i2, ]
teste2  <- dados2[-i2, ]

table(treino2$Species)
```

```
    setosa versicolor  virginica
        38         38         38
```

### 2. `scale()`

Padroniza só os preditores. O alvo é fator e não entra.

```r
preditores <- c("Sepal.Length", "Sepal.Width", "Petal.Length", "Petal.Width")

media2  <- apply(treino2[preditores], 2, mean)
desvio2 <- apply(treino2[preditores], 2, sd)

treino2[preditores] <- scale(treino2[preditores], center = media2, scale = desvio2)
teste2[preditores]  <- scale(teste2[preditores],  center = media2, scale = desvio2)
```

### 3. `nnet()`

Sem `linout`: em classificação a saída é probabilidade, uma por classe.

```r
rede2 <- nnet(Species ~ .,
              data  = treino2,
              size  = 5,
              decay = 0.01,
              maxit = 500,
              trace = FALSE)
```

### 4. `predict(type = )`

`"class"` devolve a espécie prevista; `"raw"` devolve as probabilidades. A classe prevista é só a probabilidade maior.

```r
classe <- predict(rede2, teste2, type = "class")
prob   <- predict(rede2, teste2, type = "raw")

head(round(prob, 3))
```

```
   setosa versicolor virginica
2   0.998      0.002         0
10  0.998      0.002         0
11  0.998      0.001         0
14  0.998      0.001         0
18  0.998      0.002         0
33  0.999      0.001         0
```

### 5. `table()`

A matriz de confusão. Linhas = previsto, colunas = observado; a diagonal são os acertos.

```r
matriz <- table(previsto = classe, observado = teste2$Species)
matriz

acuracia <- sum(diag(matriz)) / sum(matriz)
round(acuracia, 3)
```

```
            observado
previsto     setosa versicolor virginica
  setosa         12          0         0
  versicolor      0         11         0
  virginica       0          1        12

[1] 0.972
```

> Um único erro, entre *versicolor* e *virginica* — as duas se sobrepõem. Nenhuma *setosa* errada: ela é linearmente separável.

### 6. `multinom()`

O baseline. É uma rede **sem camada oculta** — a diferença entre os dois é exatamente o que a camada oculta acrescentou.

```r
base2       <- multinom(Species ~ ., data = treino2, trace = FALSE)
classe_base <- predict(base2, teste2)

round(c(rede      = acuracia,
        logistica = mean(classe_base == teste2$Species),
        chute     = max(table(treino2$Species)) / nrow(treino2)), 3)
```

```
     rede logistica     chute
    0.972     0.972     0.333
```

> Empate. O `iris` é fácil: serve para conferir se o seu código está certo, não para comparar modelos.

### 7. `plot()`

Os acertos em azul, os erros em vermelho.

```r
plot(teste2$Petal.Length, teste2$Petal.Width,
     col = ifelse(classe == teste2$Species, "steelblue", "red"),
     pch = 19, xlab = "Comprimento da petala (padronizado)",
     ylab = "Largura da petala (padronizado)",
     main = "Rede neural - iris (vermelho = erro)")
```

---

# Parte B — `tidymodels`

Instale antes da aula: `install.packages("tidymodels")` baixa mais de 80 pacotes.
As saídas abaixo mostram o **formato** do resultado; os valores mudam com a semente e a versão dos pacotes.

```r
library(tidymodels)
tidymodels_prefer()   # resolve conflitos de nomes (filter, select, ...)
set.seed(2026)
```

### Equivalência entre os dois caminhos

| `nnet` direto | `tidymodels` |
|---|---|
| `sample()` nas linhas | `initial_split()` · `training()` · `testing()` |
| `scale(center=, scale=)` | `step_normalize()` |
| `nnet(size=, decay=, linout=)` | `mlp(hidden_units=, penalty=)` + `set_mode()` |
| `predict()` + desfazer a escala | `augment()` — a escala volta sozinha |
| `rmse <- function(...)` | `metric_set(rmse, rsq, mae)` |
| `table(previsto, observado)` | `conf_mat()` |

---

## B.1 · mtcars — regressão

As sete etapas, sempre nesta ordem. Valem para qualquer modelo e qualquer banco.

### 1. `initial_split()`

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

### 2. `recipe()`

Uma lista de instruções de pré-processamento. Aprende no treino e reaplica, idêntica, no teste. `bake(prep(...))` mostra o que a rede vai receber.

```r
receita <- recipe(qsec ~ mpg + cyl + disp + hp + wt, data = treino) |>
  step_normalize(all_numeric_predictors())

bake(prep(receita), new_data = NULL) |> head(3)
```

### 3. `mlp()`

A rede. `hidden_units` = `size`, `penalty` = `decay`, `epochs` = `maxit`. `translate()` mostra a chamada real ao `nnet`.

```r
modelo <- mlp(hidden_units = 3, penalty = 0.01, epochs = 500) |>
  set_engine("nnet") |>      # quem faz a conta
  set_mode("regression")     # linout = TRUE vem junto, automático

translate(modelo)
```

```
nnet::nnet.formula(formula = missing_arg(), data = missing_arg(),
                   size = 3, decay = 0.01, maxit = 500,
                   trace = FALSE, linout = TRUE)
```

### 4. `workflow()`

Junta receita e modelo. Assim o pré-processamento viaja junto do modelo — na hora de prever, nada fica para trás.

```r
fluxo <- workflow() |>
  add_recipe(receita) |>
  add_model(modelo)
```

### 5. `fit()`

Treina. A semente importa: os pesos iniciais são aleatórios.

```r
set.seed(2026)
ajuste <- fit(fluxo, data = treino)
```

### 6. `augment()`

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

### 7. `metric_set()`

As métricas prontas, com nome padronizado. RMSE e MAE em segundos; R² adimensional.

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

### + Baseline

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

### + `ggplot()`

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

## B.2 · iris — classificação

O fluxo é o mesmo. Mudam três coisas: o alvo é fator, o modo é `"classification"` e a saída vem com probabilidades.

### 1. `initial_split(strata = )`

`strata` preserva a proporção das classes no treino e no teste.

```r
set.seed(2026)
split2  <- initial_split(iris, prop = 0.75, strata = Species)
treino2 <- training(split2)
teste2  <- testing(split2)

treino2 |> count(Species)
```

### 2. `recipe()`

Mesma receita de antes: padronizar os preditores.

```r
receita2 <- recipe(Species ~ ., data = treino2) |>
  step_normalize(all_numeric_predictors())
```

### 3. `set_mode("classification")`

A única mudança relevante no modelo.

```r
modelo2 <- mlp(hidden_units = 5, penalty = 0.01, epochs = 500) |>
  set_engine("nnet") |>
  set_mode("classification")

fluxo2 <- workflow() |> add_recipe(receita2) |> add_model(modelo2)

set.seed(2026)
ajuste2 <- fit(fluxo2, data = treino2)
```

### 4. `augment()`

Devolve `.pred_class` e uma coluna de probabilidade por classe.

```r
predicoes2 <- augment(ajuste2, new_data = teste2)

predicoes2 |>
  select(Species, .pred_class, .pred_setosa, .pred_versicolor, .pred_virginica) |>
  head(4)
```

### 5. `conf_mat()`

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

### 6. `roc_auc()`

Usa as **probabilidades**, não a classe. Se houver mais de duas classes, passe todas as colunas.

```r
predicoes2 |> roc_auc(truth = Species,
                      .pred_setosa, .pred_versicolor, .pred_virginica)
```

### 7. Comparar modelos

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

Mude um parâmetro por vez e observe o efeito.

| `nnet` | `tidymodels` | efeito de aumentar |
|---|---|---|
| `size` | `hidden_units` | mais flexibilidade — e mais risco de decorar |
| `decay` | `penalty` | modelo mais suave, menos sobreajuste |
| `maxit` | `epochs` | erro de treino cai; o de teste, nem sempre |
| `set.seed()` | `set.seed()` | muda tudo — a rede não tem solução única |

---

## O que falta aqui

Validação cruzada para escolher `hidden_units` e `penalty` sem olhar o teste, `last_fit()` para abrir o teste uma única vez, importância de variáveis e curvas de resposta. Está tudo no material completo da disciplina, [uma pasta acima](../).

---

Material didático · CC BY-NC-SA 4.0 · Código dos exemplos · MIT
Departamento de Engenharia de Transportes · EESC-USP · 2026
