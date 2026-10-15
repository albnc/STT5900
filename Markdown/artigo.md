---
title: "Peso, potência e transmissão: o que explica o consumo de combustível de automóveis?"
subtitle: "Um artigo-exemplo escrito em Quarto"
author:
  - name: "Seu Nome"
    affiliation: "Departamento de Engenharia de Transportes, EESC/USP"
date: today
lang: pt
abstract: |
  Este artigo investiga quais características de projeto explicam o consumo
  de combustível de automóveis, a partir do banco `mtcars`. Uma análise
  exploratória mostra que o consumo diminui com o peso, a potência e o
  número de cilindros. Um modelo de regressão linear múltipla com peso,
  potência e tipo de transmissão explica a maior parte da variação
  observada. O documento serve de modelo para a escrita de artigos
  reprodutíveis: todos os números, tabelas e figuras são gerados pelo código.
keywords: [consumo de combustível, regressão linear, Quarto, reprodutibilidade]
format:
  html:
    toc: true
    toc-depth: 2
    toc-title: "Sumário"
    number-sections: true
    fig-width: 6
    fig-height: 4
    code-fold: true
    code-summary: "Mostrar código"
  pdf:
    toc: true
    number-sections: true
    echo: false
bibliography: referencias.bib
#cls: abntex2.cls
execute:
  message: false
  warning: false
---

```{r}
#| label: setup
#| include: false
library(dplyr)
library(ggplot2)
library(knitr)

theme_set(theme_minimal(base_size = 12))

dados <- mtcars |>
  mutate(
    cilindros    = factor(cyl),
    transmissao  = factor(am, levels = c(0, 1),
                          labels = c("Automática", "Manual")),
    consumo_kml  = mpg * 0.4251,   # milhas/galão -> km/L
    peso_t       = wt * 0.4536     # 1000 lb -> toneladas
  )
```

# Introdução

O consumo de combustível é uma das variáveis centrais no planejamento de
transportes: afeta o custo operacional, as emissões e a escolha do veículo.
Entender quais características de projeto o explicam ajuda tanto o usuário
quanto o formulador de políticas.

Este estudo usa o banco clássico `mtcars`, extraído da revista *Motor Trend*
de 1974 e analisado em detalhe por @henderson1981. A análise é escrita como
um documento reprodutível, no espírito da programação letrada [@knuth1984],
com as ferramentas descritas em @xie2018 e @wickham2023.

Os objetivos são:

1. descrever o consumo dos automóveis do banco;
2. identificar as variáveis mais associadas ao consumo;
3. ajustar um modelo explicativo e interpretar seus coeficientes.

# Dados e método

## Dados

O banco contém `r nrow(dados)` automóveis e `r ncol(mtcars)` variáveis.
As unidades originais foram convertidas para o sistema métrico. As variáveis
usadas estão na @tbl-dicionario.

| Variável      | Descrição                         | Unidade     |
|:--------------|:----------------------------------|:------------|
| `consumo_kml` | Consumo de combustível            | km/L        |
| `peso_t`      | Peso do veículo                   | t           |
| `hp`          | Potência bruta                    | hp          |
| `cilindros`   | Número de cilindros               | 4, 6 ou 8   |
| `transmissao` | Tipo de transmissão               | Aut./Manual |

: Variáveis usadas na análise {#tbl-dicionario}

## Método

O consumo foi modelado por regressão linear múltipla
(@eq-modelo), estimada por mínimos quadrados ordinários:

$$
\text{Consumo}_i = \beta_0 + \beta_1\,\text{Peso}_i + \beta_2\,\text{Potência}_i
+ \beta_3\,\text{Manual}_i + \varepsilon_i
$$ {#eq-modelo}

em que $\text{Manual}_i$ vale 1 para transmissão manual e 0 para automática,
e $\varepsilon_i$ é o erro aleatório.

# Resultados

## Análise exploratória

O consumo médio é de `r round(mean(dados$consumo_kml), 1)` km/L, variando de
`r round(min(dados$consumo_kml), 1)` a `r round(max(dados$consumo_kml), 1)` km/L
(@fig-histograma).

```{r}
#| label: fig-histograma
#| fig-cap: "Distribuição do consumo de combustível"
ggplot(dados, aes(consumo_kml)) +
  geom_histogram(bins = 10, fill = "steelblue", color = "white") +
  labs(x = "Consumo (km/L)", y = "Número de automóveis")
```

A @tbl-cilindros resume as variáveis por número de cilindros: carros de 8
cilindros são mais pesados, mais potentes e consomem bem mais.

```{r}
#| label: tbl-cilindros
#| tbl-cap: "Médias por número de cilindros"
dados |>
  group_by(Cilindros = cilindros) |>
  summarise(
    `N`                = n(),
    `Consumo (km/L)`   = mean(consumo_kml),
    `Peso (t)`         = mean(peso_t),
    `Potência (hp)`    = mean(hp)
  ) |>
  kable(digits = 1)
```

A @fig-exploratoria mostra os dois padrões principais: o consumo cai com o
número de cilindros (a) e com o peso (b).

```{r}
#| label: fig-exploratoria
#| fig-cap: "Consumo de combustível segundo características do veículo"
#| fig-subcap:
#|   - "Por número de cilindros"
#|   - "Em função do peso"
#| layout-ncol: 2
ggplot(dados, aes(cilindros, consumo_kml, fill = cilindros)) +
  geom_boxplot(show.legend = FALSE) +
  labs(x = "Cilindros", y = "Consumo (km/L)")

ggplot(dados, aes(peso_t, consumo_kml, color = transmissao)) +
  geom_point(size = 2) +
  geom_smooth(method = "lm", formula = y ~ x, se = FALSE) +
  labs(x = "Peso (t)", y = "Consumo (km/L)", color = "Transmissão")
```

## Modelo de regressão

```{r}
#| label: modelo
modelo <- lm(consumo_kml ~ peso_t + hp + transmissao, data = dados)
r2     <- summary(modelo)$r.squared
coefs  <- coef(modelo)
```

O modelo da @eq-modelo explica `r round(100 * r2, 1)`% da variação do
consumo ($R^2$ = `r round(r2, 3)`). Os coeficientes estão na @tbl-modelo.

```{r}
#| label: tbl-modelo
#| tbl-cap: "Coeficientes do modelo de regressão (variável resposta: consumo em km/L)"
summary(modelo)$coefficients |>
  as.data.frame() |>
  setNames(c("Estimativa", "Erro padrão", "t", "p-valor")) |>
  `rownames<-`(c("Intercepto", "Peso (t)", "Potência (hp)",
                 "Transmissão manual")) |>
  kable(digits = 3)
```

Cada tonelada adicional reduz o consumo em cerca de
`r abs(round(coefs["peso_t"], 1))` km/L, mantidas as demais variáveis
constantes. A @fig-residuos indica que os resíduos não apresentam padrão
evidente em relação aos valores ajustados.

```{r}
#| label: fig-residuos
#| fig-cap: "Resíduos versus valores ajustados"
ggplot(data.frame(ajustado = fitted(modelo), residuo = resid(modelo)),
       aes(ajustado, residuo)) +
  geom_hline(yintercept = 0, linetype = "dashed") +
  geom_point(size = 2) +
  labs(x = "Consumo ajustado (km/L)", y = "Resíduo (km/L)")
```

# Discussão

O peso aparece como o principal determinante do consumo, resultado coerente
com a física do movimento: mais massa exige mais energia para acelerar e
vencer a resistência ao rolamento. A potência tem efeito negativo menor, e o
efeito da transmissão manual, que parece grande na @fig-exploratoria, diminui
quando o peso é controlado — carros manuais do banco são, em média, mais leves.

As limitações principais são a amostra pequena e antiga (`r nrow(dados)`
modelos de 1973–74) e a ausência de variáveis aerodinâmicas.

# Conclusão

Peso e potência explicam a maior parte da variação no consumo dos automóveis
analisados. Do ponto de vista da escrita, o ganho do Quarto é que, ao trocar
o banco de dados e clicar em **Render**, todos os números do texto, as tabelas
e as figuras são atualizados automaticamente.

# Referências {.unnumbered}

::: {#refs}
:::
