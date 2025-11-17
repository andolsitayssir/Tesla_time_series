library(quantmod)
install.packages("tidyverse")
library(tidyverse)
   
library(rugarch)    
library(fpp2)      
library(forecast)
install.packages("prophet")
library(prophet)
library(dynlm)
library(ggplot2)
library(dplyr)
install.packages("tseries")
library(tseries)
install.packages("vars")    
library(vars)
library(zoo)
library(corrplot)
library(rugarch)
library(sandwich)
library(prophet)
# --- Partie 1 : IMPORTATION ET PR2PARATION DES DONNEES ----
getSymbols("TSLA", src = "yahoo", from = "2020-01-01", to = Sys.Date(), auto.assign = TRUE)
tsla_data=data.frame(
  Date = index(TSLA),    
  Open = as.numeric(Op(TSLA)),
  High = as.numeric(Hi(TSLA)),
  Low = as.numeric(Lo(TSLA)),
  Close = as.numeric(Cl(TSLA)),
  Volume = as.numeric(Vo(TSLA)),
  Adjusted = as.numeric(Ad(TSLA))
)

nrow(tsla_data)
ncol(tsla_data)
head(tsla_data)

tsla_data$Returns <- c(NA, diff(log(tsla_data$Close)) )
tsla_data$Volume_Change <- c(NA, diff(log(tsla_data$Volume)) )
tsla_data$Price_Range <- ((tsla_data$High - tsla_data$Low) / tsla_data$Close) 
library(TTR)
tsla_data$RSI <- RSI(tsla_data$Close, n = 14)
#what is rsi 
# rsi mesure la rapididité du mouvement des prix pour identifier les conditions de surachat ou de survente
tsla_data <- na.omit(tsla_data)
head(tsla_data)


summary(tsla_data[, c("Close", "Returns", "Volume_Change", "Price_Range")])

n_obs <- nrow(tsla_data) #
train_size <- round(0.9 * n_obs)
test_size <- n_obs - train_size

train_data <- tsla_data[1:train_size, ]
test_data <- tsla_data[(train_size + 1):n_obs, ]

# --- Partie 2 : ANALYSE ----
#2.1 visualisation
plot(tsla_data$Date, tsla_data$Close, type="l", col="blue", lwd=1.5,
     main="Prix de clôture Tesla", xlab="Date", ylab="Prix ($)")


plot(tsla_data$Date, tsla_data$Returns, type="l", col="red", lwd=1,
     main="Rendements logarithmiques", xlab="Date", ylab="Rendements (%)")

plot(tsla_data$Date, tsla_data$Volume/1e6, type="l", col="darkgreen", lwd=1,
     main="Volume d'échange", xlab="Date", ylab="Volume (Millions)")


plot(tsla_data$Date, tsla_data$Price_Range, type="l", col="purple", lwd=1,
     main="Volatilité intraday (Range)", xlab="Date", ylab="Range (%)")

plot(train_data$Date, train_data$RSI, type="l", col="purple", lwd=1.5,
     main="RSI (Relative Strength Index)", 
     xlab="Date", ylab="RSI")
#2.2 tests de stationnarité

adf.test(train_data$Close)
#p_value >> 0.05 donc on ne rejette pas H0
# La série des prix n'est pas stationnaire

adf.test(train_data$Returns)
#p_value < 0.05 donc on rejette H0
# La série des rendements est stationnaire

adf.test(train_data$Volume_Change)
#p_value < 0.05 donc on rejette H0
# La série des variations de volume est stationnaire

#2.3 decomposotion
ts_price = ts(tsla_data$Close, frequency=252)
decomp_price = decompose(ts_price)
plot(decomp_price)
# Trend: Croissance exponentielle
# Seasonal: Motif annuel régulier
# Random: Forte volatilité résiduelle

ts_returns = ts(tsla_data$Returns, frequency=252)
decomp_returns = decompose(ts_returns)
plot(decomp_returns)
# Trend: Stationnaire
# Seasonal: Léger motif annuel
# Random: Volatilité résiduelle

# 2.4 ACF et PCAF
acf(train_data$Returns, main="ACF des Rendements de Tesla")
# La décroissance rapide de l'ACF indique une série stationnaire
# Les rendements ne présentent pas de dépendance significative à long terme
pacf(train_data$Returns, main="ACF des Rendements au Carré de Tesla")
# Quelques pics dans la PACF mais non significatifs
# Confirme l'absence d'autocorrélation linéaire forte

acf(train_data$Returns^2, main="ACF des Rendements au Carré de Tesla")
# Plusieurs lags hors des bandes de confiance
# Indique une dépendance dans la variance → Effet ARCH/GARCH possible
pacf(train_data$Returns^2, main="PACF des Rendements au Carré de Tesla")
# Quelques lags significatifs
# Confirme la présence d'une dépendance conditionnelle dans la variance


# Detection des outliers 
boxplot(tsla_data$Returns, main="Boxplot des Rendements de Tesla", ylab="Rendements (%)")
q1 <- quantile(train_data$Returns, 0.25)
q3 <- quantile(train_data$Returns, 0.75)
iqr <- q3 - q1
lower_bound <- q1 - 3 * iqr  # 3*IQR pour outliers extrêmes
upper_bound <- q3 + 3 * iqr

outliers_idx <- which(train_data$Returns < lower_bound | train_data$Returns > upper_bound)
outliers <- train_data[outliers_idx, c("Date", "Returns", "Close", "Volume")]
cat("Nombre d'outliers détectés:", nrow(outliers), "\n")


cor_vars <- train_data[, c("Returns", "Volume_Change", "Price_Range")]
cor_matrix <- cor(cor_vars, use="complete.obs")
print(round(cor_matrix, 3))

corrplot(cor_matrix, method="color", type="upper", 
         addCoef.col="black", tl.col="black", 
         title="Corrélation entre variables", mar=c(0,0,2,0))


# préparation des séries temporelles
ts_returns = ts(train_data$Returns, frequency=252)
ts_volume= ts(train_data$Volume_Change, frequency=252)
ts_close= ts(train_data$Close, frequency=252)
#=======================================#
#PARTIE 3 : MODELISATION CLASSIQUE
#=======================================#
h= 10 # horizon de prévision

k=5 # nombre de folds pour cross validation
n=nrow(test_data)
fold_size = floor(n / h)
# ---------------
#3.1 model ARIMA
# ---------------

   
arima_model = auto.arima(ts_returns,seasonal=FALSE,stepwise=FALSE,approximation=FALSE)

summary(arima_model)
checkresiduals(arima_model)

Box.test(residuals(arima_model), lag=20, type="Ljung-Box")
#p-value >> 0.05 donc on ne rejette pas H0
# Pas d'autocorrélation significative
#bruit blanc des residus


arima_forecast <- forecast(arima_model, h=h)
plot(arima_forecast, main="Prévisions ARIMA")
arima_forecast

arima_acc <- accuracy(arima_forecast, test_data$Returns[1:h])
arima_acc
#cross validation arima
cross_val_results_arima = c()

for (i in 1:(k-1)){
  
train_fold <- train_data[1:(fold_size*i), ]
test_fold <- train_data[(fold_size*i+1):(fold_size*(i+1)), ]
arima_cross_v <- auto.arima(ts(train_fold$Returns, frequency=252))
  fc_cv <- forecast(arima_cross_v, h=nrow(test_fold))
  cross_val_results_arima[i] <- accuracy(fc_cv, test_fold$Returns)[2, "RMSE"]
  

}
mean(cross_val_results_arima)
# RMSE= 0.06 , le model arima capture bien les rendements

# modele SARIMA
sarima_model = auto.arima(ts_returns, seasonal=TRUE)
summary(sarima_model)
checkresiduals(sarima_model)
Box.test(residuals(sarima_model), lag=20, type="Ljung-Box")
#p_value >> 0.05 donc on ne rejette pas H0

sarima_forcast <- forecast(sarima_model, h=h)
plot(sarima_forcast, main="Prévisions SARIMA")
sarima_forcast

sarima_acc <- accuracy(sarima_forcast, test_data$Returns[1:h])
sarima_acc

# cross validation sarima
cross_val_results_sarima = c()
for (i in 1:(k-1)){
  
  train_fold <- train_data[1:(fold_size*i), ]
  test_fold <- train_data[(fold_size*i+1):(fold_size*(i+1)), ]
  sarima_cross_v <- auto.arima(ts(train_fold$Returns, frequency=252), seasonal=TRUE)
  fc_cv <- forecast(sarima_cross_v, h=nrow(test_fold))
  cross_val_results_sarima[i] <- accuracy(fc_cv, test_fold$Returns)[2, "RMSE"]
  
}
mean(cross_val_results_sarima)
#RMSE= 0.072 , le model sarima capture bien les rendements

# ---------
# model var
# ---------
var_data = window(ts.union(ts_returns, ts_volume), end=c(length(ts_returns),1))
VARselect(var_data, lag.max=10, type="const")

var_model = VAR(var_data, p=3, type="const")
var_summary = summary(var_model)
#equation 1 de ts_returns
#Les rendements passés (t-1, t-2, t-3) et les variations de volume passées (t-1, t-2, t-3) n'ont PAS de pouvoir prédictif sur les rendements futurs
#equation 2 ts_volume
#Le volume passé (t-1, t-2, t-3) prédit le volume futur (autocorrélation)
#Les rendements passés (t-2, t-3) influencent le volume futur

serial_test = serial.test(var_model, lags.pt=16, type="PT.asymptotic")
#p_value <<<0.05 donc on rejette H0
# Présence d'autocorrélation dans les résidus


# Causalité de Granger
# Test 1 : Est-ce que Volume_Change cause Returns ?
granger_ts_returns = causality(var_model, cause = "ts_volume")$Granger
granger_ts_volume = causality(var_model, cause = "ts_returns")$Granger

var_forcast = predict(var_model, n.ahead=h)
plot(var_forcast)
var_forcast

var_residuals_cov <- cov(residuals(var_model))
var_residuals_cov
#==================================# 
#PARTIE 4 : MODELISATION GARCH  
#==================================#

#ARCH(1) model
spec_arch = ugarchspec(variance.model = list(model = "sGARCH", garchOrder = c(1,0)),
                        mean.model = list(armaOrder = c(0,0), include.mean = TRUE),
                        distribution.model = "norm")
fit_arch = ugarchfit(spec = spec_arch, data = ts_returns)
summary(fit_arch)
show(fit_arch)
#p_value = 0.99 >>0.05
#on ne rejette pas h0
# Pas d'autocorrélation significative dans les résidus standardisés
#alpha1 proche de 1 => non stationnaire
#les paramatre ne sont pas stables dans le temps mu>0.75
#asymetrie non capture sign bias test t_value <<<<<< 0.0000001
#test de pearson p=0 distribution normale non adapté
res_arch = residuals(fit_arch, standardize=TRUE)
acf(res_arch, main="ACF des résidus standardisés ARCH(1)")
Box.test(res_arch, lag=20, type="Ljung-Box")




#GARCH(1,1) model
spec_garch = ugarchspec(variance.model = list(model = "sGARCH",
                                             garchOrder = c(1,1)),
                          mean.model = list(armaOrder = c(0,0), include.mean = TRUE),
                          distribution.model = "norm")
fit_garch = ugarchfit(spec = spec_garch, data = ts_returns)
summary(fit_garch)
show(fit_garch)
#alpha1 =0.06 <1 model stationnaire 
#alpha1>>beta1 votalité persistente
#residus p_value >>0.05 donc on ne rejette pas h0
# Pas d'autocorrélation significative dans les résidus standardisés
#parametre stable : mu , omega < 0.75 
#sign bias test t_value > 0.05
# (-)test goodness to fit p_value tres petite 

res_garch = residuals(fit_garch, standardize=TRUE)
acf(res_garch, main="ACF des résidus standardisés GARCH(1,1)")
Box.test(res_garch, lag=20, type="Ljung-Box")

#garch avec distribution student-t
spec_garch_student <- ugarchspec(
  variance.model = list(model = "sGARCH", garchOrder = c(1, 1)),
  mean.model = list(armaOrder = c(0, 0), include.mean = TRUE),
  distribution.model = "std"  # ← Distribution Student-t
)
fit_garch_student = ugarchfit(spec = spec_garch_student, data = ts_returns)
summary(fit_garch_student)
show(fit_garch_student)
#model gargh avec distribution student est plus adapté aux rendements de Tesla
#amelioration des tests de diagnostic
#les p_values des tests de diagnostic sont plus élevées qu'avec la distribution normale

# cross validation arch , garch
cross_validation_arch=c()
cross_validation_garch=c()
for (i in 1:(k-1)){
  
  train_fold <- train_data[1:(fold_size*i), ]
  test_fold <- train_data[(fold_size*i+1):(fold_size*(i+1)), ]
  
  spec_arch_cv = ugarchspec(variance.model = list(model = "sGARCH", garchOrder = c(1,0)),
                            mean.model = list(armaOrder = c(0,0), include.mean = TRUE),
                            distribution.model = "norm")
  fit_arch_cv = ugarchfit(spec = spec_arch_cv, data = ts(train_fold$Returns, frequency=252))
  fc_arch_cv = ugarchforecast(fit_arch_cv, n.ahead=nrow(test_fold))
  fc_values_arch = as.numeric(fc_arch_cv@forecast$seriesFor)
  cross_validation_arch[i] <- sqrt(mean((test_fold$Returns - fc_values_arch)^2))
  
  spec_garch_cv = ugarchspec(variance.model = list(model = "sGARCH", garchOrder = c(1,1)),
                             mean.model = list(armaOrder = c(0,0), include.mean = TRUE),
                             distribution.model = "norm")
  fit_garch_cv = ugarchfit(spec = spec_garch_cv, data = ts(train_fold$Returns, frequency=252))
  fc_garch_cv = ugarchforecast(fit_garch_cv, n.ahead=nrow(test_fold))
  fc_values_garch = as.numeric(fc_garch_cv@forecast$seriesFor)
  cross_validation_garch[i] <- sqrt(mean((test_fold$Returns - fc_values_garch)^2))
  
}
mean(cross_validation_arch)
#RMSE = 0.09
mean(cross_validation_garch)
#RMSE = 0.075 
#-------------------
#ets model
#-------------------

s_close_simple <- ts(train_data$Close, frequency = 1)
ets_model = ets(s_close_simple)
summary(ets_model)
ets_forecast = forecast(ets_model, h=h)
plot(ets_forecast, main="Prévisions ETS")

checkresiduals(ets_model)
ets_acc = accuracy(ets_forecast, test_data$Close[1:h])
ets_acc
#RMSE et MAE elevée
#pvalue=0.27 >> 0.05 donc on ne rejette pas H0
# Pas d'autocorrélation significative dans les résidus

#cross validation ets
cross_val_results_ets = c()
for (i in 1:(k-1)){
  
  train_fold <- train_data[1:(fold_size*i), ]
  test_fold <- train_data[(fold_size*i+1):(fold_size*(i+1)), ]
  ets_cross_v <- ets(ts(train_fold$Close, frequency=252))
  fc_cv <- forecast(ets_cross_v, h=nrow(test_fold))
  cross_val_results_ets[i] <- accuracy(fc_cv, test_fold$Close)[2, "RMSE"]
  
}
mean(cross_val_results_ets)
#RMSE = 8.5 , le model ets ne capture pas bien les prix de clôture

#-------------------
# model prophet
#-------------------
df_profet = data.frame(
  ds = train_data$Date,
  y = train_data$Close
)

m_prophet = prophet(
  yearly.seasonality = FALSE,
  weekly.seasonality = FALSE,
  daily.seasonality = FALSE,
  seasonality.mode = "additive",
  changepoint.prior.scale = 0.9,

)
#des variables exogènes 
m_prophet <- add_regressor(m_prophet, 'RSI')
m_prophet <- add_regressor(m_prophet, 'Price_Range')
df_profet$RSI <- train_data$RSI
df_profet$Price_Range <- train_data$Price_Range
m_prophet = fit.prophet(m_prophet, df_profet)

future = make_future_dataframe(m_prophet, periods = h, freq = "day")
future$RSI <- c(train_data$RSI, test_data$RSI[1:h])
future$Price_Range <- c(train_data$Price_Range, test_data$Price_Range[1:h])

forecast_prophet = predict(m_prophet, future)


plot(m_prophet, forecast_prophet, 
     main="Prévisions Prophet - Prix Tesla")
prophet_plot_components(m_prophet, forecast_prophet)

#evaluation prophet
test_start_date <- as.Date(test_data$Date[1])
forecast_prophet$ds <- as.Date(forecast_prophet$ds)

pred_test_prophet <- forecast_prophet[
  forecast_prophet$ds >= test_start_date, 
]
n_pred <- min(nrow(pred_test_prophet), test_size)
mae_prophet <- mean(abs(test_data$Close[1:n_pred] - pred_test_prophet$yhat[1:n_pred]), na.rm = TRUE)
rmse_prophet <- sqrt(mean((test_data$Close[1:n_pred] - pred_test_prophet$yhat[1:n_pred])^2, na.rm = TRUE))
mae_prophet
rmse_prophet
#rmse =116
summary(m_prophet)

#cross validation prophet
cv_results_prophet = c()
for (i in 1:(k-1)){
  
  train_fold <- train_data[1:(fold_size*i), ]
  test_fold <- train_data[(fold_size*i+1):(fold_size*(i+1)), ]
  
  df_profet_cv = data.frame(
    ds = train_fold$Date,
    y = train_fold$Close,
    RSI = train_fold$RSI,
    Price_Range = train_fold$Price_Range
  )
  
  m_prophet_cv = prophet(
    yearly.seasonality = FALSE,
    weekly.seasonality = FALSE,
    daily.seasonality = FALSE,
    seasonality.mode = "additive",
    changepoint.prior.scale = 0.9
  )
  m_prophet_cv <- add_regressor(m_prophet_cv, 'RSI')
  m_prophet_cv <- add_regressor(m_prophet_cv, 'Price_Range')

  m_prophet_cv = fit.prophet(m_prophet_cv, df_profet_cv)
  
  future_cv = make_future_dataframe(m_prophet_cv, periods = nrow(test_fold), freq = "day")
  future_cv$RSI <- c(train_fold$RSI, test_fold$RSI)
  future_cv$Price_Range <- c(train_fold$Price_Range, test_fold$Price_Range)

  forecast_prophet_cv = predict(m_prophet_cv, future_cv)
  

  test_start_date_cv <- as.Date(test_fold$Date[1])
  forecast_prophet_cv$ds <- as.Date(forecast_prophet_cv$ds)
  
  pred_test_prophet_cv <- forecast_prophet_cv[
    forecast_prophet_cv$ds >= test_start_date_cv, 
  ]
  
  n_pred_cv <- min(nrow(pred_test_prophet_cv), nrow(test_fold))
  rmse_cv <- sqrt(mean((test_fold$Close[1:n_pred_cv] - pred_test_prophet_cv$yhat[1:n_pred_cv])^2, na.rm = TRUE))
  cv_results_prophet[i] <- rmse_cv
}

mean(cv_results_prophet)
#rmse  = 6.21
# ---------------------------------------
# MODÈLE ARIMAX (avec variables exogènes)
# ---------------------------------------



# Variables exogènes: RSI et Price_Range
xreg_train <- cbind(RSI = train_data$RSI, 
                    Price_Range = train_data$Price_Range)
xreg_test <- cbind(RSI = test_data$RSI, 
                   Price_Range = test_data$Price_Range)

arimax_model <- auto.arima(ts_returns, xreg = xreg_train, 
                           seasonal = FALSE, stepwise = FALSE)


print(summary(arimax_model))

checkresiduals(arimax_model)
#p_value = 0.05 >> 0.05 donc on ne rejette pas H0
# Pas d'autocorrélation significative dans les résidus

# Prévisions ARIMAX
arimax_forecast <- forecast(arimax_model, h = h, xreg = xreg_test)
plot(arimax_forecast, main="Prévisions ARIMAX - Rendements avec Variables Exogènes",
     col="orange", lwd=2)


arimax_acc <- accuracy(arimax_forecast, test_data$Returns)

print(arimax_acc)
#cross validation arimax
cross_val_results_arimax = c()
for (i in 1:(k-1)){
  
  train_fold <- train_data[1:(fold_size*i), ]
  test_fold <- train_data[(fold_size*i+1):(fold_size*(i+1)), ]
  
  xreg_train_cv <- cbind(RSI = train_fold$RSI, 
                         Price_Range = train_fold$Price_Range)
  xreg_test_cv <- cbind(RSI = test_fold$RSI, 
                        Price_Range = test_fold$Price_Range)
  
  arimax_cross_v <- auto.arima(ts(train_fold$Returns, frequency=252), 
                               xreg = xreg_train_cv, seasonal=FALSE)
  
  fc_cv <- forecast(arimax_cross_v, h=nrow(test_fold), xreg=xreg_test_cv)
  
  cross_val_results_arimax[i] <- accuracy(fc_cv, test_fold$Returns)[2, "RMSE"]
  
}
mean(cross_val_results_arimax)
#rmse = 0.11 
# ================================== #
#comparaison des models 
#=================================== #

# tableau 1
comparison_returns <- data.frame(
  Modèle = c("ARIMA", "SARIMA", "ARIMAX"),
  RMSE_Train = c(arima_acc[1, "RMSE"], sarima_acc[1, "RMSE"], arimax_acc[1, "RMSE"]),
  RMSE_Test = c(arima_acc[2, "RMSE"], sarima_acc[2, "RMSE"], arimax_acc[2, "RMSE"]),
  MAE_Train = c(arima_acc[1, "MAE"], sarima_acc[1, "MAE"], arimax_acc[1, "MAE"]),
  MAE_Test = c(arima_acc[2, "MAE"], sarima_acc[2, "MAE"], arimax_acc[2, "MAE"]),
  MAPE_Test = c(arima_acc[2, "MAPE"], sarima_acc[2, "MAPE"], arimax_acc[2, "MAPE"]),
  AIC = c(AIC(arima_model), AIC(sarima_model), AIC(arimax_model)),
  BIC = c(BIC(arima_model), BIC(sarima_model), BIC(arimax_model))
)

comparison_returns

#rmse arimax =0.03 < arima 0.046 , sarima 0.045
#mae arimax =2.46 < arima 2.58 , sarima 2.55
# AIC arimax = -4738.204 < arima -4558.806 , sarima -4557.198
# BIC arimax = -4696.739 < arima - , sarima 7642

#--------------------------------------#
# tableau 2 : models de volatilité
AIC_arch <- infocriteria(fit_arch)[1]
AIC_garch_norm <- infocriteria(fit_garch)[1]
AIC_garch_student <- infocriteria(fit_garch_student)[1]

BIC_arch <- infocriteria(fit_arch)[2]
BIC_garch_norm <- infocriteria(fit_garch)[2]
BIC_garch_student <- infocriteria(fit_garch_student)[2]

LogLik_arch <- -fit_arch@fit$LLH
LogLik_garch_norm <- -fit_garch@fit$LLH
LogLik_garch_student <- -fit_garch_student@fit$LLH

comparison_volatility <- data.frame(
  Modèle = c("ARCH(1) Normal", "GARCH(1,1) Normal", "GARCH(1,1) Student-t"),
  AIC = c(AIC_arch, AIC_garch_norm, AIC_garch_student),
  BIC = c(BIC_arch, BIC_garch_norm, BIC_garch_student),
  LogLikelihood = c(LogLik_arch, LogLik_garch_norm, LogLik_garch_student)
 
)
comparison_volatility
# Le modèle GARCH(1,1) avec distribution Student-t est le meilleur selon AIC et 

#----------
#tableau 3 : modèles de prix
comparison_prices <- data.frame(
  Modèle = c("ETS", "Prophet"),
  RMSE_Test = c(ets_acc[2, "RMSE"], rmse_prophet),
  MAE_Test = c(ets_acc[2, "MAE"], mae_prophet),
  MAPE_Test = c(ets_acc[2, "MAPE"], NA),  # Prophet n'a pas MAPE direct
  AIC = c(ets_model$aic, NA),
  BIC = c(ets_model$bic, NA)
)
comparison_prices

# Le modèle ETS est supérieur au modèle Prophet pour la prédiction des prix de Tesla
#prophet echoue a bien predire les prix car il est sensible aux changements brusques et aux outliers



# Sauvegarde des models #

resultats_complets = list(
 donnees = list(
   tsla_data = tsla_data,
   train_data = train_data,
   test_data = test_data
 ),
 rendements = list(
   arima = list(
   model = arima_model,
   forecast = arima_forecast,
     accuracy = arima_acc
     ),
     sarima = list(
     model = sarima_model,
     forecast = sarima_forcast,
     accuracy = sarima_acc
     ),
     arimax = list(
     model = arimax_model,
     forecast = arimax_forecast,
     accuracy = arimax_acc
     )      
  ),
  prix = list( 
     ets = list(
     model = ets_model,
     forecast = ets_forecast,
     accuracy = ets_acc
   ),
   prophet = list(
     model = m_prophet,
     forecast = forecast_prophet,
     accuracy = list(RMSE = rmse_prophet, MAE = mae_prophet)
   )
 ), 
 volatilite = list(
   arch = list(
     model = fit_arch
   ),
   garch_norm = list(
     model = fit_garch
   ),
   garch_student = list(
     model = fit_garch_student
   )
 ),
   multivarie = list(
   var = list(
     model = var_model

   )
  ),
     comparaisons = list(
     rendements = comparison_returns,
     prix = comparison_prices,
     volatilite = comparison_volatility
     ),
     metadata = list(
     date = Sys.Date(),
     train_size = train_size,
     test_size = test_size,
     horizon = h
     )
)

save(resultats_complets, file = "tesla_resultats_complets.RData")


models_results <- data.frame(
  Modele = c("ARIMA", "SARIMA", "ARIMAX", 
             "ETS", "Prophet", 
             "ARCH(1)", "GARCH(1,1) Normal", "GARCH(1,1) Student-t",
             "VAR(3)"),
  Type = c("Returns", "Returns", "Returns", 
           "Prix", "Prix", 
           "Volatilité", "Volatilité", "Volatilité",
           "Multivarié"),
  RMSE_Train = c(
    arima_acc[1, "RMSE"], sarima_acc[1, "RMSE"], arimax_acc[1, "RMSE"],
    ets_acc[1, "RMSE"], NA,
    NA, NA, NA, NA
  ),
  RMSE_Test = c(
    arima_acc[2, "RMSE"], sarima_acc[2, "RMSE"], arimax_acc[2, "RMSE"],
    ets_acc[2, "RMSE"], rmse_prophet,
    NA, NA, NA, NA
  ),
  MAE_Train = c(
    arima_acc[1, "MAE"], sarima_acc[1, "MAE"], arimax_acc[1, "MAE"],
    ets_acc[1, "MAE"], NA,
    NA, NA, NA, NA
  ),
  MAE_Test = c(
    arima_acc[2, "MAE"], sarima_acc[2, "MAE"], arimax_acc[2, "MAE"],
    ets_acc[2, "MAE"], mae_prophet,
    NA, NA, NA, NA
  ),
  MAPE_Test = c(
    arima_acc[2, "MAPE"], sarima_acc[2, "MAPE"], arimax_acc[2, "MAPE"],
    ets_acc[2, "MAPE"], NA,
     NA, NA, NA, NA
     ),
     AIC = c(
     AIC(arima_model), AIC(sarima_model), AIC(arimax_model),
     ets_model$aic, NA,
     AIC_arch, AIC_garch_norm, AIC_garch_student,
     NA
     ),
     BIC = c(
     BIC(arima_model), BIC(sarima_model), BIC(arimax_model
     ),
     ets_model$bic, NA,
     BIC_arch, BIC_garch_norm, BIC_garch_student,
     NA
     )
)
write.csv(models_results, "data_export/models_results_summary.csv", row.names = FALSE)


align_forecast <- function(pred_df, test_dates, value_col = "yhat", lower_col = "yhat_lower", upper_col = "yhat_upper") {
  pred_df$ds <- as.Date(pred_df$ds)
  test_dates <- as.Date(test_dates)
  idx <- match(test_dates, pred_df$ds)
  data.frame(
    Prophet_Close = if (!is.null(pred_df[[value_col]])) pred_df[[value_col]][idx] else rep(NA, length(test_dates)),
    Prophet_Lower = if (!is.null(pred_df[[lower_col]])) pred_df[[lower_col]][idx] else rep(NA, length(test_dates)),
    Prophet_Upper = if (!is.null(pred_df[[upper_col]])) pred_df[[upper_col]][idx] else rep(NA, length(test_dates))
  )
}
predictions_complete <- data.frame(
  Date = test_data$Date[1:h],
  Actual_Close = test_data$Close[1:h],
  Actual_Returns = test_data$Returns[1:h],
  ARIMA_Returns = if(length(arima_forecast$mean) >= h) as.numeric(arima_forecast$mean[1:h]) else rep(NA, h),
  SARIMA_Returns = if(length(sarima_forcast$mean) >= h) as.numeric(sarima_forcast$mean[1:h]) else rep(NA, h),
  ARIMAX_Returns = if(length(arimax_forecast$mean) >= h) as.numeric(arimax_forecast$mean[1:h]) else rep(NA, h),
  ETS_Close = if(length(ets_forecast$mean) >= h) as.numeric(ets_forecast$mean[1:h]) else rep(NA, h),
  ARIMA_Lower = if(nrow(arima_forecast$lower) >= h) as.numeric(arima_forecast$lower[1:h, 2]) else rep(NA, h),
  ARIMA_Upper = if(nrow(arima_forecast$upper) >= h) as.numeric(arima_forecast$upper[1:h, 2]) else rep(NA, h),
  ETS_Lower = if(nrow(ets_forecast$lower) >= h) as.numeric(ets_forecast$lower[1:h, 2]) else rep(NA, h),
  ETS_Upper = if(nrow(ets_forecast$upper) >= h) as.numeric(ets_forecast$upper[1:h, 2]) else rep(NA, h)
)
if (exists("pred_test_prophet")) {
  prophet_aligned <- align_forecast(pred_test_prophet, test_data$Date[1:h])
  predictions_complete <- cbind(predictions_complete, prophet_aligned)
}

# Export only if you need it
write.csv(predictions_complete, "data_export/predictions_complete.csv", row.names = FALSE)

garch_params <- data.frame(
  Modele = c("ARCH(1)", "GARCH(1,1) Normal", "GARCH(1,1) Student-t"),
  Mu = c(
    coef(fit_arch)["mu"],
    coef(fit_garch)["mu"],
    coef(fit_garch_student)["mu"]
  ),
  Omega = c(
    coef(fit_arch)["omega"],
    coef(fit_garch)["omega"],
    coef(fit_garch_student)["omega"]
  ),
  Alpha1 = c(
    coef(fit_arch)["alpha1"],
    coef(fit_garch)["alpha1"],
    coef(fit_garch_student)["alpha1"]
  ),
  Beta1 = c(
    NA,
    coef(fit_garch)["beta1"],
    coef(fit_garch_student)["beta1"]
  ),
  Shape = c(
    NA,
     NA,
     coef(fit_garch_student)["shape"]
     ),
     Persistence = c(
     coef(fit_arch)["alpha1"],
     coef(fit_garch)["alpha1"] + coef(fit_garch)["beta1"],
     coef(fit_garch_student)["alpha1"] + coef(fit_garch_student)["beta1"]
     )
)
arima_params <- data.frame(
  Modele = "ARIMA",
  Ordre = paste0("(", paste(arimaorder(arima_model), collapse = ","), ")"),
  Sigma2 = arima_model$sigma2,
  LogLik = arima_model$loglik,
  AIC = AIC(arima_model),
  BIC = BIC(arima_model)
)
write.csv(arima_params, "data_export/arima_params.csv", row.names = FALSE)
write.csv(garch_params, "data_export/garch_params.csv", row.names = FALSE)

tests_stationnarite <- data.frame(
  Variable = c("Close", "Returns", "Volume_Change"),
  ADF_Statistic = c(
    adf.test(train_data$Close)$statistic,
    adf.test(train_data$Returns)$statistic,
    adf.test(train_data$Volume_Change)$statistic
  ),
  ADF_PValue = c(
    adf.test(train_data$Close)$p.value,
    adf.test(train_data$Returns)$p.value,
    adf.test(train_data$Volume_Change)$p.value
  ),
  Stationnaire = c("Non", "Oui", "Oui")
)
write.csv(tests_stationnarite, "data_export/tests_stationnarite.csv", row.names = FALSE)

serial_test <- serial.test(var_model, lags.pt=16, type="PT.asymptotic")

var_serial_results <- data.frame(
  Test = "Portmanteau Test",
  Chi_Squared = serial_test$serial$statistic,
  DF = serial_test$serial$parameter,
  P_Value = serial_test$serial$p.value,
  Interpretation = ifelse(serial_test$serial$p.value < 0.05,
                         "Autocorrélation présente",
                         "Pas d'autocorrélation")
)
write.csv(var_serial_results, "data_export/var_serial_results.csv", row.names = FALSE)


granger_results <- data.frame(
  Test = c("Volume → Returns", "Returns → Volume"),
  F_Statistic = c(
    granger_ts_returns$statistic,
    granger_ts_volume$statistic
  ),
  P_Value = c(
    granger_ts_returns$p.value,
    granger_ts_volume$p.value
  ),
  Decision = c(
    ifelse(granger_ts_returns$p.value < 0.05, 
           "Causalité détectée", "Pas de causalité"),
    ifelse(granger_ts_volume$p.value < 0.05, 
           "Causalité détectée", "Pas de causalité")
  )
)

write.csv(granger_results, "data_export/granger_causality.csv", row.names = FALSE)
# 1. Données principales
write.csv(tsla_data, "data_export/tsla_data.csv", row.names = FALSE)
write.csv(train_data, "data_export/tsla_train_data.csv", row.names = FALSE)
write.csv(test_data, "data_export/tsla_test_data.csv", row.names = FALSE)

# 2. Résumés et comparaisons
write.csv(comparison_returns, "data_export/comparison_returns.csv", row.names = FALSE)
write.csv(comparison_volatility, "data_export/comparison_volatility.csv", row.names = FALSE)
write.csv(comparison_prices, "data_export/comparison_prices.csv", row.names = FALSE)

# 3. Résultats de cross-validation
write.csv(data.frame(RMSE_CV_ARIMA = cross_val_results_arima), "data_export/cv_arima.csv", row.names = FALSE)
write.csv(data.frame(RMSE_CV_SARIMA = cross_val_results_sarima), "data_export/cv_sarima.csv", row.names = FALSE)
write.csv(data.frame(RMSE_CV_ETS = cross_val_results_ets), "data_export/cv_ets.csv", row.names = FALSE)
write.csv(data.frame(RMSE_CV_Prophet = cv_results_prophet), "data_export/cv_prophet.csv", row.names = FALSE)
write.csv(data.frame(RMSE_CV_ARIMAX = cross_val_results_arimax), "data_export/cv_arimax.csv", row.names = FALSE)
write.csv(data.frame(RMSE_CV_ARCH = cross_validation_arch), "data_export/cv_arch.csv", row.names = FALSE)
write.csv(data.frame(RMSE_CV_GARCH = cross_validation_garch), "data_export/cv_garch.csv", row.names = FALSE)

# 4. Paramètres et diagnostics des modèles
write.csv(arima_params, "data_export/arima_params.csv", row.names = FALSE)
write.csv(garch_params, "data_export/garch_params.csv", row.names = FALSE)

# 5. Résultats des tests de stationnarité et multivariés
write.csv(tests_stationnarite, "data_export/tests_stationnarite.csv", row.names = FALSE)
write.csv(var_serial_results, "data_export/var_serial_results.csv", row.names = FALSE)
write.csv(granger_results, "data_export/granger_causality.csv", row.names = FALSE)

# 6. Résumés textuels (summary, checkresiduals, etc.)
capture.output(summary(arima_model), file = "data_export/summary_arima.txt")
capture.output(summary(sarima_model), file = "data_export/summary_sarima.txt")
capture.output(summary(arimax_model), file = "data_export/summary_arimax.txt")
capture.output(summary(ets_model), file = "data_export/summary_ets.txt")
capture.output(summary(m_prophet), file = "data_export/summary_prophet.txt")
capture.output(show(fit_arch), file = "data_export/summary_arch.txt")
capture.output(show(fit_garch), file = "data_export/summary_garch.txt")
capture.output(show(fit_garch_student), file = "data_export/summary_garch_student.txt")
capture.output(summary(var_model), file = "data_export/summary_var.txt")

capture.output(checkresiduals(arima_model), file = "data_export/checkresiduals_arima.txt")
capture.output(checkresiduals(sarima_model), file = "data_export/checkresiduals_sarima.txt")
capture.output(checkresiduals(ets_model), file = "data_export/checkresiduals_ets.txt")
capture.output(Box.test(residuals(arima_model), lag=20, type="Ljung-Box"), file = "data_export/box_arima.txt")
capture.output(Box.test(residuals(sarima_model), lag=20, type="Ljung-Box"), file = "data_export/box_sarima.txt")

# 7. Prédictions complètes
write.csv(predictions_complete, "data_export/predictions_complete.csv", row.names = FALSE)

# 8. Résumé global pour Python/LLM
models_results <- data.frame(
    Modele = c("ARIMA", "SARIMA", "ARIMAX", 
             "ETS", "Prophet", 
             "ARCH(1)", "GARCH(1,1) Normal", "GARCH(1,1) Student-t",
             "VAR(3)"),
     Type = c("Returns", "Returns", "Returns", 
           "Prix", "Prix", 
           "Volatilité", "Volatilité", "Volatilité",
           "Multivarié"),
    RMSE_Train = c(
    arima_acc[1, "RMSE"], sarima_acc[1, "RMSE"], arimax_acc[1, "RMSE"],
    ets_acc[1, "RMSE"], NA,
    NA, NA, NA, NA
  ),
    RMSE_Test = c(
    arima_acc[2, "RMSE"], sarima_acc[2, "RMSE"], arimax_acc[2, "RMSE"],
    ets_acc[2, "RMSE"], rmse_prophet,
    NA, NA, NA, NA
  ),
    MAE_Train = c(
    arima_acc[1, "MAE"], sarima_acc[1, "MAE"], arimax_acc[1, "MAE"],
    ets_acc[1, "MAE"], NA,
    NA, NA, NA, NA
  ),
    MAE_Test = c(
    arima_acc[2, "MAE"], sarima_acc[2, "MAE"], arimax_acc[2, "MAE"],
    ets_acc[2, "MAE"], mae_prophet,
    NA, NA, NA, NA
  ),
    MAPE_Test = c(
    arima_acc[2, "MAPE"], sarima_acc[2, "MAPE"], arimax_acc[2, "MAPE"],
    ets_acc[2, "MAPE"], NA,
     NA, NA, NA, NA
     ),
     AIC = c(
     AIC(arima_model), AIC(sarima_model), AIC(arimax_model),
     ets_model$aic, NA,
     AIC_arch, AIC_garch_norm, AIC_garch_student,
     NA
     ),
     BIC = c(
     BIC(arima_model), BIC(sarima_model), BIC(arimax_model),
     ets_model$bic, NA,
     BIC_arch, BIC_garch_norm, BIC_garch_student,
     NA
     )
)
write.csv(models_results, "data_export/models_results_summary.csv", row.names = FALSE)


resultats_complets = list(
  donnees = list(
    tsla_data = tsla_data,
    train_data = train_data,
    test_data = test_data
  ),
  rendements = list(
    arima = list(
      model = arima_model,
      forecast = arima_forecast,
      accuracy = arima_acc,
      cv = cross_val_results_arima
    ),
    sarima = list(
      model = sarima_model,
      forecast = sarima_forcast,
      accuracy = sarima_acc,
      cv = cross_val_results_sarima
    ),
    arimax = list(
      model = arimax_model,
      forecast = arimax_forecast,
      accuracy = arimax_acc,
      cv = cross_val_results_arimax
    )
  ),
  prix = list(
    ets = list(
      model = ets_model,
      forecast = ets_forecast,
      accuracy = ets_acc,
      cv = cross_val_results_ets
    ),
    prophet = list(
      model = m_prophet,
      forecast = forecast_prophet,
      accuracy = list(RMSE = rmse_prophet, MAE = mae_prophet),
      cv = cv_results_prophet
    )
  ),
  volatilite = list(
    arch = list(
      model = fit_arch,
      cv = cross_validation_arch
    ),
    garch_norm = list(
      model = fit_garch,
      cv = cross_validation_garch
    ),
    garch_student = list(
      model = fit_garch_student
    )
  ),
  multivarie = list(
    var = list(
      model = var_model,
      summary = var_summary,
      serial_test = serial_test
    )
  ),
  comparaisons = list(
    rendements = comparison_returns,
    prix = comparison_prices,
    volatilite = comparison_volatility
  ),
  diagnostics = list(
    arima = capture.output(summary(arima_model)),
    sarima = capture.output(summary(sarima_model)),
    arimax = capture.output(summary(arimax_model)),
    ets = capture.output(summary(ets_model)),
    prophet = capture.output(summary(m_prophet)),
    arch = capture.output(summary(fit_arch)),
    garch = capture.output(summary(fit_garch)),
    garch_student = capture.output(summary(fit_garch_student)),
    var = capture.output(summary(var_model))
  ),
  metadata = list(
    date = Sys.Date(),
    train_size = train_size,
    test_size = test_size,
    horizon = h
  )
)
save(resultats_complets, file = "tesla_resultats_complets.RData")

