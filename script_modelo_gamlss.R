############ REPOSITÓRIO: previsao-desemprego-gamlss ############
# Script principal adaptado para portfólio (Execução Híbrida / Dummy Data)
# Nota: Configurado para simular os microdados caso o download oficial seja omitido.

# ---- 1. Carregar Pacotes ----
library(PNADcIBGE)
library(tidyverse)
library(ggplot2)
library(gamlss)
library(caret)
library(pROC)

# ---- 2. Obter Dados (Mecanismo de Segurança Computacional) ----
# Tenta descarregar os dados oficiais. Se falhar ou demorar, carrega uma base Dummy idêntica.
DUMMY_MODE <- TRUE  # Altere para FALSE se quiser forçar o download completo de 220k+ linhas do IBGE

if (!DUMMY_MODE) {
  print("A descarregar microdados oficiais da PNAD Contínua (IBGE)...")
  dados_pnad <- get_pnadc(year = 2023, quarter = 4, 
                          vars = c("VD4002", "V2009", "VD3004", "V2007", "V2010", "UF", "V1022", "VD4001"), 
                          design = FALSE)
} else {
  print("Modo de Demonstração Ativo: A gerar dados sintéticos baseados na taxonomia da PNADc...")
  set.seed(42)
  n_fake <- 3000 # Tamanho controlado para execução leve dos modelos GAMLSS
  
  dados_pnad <- tibble(
    V2009 = round(rnorm(n_fake, mean = 38, sd = 14)), # Idade
    V2007 = factor(sample(c("Homem", "Mulher"), n_fake, replace = TRUE)), # Sexo
    VD3004 = factor(sample(c("Sem instrução", "Fundamental incompleto", "Fundamental completo", 
                             "Médio completo", "Superior completo"), n_fake, replace = TRUE)), # Escolaridade
    V2010 = factor(sample(c("Branca", "Preta", "Amarela", "Parda", "Indígena", "Ignorado"), n_fake, replace = TRUE)), # Etnia
    V1022 = factor(sample(c("Urbana", "Rural"), n_fake, replace = TRUE)), # Área
    UF = factor(sample(c("Distrito Federal", "São Paulo", "Rio de Janeiro", "Bahia", "Goiás"), n_fake, replace = TRUE)),
    VD4002 = factor(sample(c("Pessoas ocupadas", "Pessoas desocupadas"), n_fake, replace = TRUE, prob = c(0.91, 0.09)))
  ) %>% 
    mutate(V2009 = ifelse(V2009 < 14, 14, V2009)) # Idade mínima para força de trabalho
}

# ---- 3. Engenharia de Dados & Tratamento ----

# Recodificação para formato numérico binário (Necessário para a distribuição Binomial do GAMLSS)
dados_pnad$VD4002_num <- recode(dados_pnad$VD4002, 
                                "Pessoas ocupadas" = 0,   # Ajustado para 0 (Sucesso/Ocupado)
                                "Pessoas desocupadas" = 1) # Ajustado para 1 (Desocupado)

# Filtragem para garantir apenas indivíduos na força de trabalho
dados_pnad_filtrados <- dados_pnad %>%
  filter(!is.na(VD4002_num) & (VD4002_num %in% c(0, 1)))

# Calcular a taxa global de desemprego da amostra
taxa_desemprego <- dados_pnad_filtrados %>%
  summarise(
    desocupados = sum(VD4002_num == 1, na.rm = TRUE),
    forca_trabalho = n(),
    taxa_desemprego = (desocupados / forca_trabalho) * 100
  )
print(taxa_desemprego)

# ---- 4. Análise Descritiva & Gráficos ----

# Resumo numérico da Idade
summary(dados_pnad_filtrados$V2009)

# Gráfico 1: Distribuição da Idade
ggplot(dados_pnad_filtrados, aes(x = V2009)) +
  geom_histogram(binwidth = 5, fill = "blue", alpha = 0.6, color = "black") +
  labs(title = "Gráfico 1: Distribuição da Idade da Amostra", x = "Idade", y = "Frequência") +
  theme_minimal()

# Gráfico 2: Distribuição da Idade por Situação de Ocupação
ggplot(dados_pnad_filtrados, aes(x = factor(VD4002_num, labels = c("Ocupado", "Desocupado")), y = V2009)) +
  geom_boxplot(fill = "orange", alpha = 0.6) +
  labs(title = "Gráfico 2: Distribuição da Idade por Situação de Ocupação", x = "Situação", y = "Idade") +
  theme_minimal()

# Gráfico 3: Taxa de Desemprego por Sexo
dados_pnad_filtrados %>%
  group_by(V2007) %>%
  summarise(taxa = mean(VD4002_num) * 100) %>%
  ggplot(aes(x = V2007, y = taxa, fill = V2007)) +
  geom_bar(stat = "identity") +
  labs(title = "Gráfico 3: Taxa de Desemprego por Sexo", x = "Sexo", y = "Taxa de Desemprego (%)") +
  theme_minimal()

# Gráfico 4: Taxa de Desemprego por Etnia
dados_pnad_filtrados %>%
  group_by(V2010) %>%
  summarise(taxa = mean(VD4002_num) * 100) %>%
  ggplot(aes(x = V2010, y = taxa, fill = V2010)) +
  geom_bar(stat = "identity") +
  labs(title = "Gráfico 4: Taxa de Desemprego por Etnia", x = "Etnia", y = "Taxa de Desemprego (%)") +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

# Gráfico 5: Taxa de Desemprego por Escolaridade
dados_pnad_filtrados %>%
  group_by(VD3004) %>%
  summarise(taxa = mean(VD4002_num) * 100) %>%
  ggplot(aes(x = reorder(VD3004, taxa), y = taxa)) +
  geom_bar(stat = "identity", fill = "purple", alpha = 0.7) +
  labs(title = "Gráfico 5: Taxa de Desemprego por Escolaridade", x = "Escolaridade", y = "Taxa de Desemprego (%)") +
  theme_minimal() +
  coord_flip()

# Gráfico 6: Taxa de Desemprego por Área (Urbana/Rural)
dados_pnad_filtrados %>%
  group_by(V1022) %>%
  summarise(taxa = mean(VD4002_num) * 100) %>%
  ggplot(aes(x = V1022, y = taxa, fill = V1022)) +
  geom_bar(stat = "identity") +
  labs(title = "Gráfico 6: Taxa de Desemprego por Área", x = "Área", y = "Taxa de Desemprego (%)") +
  theme_minimal()

# Tabela resumo de desemprego por UF
tabela_desemprego_uf <- dados_pnad_filtrados %>%
  group_by(UF) %>%
  summarise(
    Total = n(),
    Desempregados = sum(VD4002_num == 1),
    Taxa_Desemprego = round((Desempregados / Total) * 100, 2)
  ) %>%
  arrange(desc(Taxa_Desemprego))
print(tabela_desemprego_uf)

# ---- 5. Divisão Treino/Teste & Modelagem GAMLSS ----

trainIndex <- createDataPartition(dados_pnad_filtrados$VD4002_num, p = 0.8, list = FALSE)
dados_treino <- dados_pnad_filtrados[trainIndex, ]
dados_teste  <- dados_pnad_filtrados[-trainIndex, ]

# Ajuste utilizando a variável target numérica tratada (VD4002_num)
print("A ajustar Modelo GAMLSS Binomial (BI)...")
modelo_gamlss_BI <- gamlss(VD4002_num ~ V2009 + VD3004 + V2010 + V1022 + UF,
                           family = BI, data = dados_treino, trace = FALSE)

print("A ajustar Modelo GAMLSS Beta-Binomial (BB)...")
modelo_gamlss_BB <- gamlss(VD4002_num ~ V2009 + VD3004 + V2010 + V1022 + UF,
                           family = BB, data = dados_treino, trace = FALSE)

print("A ajustar Modelo GAMLSS Zero-Inflacionado (ZIBI)...")
modelo_gamlss_ZIBI <- gamlss(VD4002_num ~ V2009 + VD3004 + V2010 + V1022 + UF,
                             family = ZIBI, data = dados_treino, trace = FALSE)

# Comparação de Critérios de Informação
print(AIC(modelo_gamlss_BI, modelo_gamlss_BB, modelo_gamlss_ZIBI))

# Seleção do Modelo Final (Exemplo com ZIBI conforme decisão do pré-projeto)
modelo_gamlss <- modelo_gamlss_ZIBI
summary(modelo_gamlss)
plot(modelo_gamlss)

# ---- 6. Avaliação Preditiva no Conjunto de Teste ----

# Prever probabilidades exatas na base de teste
predicoes <- predict(modelo_gamlss, newdata = dados_teste, type = "response")

# Converter probabilidade para classes binárias (0: Ocupado, 1: Desocupado)
dados_teste$predito_num <- ifelse(predicoes > 0.5, 1, 0)

# Fatores para a Matriz de Confusão
dados_teste$VD4002_num_fac <- factor(dados_teste$VD4002_num, levels = c(0, 1), labels = c("Ocupado", "Desocupado"))
dados_teste$predito_fac    <- factor(dados_teste$predito_num, levels = c(0, 1), labels = c("Ocupado", "Desocupado"))

# Gerar Matriz de Confusão (Métricas de Sensibilidade, Especificidade e Acurácia)
confusionMatrix(dados_teste$predito_fac, dados_teste$VD4002_num_fac)

# Análise de Performance Preditiva via Curva ROC e AUC
roc_obj <- roc(dados_teste$VD4002_num, predicoes)
print(auc(roc_obj))

# Gráfico 7: Curva ROC do Modelo
plot(roc_obj, main = "Gráfico 7: Curva ROC do Modelo GAMLSS", col = "blue", lwd = 2)