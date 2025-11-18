# Tesla Time Series Project

Ce projet analyse et prédit les prix et rendements de l'action Tesla (TSLA) à l'aide de modèles classiques (ARIMA, GARCH, ETS, Prophet) et de modèles avancés (LSTM, GRU, ARIMA-LSTM, Prophet-RNN).

## Structure du projet

- `tesla.r` : Analyse, modélisation et export des résultats en R (modèles classiques).
- `tesla_deep.ipynb` : Modélisation avancée en Python (deep learning, hybrid, ARIMA_LSTM, Prophet-RNN).
- `tesla_genai.py` : Génération d'hypothèses et d'explications avec un LLM (gpt-oss-120b).
- `data_export/` : Résultats, métriques et diagnostics exporter.


## Installation

1. Clonez le dépôt.
2. Installez les dépendances Python :
   ```sh
   pip install -r requirments.txt

   