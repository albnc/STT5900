# Escrevendo com Markdown e Quarto no RStudio — aula prática 2026

**STT5900 · Departamento de Engenharia de Transportes · EESC/USP**
Prof. Dr. André Luiz Barbosa Nunes da Cunha

> Roteiro curto para escrever um texto/artigo reprodutível: texto + código +
> referências + tabelas + sumário, tudo num arquivo só.
> O exemplo completo está em [`artigo.qmd`](artigo.qmd) e as referências em
> [`referencias.bib`](referencias.bib).

---

## 0. Antes de começar

| O quê | Para quê |
|---|---|
| **Markdown** | Linguagem de marcação simples: texto puro com alguns símbolos (`#`, `*`, `-`) |
| **Quarto** (`.qmd`) | Markdown + código executável → gera HTML, Word, PDF, slides |
| **RStudio** | Editor que já vem com o Quarto embutido |

Requisitos: R, RStudio recente e os pacotes abaixo.

```r
install.packages(c("rmarkdown", "knitr", "dplyr", "ggplot2"))
# Só se for gerar PDF:
# install.packages("tinytex"); tinytex::install_tinytex()
```

---

## 1. Escrever o texto

### Criar o arquivo

1. **File → New File → Quarto Document…**
2. Dê um título, escolha **HTML** e desmarque *"Use visual markdown editor"* (por enquanto).
3. Salve como `artigo.qmd` **na mesma pasta** onde ficará o `referencias.bib`.
4. Clique em **Render** (`Ctrl + Shift + K`).

### O cabeçalho YAML

Tudo entre os `---` no topo configura o documento:

```yaml
---
title: "Meu primeiro artigo"
author: "Seu Nome"
date: today
lang: pt
format: html
---
```

### Sintaxe básica

| Você escreve | Resultado |
|---|---|
| `# Título` / `## Subtítulo` | Títulos de nível 1 e 2 |
| `**negrito**` / `*itálico*` | **negrito** / *itálico* |
| `` `codigo` `` | `codigo` |
| `- item` | Lista com marcadores |
| `1. item` | Lista numerada |
| `[USP](https://www.usp.br)` | [USP](https://www.usp.br) |
| `![Legenda](img/foto.png)` | Imagem com legenda |
| `> citação` | Bloco de citação |
| `$E = mc^2$` | Equação em linha (LaTeX) |
| `$$ y = \beta_0 + \beta_1 x $$` | Equação em destaque |

> **Dica:** deixe **uma linha em branco** entre parágrafos, listas e títulos.
> É a causa nº 1 de "por que minha lista não apareceu?".

O **editor visual** (botão *Visual* no topo) funciona como um Word: útil para
quem está começando, mas o arquivo continua sendo Markdown puro.

---

## 2. Adicionar código e rodar

### Blocos de código (*chunks*)

Insira com `Ctrl + Alt + I`:

````markdown
```{r}
#| label: setup
#| message: false
library(dplyr)
dados <- mtcars
summary(dados$mpg)
```
````

- Rode um bloco: botão ▶ verde ou `Ctrl + Shift + Enter`.
- Rode uma linha: `Ctrl + Enter`.
- **Render** roda tudo do zero, numa sessão limpa → garante reprodutibilidade.

### Opções mais usadas (linhas `#|`)

- `#| echo: false` → mostra o resultado, esconde o código
- `#| eval: false` → mostra o código, não executa
- `#| message: false` / `#| warning: false` → esconde mensagens/avisos
- `#| fig-cap: "..."` → legenda da figura
- `#| label: fig-nome` → rótulo para referência cruzada

### Código dentro do texto

```markdown
O banco tem `r nrow(mtcars)` automóveis e consumo médio de
`r round(mean(mtcars$mpg), 1)` mpg.
```

Vira: *O banco tem 32 automóveis e consumo médio de 20.1 mpg.*
Mudou o dado? O número no texto muda sozinho.

---

## 3. Citações e tabelas

### Referências

1. Crie um arquivo `.bib` (exportado do Zotero, Mendeley, Google Scholar…).
   Exemplo: [`referencias.bib`](referencias.bib).
2. Aponte no YAML:

```yaml
bibliography: referencias.bib
```

3. Cite pela chave:

| Você escreve | Resultado (aprox.) |
|---|---|
| `[@knuth1984]` | (Knuth 1984) |
| `@knuth1984` | Knuth (1984) |
| `[@knuth1984; @xie2018]` | (Knuth 1984; Xie, Allaire e Grolemund 2018) |
| `[@wickham2023, p. 10]` | (Wickham et al. 2023, p. 10) |
| `[-@knuth1984]` | (1984) |

A lista de referências é gerada no fim do documento. Para controlar onde ela
aparece:

```markdown
# Referências {.unnumbered}

::: {#refs}
:::
```

> **Atalho:** no editor visual, **Insert → Citation** busca por DOI e já
> adiciona a entrada ao `.bib`.
> **ABNT:** baixe `abntex2.csl` no
> [repositório de estilos do Zotero](https://www.zotero.org/styles), salve na
> pasta e acrescente `csl: abntex2.csl` no YAML.

### Tabelas digitadas

```markdown
| Variável | Descrição | Unidade      |
|:---------|:----------|:-------------|
| `mpg`    | Consumo   | milhas/galão |
| `wt`     | Peso      | 1000 lb      |

: Variáveis usadas na análise {#tbl-dicionario}
```

`:---` alinha à esquerda, `---:` à direita, `:---:` ao centro.

### Tabelas geradas por código

````markdown
```{r}
#| label: tbl-resumo
#| tbl-cap: "Consumo médio por número de cilindros"
mtcars |>
  dplyr::group_by(cyl) |>
  dplyr::summarise(mpg_medio = mean(mpg)) |>
  knitr::kable(digits = 1)
```
````

### Referência cruzada

Rótulos com prefixo `tbl-`, `fig-`, `eq-` ou `sec-` são numerados
automaticamente:

```markdown
Os resultados estão na @tbl-resumo e na @fig-dispersao.
```

→ *Os resultados estão na Tabela 2 e na Figura 1.*

---

## 4. Gerar o índice (sumário)

Basta configurar no YAML:

```yaml
format:
  html:
    toc: true            # liga o sumário
    toc-depth: 2         # até ## (subtítulos)
    toc-title: "Sumário"
    number-sections: true  # numera 1, 1.1, 1.2...
```

- Para tirar uma seção da numeração: `# Referências {.unnumbered}`.
- O mesmo arquivo gera outros formatos — só acrescente no YAML:

```yaml
format:
  html: default
  docx: default
  pdf: default   # exige tinytex
```

e escolha o formato na setinha ao lado do botão **Render**.

---

## 5. Juntando tudo: um artigo sendo produzido

O arquivo [`artigo.qmd`](artigo.qmd) é um artigo completo sobre o consumo de
combustível dos carros do `mtcars`. Abra-o ao lado do HTML renderizado e
acompanhe como cada parte do artigo usa um recurso da aula:

| Parte do artigo | Recurso Quarto usado |
|---|---|
| Título, autor, afiliação, **resumo** e palavras-chave | YAML: `abstract:`, `keywords:`, `author: affiliation:` |
| Bloco `setup` invisível | Chunk com `#| include: false` (carrega pacotes, converte unidades) |
| Introdução com citações | `@henderson1981`, `[@knuth1984]` |
| Tabela de variáveis | Tabela digitada + `{#tbl-dicionario}` |
| Método com equação numerada | `$$ ... $$ {#eq-modelo}` e `@eq-modelo` |
| Números no texto (média, mín., máx., R²) | Código em linha `` `r ...` `` |
| Histograma | Chunk com `#| label: fig-histograma` e `fig-cap` |
| Tabela de médias por cilindros | `kable()` + `#| label: tbl-cilindros` |
| Painel com dois gráficos (a) e (b) | `#| layout-ncol: 2` + `fig-subcap` |
| Tabela de coeficientes do modelo | `lm()` + `kable()` |
| Gráfico de resíduos | Diagnóstico do modelo como figura numerada |
| Código escondido no HTML | `code-fold: true` no YAML |
| Versão Word sem código | `docx: echo: false` no YAML |
| Sumário e numeração das seções | `toc: true`, `number-sections: true` |
| Lista de referências no final | `::: {#refs}` |

> **Experimente:** troque `transmissao` por `cilindros` no `lm()` e clique em
> **Render**. O R², a tabela de coeficientes e o gráfico de resíduos mudam
> sozinhos. O texto da Discussão, não: o **texto continua sendo sua
> responsabilidade**.

---

## 6. Exercício

1. Abra [`artigo.qmd`](artigo.qmd) no RStudio e clique em **Render**.
2. Inclua `cilindros` no modelo `lm()`, renderize e anote o que mudou
   sozinho e o que você precisa reescrever.
3. Acrescente uma figura nova (por exemplo, `consumo_kml` × `hp`) com
   legenda e cite-a no texto com `@fig-...`.
4. Acrescente ao `.bib` uma referência da sua pesquisa (copie o BibTeX do
   Google Scholar) e cite-a no texto.
5. Crie uma tabela digitada com legenda e faça referência a ela com `@tbl-...`.
6. Gere a versão **Word** (`docx`) e confira se o sumário apareceu.

---

## Fontes

- Quarto — [Markdown Basics](https://quarto.org/docs/authoring/markdown-basics.html)
- Quarto — [Citations](https://quarto.org/docs/authoring/citations.html) ·
  [Cross References](https://quarto.org/docs/authoring/cross-references.html) ·
  [Tables](https://quarto.org/docs/authoring/tables.html)
- [Markdown Guide](https://www.markdownguide.org/)
- Xie, Allaire e Grolemund (2018). [*R Markdown: The Definitive Guide*](https://bookdown.org/yihui/rmarkdown/)
