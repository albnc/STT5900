# Redes Neurais em R — `nnet`

**STT5900 · Engenharia de Transportes · EESC-USP · 2026**

Versão mínima: só o pacote `nnet`, que já vem instalado com o R.
Dois exemplos — prever um número (`mtcars`) e prever uma categoria (`iris`).

Script: [`RNA-simples`](RNA-simples.md) · Mesmos exemplos com tidymodels: [`RNA-tidymodels`](RNA-tidymodels.md)


---

## Definição

```
z = b + w1*x1 + w2*x2 + ... + wp*xp    # combinação linear
a = f(z)                                # ativação, não linear
```

Isso é um neurônio. A rede empilha neurônios em camadas e ajusta os pesos `w` para minimizar o erro, por retropropagação. Sem a ativação não linear `f`, empilhar camadas dá apenas outra regressão linear.

**Três regras:**

1. **Escalonar as entradas.** Sem isso a ativação satura e a rede não aprende.
2. **Separar treino e teste.** Senão você mede a memória, não o modelo.
3. **Comparar com um modelo simples.** Sem baseline, um RMSE não significa nada.

```r
library(nnet)
set.seed(2026)
```

> As saídas deste documento foram geradas com `set.seed(2026)`.

---

# Parte 1 · `mtcars` — regressão

Prever `qsec` — tempo, em segundos, para percorrer 1/4 de milha.

## 1. `sample()`

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

## 2. `scale()`

Padroniza com a média e o desvio **do treino**, e aplica os mesmos valores ao teste.

```r
media  <- apply(treino, 2, mean)
desvio <- apply(treino, 2, sd)

treino_esc <- as.data.frame(scale(treino, center = media, scale = desvio))
teste_esc  <- as.data.frame(scale(teste,  center = media, scale = desvio))
```

> Escalonar o banco inteiro antes de separar leva informação do teste para dentro do treino. É vazamento de dados — o código roda, o resultado fica otimista, ninguém percebe.

## 3. `nnet()`

Treina a rede.

| argumento | o que é |
|---|---|
| `size` | neurônios na camada oculta |
| `decay` | penalização dos pesos (regularização) |
| `linout = TRUE` | saída linear — obrigatório em regressão |
| `maxit` | máximo de iterações |
| `trace = FALSE` | não imprime o progresso |

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

## 4. `predict()`

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

## 5. RMSE e MAE

Mede o erro, os dois em segundos. RMSE pune erros grandes; MAE é o erro absoluto médio.

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

## 6. `lm()` — o baseline

Compara a rede com a regressão linear e com o chute da média.

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

## 7. `plot()`

Observado × previsto. A linha tracejada é a previsão perfeita.

```r
plot(resultado$observado, resultado$previsto,
     xlab = "qsec observado (s)", ylab = "qsec previsto (s)",
     main = "Rede neural - mtcars", pch = 19, col = "steelblue")
abline(0, 1, lty = 2)
```

---

# Parte 2 · `iris` — classificação

Classificar a espécie a partir de 4 medidas de pétala e sépala.

## 1. Split por classe

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

## 2. `scale()`

Padroniza só os preditores. O alvo é fator e não entra.

```r
preditores <- c("Sepal.Length", "Sepal.Width", "Petal.Length", "Petal.Width")

media2  <- apply(treino2[preditores], 2, mean)
desvio2 <- apply(treino2[preditores], 2, sd)

treino2[preditores] <- scale(treino2[preditores], center = media2, scale = desvio2)
teste2[preditores]  <- scale(teste2[preditores],  center = media2, scale = desvio2)
```

## 3. `nnet()`

Sem `linout`: em classificação a saída é probabilidade, uma por classe.

```r
rede2 <- nnet(Species ~ .,
              data  = treino2,
              size  = 5,
              decay = 0.01,
              maxit = 500,
              trace = FALSE)
```

## 4. `predict(type = )`

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

## 5. `table()` — matriz de confusão

Linhas = previsto, colunas = observado. A diagonal são os acertos.

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

## 6. `multinom()` — o baseline

É uma rede **sem camada oculta**. A diferença entre os dois é exatamente o que a camada oculta acrescentou.

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

## 7. `plot()`

Os acertos em azul, os erros em vermelho.

```r
plot(teste2$Petal.Length, teste2$Petal.Width,
     col = ifelse(classe == teste2$Species, "steelblue", "red"),
     pch = 19, xlab = "Comprimento da petala (padronizado)",
     ylab = "Largura da petala (padronizado)",
     main = "Rede neural - iris (vermelho = erro)")
```

---

## Resumo

| | regressão | classificação |
|---|---|---|
| alvo | numérico | `factor` |
| argumento | `linout = TRUE` | (nenhum) |
| `predict(type = )` | (padrão) | `"class"` / `"raw"` |
| métrica | RMSE, MAE | acurácia, matriz de confusão |
| baseline | `lm()` | `multinom()` |

## Para mexer

| parâmetro | teste com | efeito de aumentar |
|---|---|---|
| `size` | 1, 3, 10, 30 | mais flexibilidade — e mais risco de decorar |
| `decay` | 0, 0.01, 0.5 | modelo mais suave, menos sobreajuste |
| `maxit` | 50, 500, 5000 | erro de treino cai; o de teste, nem sempre |
| `set.seed()` | outro número | muda tudo — a rede não tem solução única |

---

Material didático · CC BY-NC-SA 4.0 · Código dos exemplos · MIT
Departamento de Engenharia de Transportes · EESC-USP · 2026
