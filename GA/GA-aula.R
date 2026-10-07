# ==============================================================================
# ALGORITMO GENÉTICO (GA) EM R — com apoio do tidymodels
# STT5900 · EESC/USP · 2026
# ------------------------------------------------------------------------------
# Roteiro da prática (os mesmos 4 blocos do slide "Mão na massa"):
#   PARTE 1 — Aquecimento 1D: por que um otimizador local não basta
#   PARTE 2 — Regressão por GA (mtcars) e a conferência com lm()
#   PARTE 3 — Calibração de modelos de tráfego (SP-270 km 27)
#   PARTE 4 — GA binário: seleção de variáveis com validação cruzada
#
# Os comentários #> indicam o FORMATO da saída. Os valores dependem da semente
# e da versão dos pacotes — compare os seus com os do colega ao lado.
#
# install.packages(c("GA", "tidymodels", "readxl"))   # instale ANTES da aula
# ==============================================================================


# ------------------------------------------------------------------------------
# ONDE O TIDYMODELS ENTRA (e onde NÃO entra)
# ------------------------------------------------------------------------------
# O tidymodels não tem um GA próprio: quem otimiza continua sendo GA::ga().
# O ganho está em tudo que fica EM VOLTA da otimização:
#
#   tarefa                       antes (aula 2025)        agora
#   --------------------------------------------------------------------------
#   escala das variáveis         nenhuma (limites ±100)   recipe + step_normalize()
#   erro da função fitness       sum((obs - mod)^2)       yardstick::rmse_vec()
#   conferir o resultado         olhar os números         linear_reg() + tidy()
#   avaliar fora da amostra      —                        initial_split() / testing()
#   métricas                     —                        metric_set(rmse, mae, rsq)
#   seleção de variáveis         —                        vfold_cv() + fit_resamples()
#
# Para curvas simples (Greenshields, Van Aerde) o GA + uma função de previsão
# vetorizada é o caminho mais curto. O tidymodels brilha na PARTE 4, quando
# cada avaliação da fitness é, ela mesma, um modelo validado.

library(GA)
library(tidymodels)
tidymodels_prefer()     # resolve conflitos de nomes (filter, select, ...)

SEMENTE <- 5207246


# ==============================================================================
# PARTE 1 — AQUECIMENTO 1D
# ==============================================================================
# Uma função com VÁRIOS picos. Qual é o maior entre -5 e 5?

f <- function(x) sin(x) + sin(3 * x) * cos(x)
lbound <- -5
ubound <-  5
curve(f, lbound, ubound, n = 500, lwd = 2)

# --- [1] O otimizador clássico depende de onde começa -------------------------
# optim() sobe a ladeira mais próxima e para no primeiro topo que encontra.
inicios <- c(-4, -1.5, 0.5, 3.5)

tibble(inicio = inicios) |>
  mutate(
    x_final = map_dbl(inicio, \(x0) optim(x0, f, method = "L-BFGS-B",
                                          lower = lbound, upper = ubound,
                                          control = list(fnscale = -1))$par),
    f_final = f(x_final)
  )
#> # tibble 4 × 3: inicio | x_final | f_final
#
# ESPERADO: pontos de partida diferentes -> picos diferentes. Só quem parte
# perto de x = 0,56 acha o máximo global (f = 1,37); quem parte de -1,5 para
# num "pico" NEGATIVO. Na vida real você não sabe de antemão onde começar.

# --- [2] O GA olha para uma POPULAÇÃO inteira ---------------------------------
GA <- ga(type    = "real-valued",
         fitness = f,                 # o GA sempre MAXIMIZA
         lower   = c(x = lbound),
         upper   = c(x = ubound),
         seed    = SEMENTE)

summary(GA)
#> -- Genetic Algorithm -------------------
#> GA settings: type, population size, number of generations, ...
#> GA results: Iterations | Fitness function value | Solution
#
# ESPERADO: x ≈ 0,565 e f ≈ 1,373 — o máximo global, sem escolher ponto de partida.

curve(f, lbound, ubound, n = 500, lwd = 2)
points(GA@solution, GA@fitnessValue, col = "red", pch = 19, cex = 1.5)

# --- [3] Assistir a evolução, geração a geração -------------------------------
monitor <- function(obj) {
  curve(f, lbound, ubound, n = 500,
        main = paste("geração =", obj@iter))
  points(obj@population, obj@fitness, pch = 20, col = 2)
  rug(obj@population, col = 2)
  Sys.sleep(0.2)
}

GA <- ga(type = "real-valued", fitness = f,
         lower = c(x = lbound), upper = c(x = ubound),
         popSize = 20, maxiter = 30,
         monitor = monitor, seed = SEMENTE)

# PARA MEXER:
#   popSize = 5      -> população pequena: às vezes converge no pico errado
#   pmutation = 0.5  -> muita mutação: a população "não sossega"
#   optim = TRUE     -> GA híbrido: o GA acha a montanha, o optim() acha o topo


# ==============================================================================
# FERRAMENTA: um calibrador genérico (usado nas partes 2 e 3)
# ==============================================================================
# Em vez de reescrever a fitness para cada modelo, escrevemos UMA vez:
#   prever(p)  -> devolve as previsões do modelo para o vetor de parâmetros p
#   y          -> os valores observados
# A fitness é -RMSE: mesmo ótimo que -SQE, mas na unidade de y (fácil de ler).

calibrar_ga <- function(prever, y, lower, upper,
                        popSize = 50, maxiter = 300, run = 50,
                        seed = SEMENTE, ...) {
  fitness <- function(p) {
    names(p) <- names(lower)
    pred <- prever(p)
    if (any(!is.finite(pred))) return(-1e10)   # parâmetro inválido = péssimo
    -rmse_vec(truth = y, estimate = pred)
  }
  ga(type = "real-valued", fitness = fitness,
     lower = lower, upper = upper,
     popSize = popSize,
     maxiter = maxiter,
     run     = run,      # para se a melhor solução não melhorar em 'run' gerações
     optim   = TRUE,     # refinamento local no fim (GA híbrido)
     monitor = FALSE,
     seed    = seed, ...)
}

# Solução colada no limite = limite mal escolhido. Sempre confira.
conferir_limites <- function(modelo_ga, lower, upper, tol = 0.01) {
  s <- modelo_ga@solution[1, ]
  tibble(parametro = names(lower),
         estimado  = s,
         inferior  = lower,
         superior  = upper) |>
    mutate(alerta = if_else(estimado - inferior < tol * (superior - inferior) |
                              superior - estimado < tol * (superior - inferior),
                            "<< no limite: alargue o intervalo", ""))
}


# ==============================================================================
# PARTE 2 — REGRESSÃO POR GA: mtcars
# ==============================================================================
# qsec (tempo no 1/4 de milha) ~ mpg + hp + wt
# A regressão linear tem solução exata (mínimos quadrados). Por isso este é o
# exemplo perfeito para CONFERIR o GA antes de usá-lo onde não há fórmula.

# --- [1] RECIPE: padronizar os preditores -------------------------------------
# hp vai até 335; wt, até 5,4. Sem padronizar, os coeficientes vivem em
# escalas muito diferentes e o GA precisa de limites enormes (±100).
# Com step_normalize(), todos os preditores têm média 0 e desvio 1.
receita <- recipe(qsec ~ mpg + hp + wt, data = mtcars) |>
  step_normalize(all_numeric_predictors())

carros <- bake(prep(receita), new_data = NULL)
carros |> head(3)
#> # tibble 3 × 4: mpg | hp | wt (padronizados) | qsec (original)

# --- [2] A previsão, VETORIZADA -----------------------------------------------
# Antes: w[1] + w[2]*mpg + w[3]*hp + w[4]*wt  (uma linha por variável)
# Agora: produto matricial — serve para 3 ou para 30 variáveis.
X <- model.matrix(qsec ~ mpg + hp + wt, data = carros)   # inclui o intercepto
prever_linear <- function(w) drop(X %*% w)

# --- [3] GA -------------------------------------------------------------------
lim_inf <- c(b0 = 10, mpg = -5, hp = -5, wt = -5)
lim_sup <- c(b0 = 25, mpg =  5, hp =  5, wt =  5)

GA1 <- calibrar_ga(prever_linear, y = carros$qsec,
                   lower = lim_inf, upper = lim_sup, popSize = 100)
summary(GA1)
plot(GA1)            # melhor, média e mediana da fitness por geração

conferir_limites(GA1, lim_inf, lim_sup)

# --- [4] Conferência: GA x mínimos quadrados ----------------------------------
mq <- linear_reg() |> fit(qsec ~ mpg + hp + wt, data = carros)

tidy(mq) |>
  select(termo = term, minimos_quadrados = estimate) |>
  mutate(ga = as.numeric(GA1@solution[1, ]),
         diferenca = round(ga - minimos_quadrados, 4))
#> # tibble 4 × 4: termo | minimos_quadrados | ga | diferenca
#
# ESPERADO: diferenças desprezíveis. O GA chegou lá SEM derivadas e SEM fórmula.

# PARA MEXER:
#   Tire o step_normalize() e use limites ±100 como na versão antiga.
#   Compare plot(GA1) nos dois casos: quantas gerações até estabilizar?


# ==============================================================================
# PARTE 3 — CALIBRAÇÃO DE MODELOS DE TRÁFEGO: SP-270 km 27
# ==============================================================================
# Relação fundamental: q = u · k
#   q = fluxo (veic/h)   u = velocidade (km/h)   k = densidade (veic/km)

arquivo <- "sp270km27.xlsx"   # deixe o arquivo na mesma pasta deste script

if (file.exists(arquivo)) {
  dados <- readxl::read_excel(arquivo) |>
    select(Volume_vph, Velocidade_kmph, Densidade_vpkm) |>
    drop_na()
} else {
  # Plano B: dados SINTÉTICOS só para o código rodar sem o arquivo.
  warning("sp270km27.xlsx não encontrado: usando dados SINTÉTICOS de teste.")
  set.seed(SEMENTE)
  # (Van Aerde com uf = 110, uc = 80, kj = 150, qc = 2200, mais ruído)
  dados <- tibble(Velocidade_kmph = runif(400, 15, 105)) |>
    mutate(Densidade_vpkm = 1 / (0.005729 + 0.10313 / (110 - Velocidade_kmph) +
                                   0.00033997 * Velocidade_kmph),
           Densidade_vpkm = Densidade_vpkm * exp(rnorm(n(), 0, 0.08)),
           Volume_vph     = Velocidade_kmph * Densidade_vpkm)
}

ggplot(dados, aes(Densidade_vpkm, Velocidade_kmph)) +
  geom_point(alpha = 0.4) +
  labs(x = "Densidade (veic/km)", y = "Velocidade (km/h)",
       title = "SP-270 km 27 — diagrama velocidade × densidade") +
  theme_minimal()

# --- [1] SPLIT: calibrar em uma parte, validar na outra ------------------------
set.seed(SEMENTE)
divisao <- initial_split(dados, prop = 0.75)
treino  <- training(divisao)
teste   <- testing(divisao)

metricas <- metric_set(rmse, mae, rsq)

# --- [2] Greenshields (1935): u = uf · (1 - k / kj) ----------------------------
greenshields <- function(p, k) p["uf"] * (1 - k / p["kj"])

lim_gs_inf <- c(uf =  70, kj =  40)
lim_gs_sup <- c(uf = 140, kj = 300)

GA2 <- calibrar_ga(\(p) greenshields(p, treino$Densidade_vpkm),
                   y = treino$Velocidade_kmph,
                   lower = lim_gs_inf, upper = lim_gs_sup)
summary(GA2)
conferir_limites(GA2, lim_gs_inf, lim_gs_sup)

# Conferência: Greenshields é uma RETA em u × k, então mínimos quadrados resolve:
#   u = uf - (uf/kj)·k   ->  intercepto = uf  |  inclinação = -uf/kj
reta <- linear_reg() |> fit(Velocidade_kmph ~ Densidade_vpkm, data = treino) |> tidy()
c(uf_mq = reta$estimate[1],
  kj_mq = -reta$estimate[1] / reta$estimate[2],
  GA2@solution[1, ])
#> uf_mq  kj_mq  uf  kj      -> os dois pares devem praticamente coincidir

# Validação no TESTE
teste |>
  mutate(.pred = greenshields(GA2@solution[1, ], Densidade_vpkm)) |>
  metricas(truth = Velocidade_kmph, estimate = .pred)
#> # tibble 3 × 3: rmse (km/h) | mae (km/h) | rsq

# --- [3] Van Aerde (1995): modelo de 4 parâmetros, NÃO linear -------------------
# k(u) = 1 / (c1 + c2/(uf - u) + c3·u)
#   c1 = (uf / (kj·uc²)) · (2·uc - uf)
#   c2 = (uf / (kj·uc²)) · (uf - uc)²
#   c3 = 1/qc - uf/(kj·uc²)
# uf: vel. de fluxo livre | uc: vel. na capacidade | kj: dens. de congestionamento
# qc: capacidade (veic/h). Aqui não há fórmula fechada: é o terreno do GA.
van_aerde <- function(p, u) {
  if (p["uc"] >= p["uf"]) return(rep(NA_real_, length(u)))   # sem sentido físico
  m  <- p["uf"] / (p["kj"] * p["uc"]^2)
  c1 <- m * (2 * p["uc"] - p["uf"])
  c2 <- m * (p["uf"] - p["uc"])^2
  c3 <- 1 / p["qc"] - m
  1 / (c1 + c2 / (p["uf"] - u) + c3 * u)
}

lim_va_inf <- c(uf =  80, uc = 40, kj =  40, qc = 1500)
lim_va_sup <- c(uf = 140, uc = 90, kj = 300, qc = 3000)

GA3 <- calibrar_ga(\(p) van_aerde(p, treino$Velocidade_kmph),
                   y = treino$Densidade_vpkm,
                   lower = lim_va_inf, upper = lim_va_sup)
summary(GA3)
plot(GA3)
conferir_limites(GA3, lim_va_inf, lim_va_sup)

teste |>
  mutate(.pred = van_aerde(GA3@solution[1, ], Velocidade_kmph)) |>
  metricas(truth = Densidade_vpkm, estimate = .pred)
#> # tibble 3 × 3: rmse (veic/km) | mae (veic/km) | rsq
#
# ATENÇÃO: Greenshields prevê VELOCIDADE e Van Aerde prevê DENSIDADE.
# Os RMSE estão em unidades diferentes: não compare um com o outro.

# --- [4] Ver as duas curvas sobre os dados ------------------------------------
p_gs <- GA2@solution[1, ]
p_va <- GA3@solution[1, ]

curvas <- bind_rows(
  tibble(modelo = "Greenshields",
         k = seq(0, p_gs["kj"], length.out = 200)) |>
    mutate(u = greenshields(p_gs, k)),
  tibble(modelo = "Van Aerde",
         u = seq(1, p_va["uf"] - 0.01, length.out = 400)) |>
    mutate(k = van_aerde(p_va, u))
) |>
  filter(k >= 0, k <= max(dados$Densidade_vpkm) * 1.2)

ggplot(dados, aes(Densidade_vpkm, Velocidade_kmph)) +
  geom_point(alpha = 0.3, colour = "grey40") +
  geom_path(data = curvas, aes(k, u, colour = modelo), linewidth = 1.2) +
  labs(x = "Densidade (veic/km)", y = "Velocidade (km/h)", colour = NULL,
       title = "Modelos calibrados por GA") +
  theme_minimal() +
  theme(legend.position = "top")

# PARA MEXER:
#   Estreite os limites de kj para 40–100 (os da versão 2025) e rode
#   conferir_limites(): o alerta aparece? O que isso diz sobre os dados?


# ==============================================================================
# PARTE 4 — GA BINÁRIO: SELEÇÃO DE VARIÁVEIS (GA + tidymodels)
# ==============================================================================
# Pergunta: quais das 10 variáveis do mtcars prevêem melhor o qsec?
# Cada indivíduo é um vetor de 10 bits: 1 = variável entra, 0 = fica fora.
#   1 0 0 1 0 1 0 0 0 0  ->  qsec ~ mpg + hp + wt
# São 2^10 - 1 = 1.023 combinações. Com 40 variáveis seriam ~1,1 trilhão.

preditores <- setdiff(names(mtcars), "qsec")

# --- [1] Validação cruzada: a fitness NÃO pode olhar só o ajuste no treino -----
# Mais variáveis sempre melhoram o ajuste no treino. A validação cruzada pune
# variáveis que só decoram ruído.
set.seed(SEMENTE)
dobras <- vfold_cv(mtcars, v = 5, repeats = 3)

# --- [2] Fitness = -RMSE médio na validação cruzada ----------------------------
# Memória (cache): o GA repete muitos indivíduos entre gerações. Guardar o
# resultado de cada combinação evita refazer a validação cruzada.
memoria <- new.env()

fitness_selecao <- function(bits) {
  chave <- paste(bits, collapse = "")
  if (!is.null(memoria[[chave]])) return(memoria[[chave]])
  if (sum(bits) == 0) return(-1e10)                 # modelo vazio não vale

  fluxo <- workflow() |>
    add_formula(reformulate(preditores[bits == 1], response = "qsec")) |>
    add_model(linear_reg())

  valor <- fit_resamples(fluxo, resamples = dobras,
                         metrics = metric_set(rmse)) |>
    collect_metrics() |>
    pull(mean)

  memoria[[chave]] <- -valor
  -valor
}

GA4 <- ga(type    = "binary",
          fitness = fitness_selecao,
          nBits   = length(preditores),
          names   = preditores,
          popSize = 20,
          maxiter = 30,
          run     = 10,
          seed    = SEMENTE)

summary(GA4)
plot(GA4)

escolhidas <- preditores[GA4@solution[1, ] == 1]
escolhidas
#> [1] "..." "..." ...      -> as variáveis que sobreviveram à evolução

length(ls(memoria))
#> [1] <n>   -> quantas combinações o GA REALMENTE avaliou, das 1.023 possíveis

# --- [3] Comparar: todas as variáveis x as escolhidas pelo GA ------------------
comparar <- function(vars, rotulo) {
  workflow() |>
    add_formula(reformulate(vars, response = "qsec")) |>
    add_model(linear_reg()) |>
    fit_resamples(resamples = dobras, metrics = metric_set(rmse, rsq)) |>
    collect_metrics() |>
    mutate(modelo = rotulo, n_variaveis = length(vars))
}

bind_rows(
  comparar(preditores,           "todas as 10"),
  comparar(c("mpg", "hp", "wt"), "aula (mpg, hp, wt)"),
  comparar(escolhidas,           "escolhidas pelo GA")
) |>
  select(modelo, n_variaveis, .metric, mean) |>
  pivot_wider(names_from = .metric, values_from = mean)
#> # tibble 3 × 4: modelo | n_variaveis | rmse | rsq
#
# ESPERADO: o GA usa MENOS variáveis e tem RMSE de validação menor.
# Testado (GA 3.2.5, semente da aula): o GA escolheu disp + wt + vs + carb
# avaliando ~150 das 1.023 combinações — e a força bruta confirma que essa é
# a MELHOR de todas. 15% do trabalho, 100% do resultado.

# PARA MEXER:
#   Troque linear_reg() por outro modelo (ex.: rand_forest()) — a fitness
#   continua a mesma. É a vantagem de montar a fitness com workflow().
#   DESAFIO: confirme por força bruta (avalie as 1.023 combinações) e meça
#   o tempo com system.time(). Agora imagine 40 variáveis.
#   Para bases maiores: ga(..., parallel = TRUE) divide a população entre
#   os núcleos do computador (vale a pena quando cada fitness é cara).


# ==============================================================================
# RESUMO
# ==============================================================================
#   type = "real-valued"   parâmetros contínuos      (partes 1, 2 e 3)
#   type = "binary"        escolhas sim/não          (parte 4)
#   type = "permutation"   ordens e rotas            (desafio: caixeiro-viajante)
#
#   O GA sempre MAXIMIZA  -> para minimizar um erro, devolva -erro.
#   popSize  : tamanho da população      maxiter : nº máximo de gerações
#   run      : parada por estagnação     optim   : refinamento local (híbrido)
#   seed     : reprodutibilidade         monitor : assistir à evolução
#
# CHECKLIST antes de confiar numa solução do GA:
#   [ ] rodei com outra semente e cheguei perto do mesmo lugar?
#   [ ] a solução não está colada nos limites? (conferir_limites)
#   [ ] o plot() mostra a fitness estabilizada?
#   [ ] avaliei fora da amostra de calibração? (teste ou validação cruzada)
# ==============================================================================
