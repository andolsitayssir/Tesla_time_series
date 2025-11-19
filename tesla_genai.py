import os
from groq import Groq
from dotenv import load_dotenv , dotenv_values
import pandas as pd
from pandas import read_csv

load_dotenv()
api_key = os.getenv("GROQ_API_KEY")

client = Groq(api_key=api_key)
model ="openai/gpt-oss-120b"

def load_data():
    """Charge les fichiers CSV et texte avec intégration des summaries"""
    data = {}
    
    # Charger les CSV
    try:
        data['models_results'] = pd.read_csv('./data_export/deep_models_results.csv')
        data['granger_test'] = pd.read_csv('./data_export/granger_causality.csv')
        data['stationarity'] = pd.read_csv('./data_export/tests_stationnarite.csv')
        data['desc_tsla'] = pd.read_csv('./data_export/desc_tsla.csv')
    except Exception as e:
        print(f"Erreur chargement CSV: {e}")
    
    # Charger les résumés texte et les mapper aux modèles
    model_summaries = {
        'arima': './data_export/summary_arima.txt',
        'arimax': './data_export/summary_arimax.txt',
        'sarima': './data_export/summary_sarima.txt',
        'ets': './data_export/summary_ets.txt',
        'garch': './data_export/summary_garch.txt',
        'garch_student': './data_export/summary_garch_student.txt',
        'var': './data_export/summary_var.txt',
        'prophet': './data_export/summary_prophet.txt'
    }
    
    # Charger chaque summary
    summaries = {}
    for model_key, filename in model_summaries.items():
        try:
            with open(filename, 'r', encoding='utf-8') as file:
                summaries[model_key] = file.read()
        except:
            summaries[model_key] = "Fichier non trouvé"
    
    # Ajouter les summaries aux modèles dans le dataframe
    def get_summary(model_name):
        """Retourne le summary correspondant au modèle"""
        model_lower = model_name.lower().replace('_', ' ').replace('-', ' ')
        for key, summary in summaries.items():
            if key in model_lower:
                return summary[:500]  # Aperçu de 500 caractères
        return "Pas de summary disponible"
    
    # Ajouter une colonne avec les summaries
    data['models_results']['Summary'] = data['models_results']['Modele'].apply(get_summary)
    data['full_summaries'] = summaries
    
    return data
data = load_data()

def generate_hypotheses(data):
    """Point 1: Générer automatiquement des hypothèses à partir des stats descriptives"""
    
    models_df = data['models_results']
    desc_stats_df = data['desc_tsla']
    stationarity_df = data['stationarity']
    granger_df = data['granger_test']
    
    best_returns = models_df[models_df['Type'] == 'Returns'].nsmallest(1, 'RMSE_Test')
    best_model = best_returns['Modele'].values[0]
    best_rmse = best_returns['RMSE_Test'].values[0]
    
    # Extraire les stats descriptives
    desc_stats_text = desc_stats_df.to_string()
    stationarity_text = stationarity_df.to_string()
    granger_text = granger_df.to_string()
    
    # Calculer des statistiques supplémentaires
    skewness_info = desc_stats_df.to_dict() if 'Skewness' in desc_stats_df.columns else {}
    kurtosis_info = desc_stats_df.to_dict() if 'Kurtosis' in desc_stats_df.columns else {}
    
    prompt = f"""
Tu es expert en machine learning et analyse statistique de séries temporelles financières.

 STATISTIQUES DESCRIPTIVES - TESLA (TSLA):
{desc_stats_text}

 TESTS DE STATIONNARITÉ:
{stationarity_text}

🔗 CAUSALITÉ GRANGER:
{granger_text}

MEILLEUR MODÈLE ACTUEL: {best_model} (RMSE Test: {best_rmse:.4f})

TÂCHE - GÉNÉRER HYPOTHÈSES À PARTIR DES STATS DESCRIPTIVES:

En analysant les statistiques ci-dessus, identifie les CARACTÉRISTIQUES de la série:
- Asymétrie (Skewness)? Queues épaisses (Kurtosis)?
- Stationnarité différente pour Returns vs Close?
- Absence de causalité entre variables?
- Volatilité? Tendance? Saisonnalité?

PUIS propose 5 HYPOTHÈSES DE MODÈLES adaptées à ces caractéristiques.

Pour CHAQUE hypothèse:
1. NOM DU MODÈLE
2. CARACTÉRISTIQUE STATISTIQUE DÉTECTÉE (d'après les stats descriptives)
3. POURQUOI CE MODÈLE S'ADAPTE À CES CARACTÉRISTIQUES
4. AMÉLIORATION ATTENDUE vs {best_model}
5. DONNÉES/FEATURES NÉCESSAIRES
6. COMPLEXITÉ (Faible/Moyen/Élevé)



Exemple format:
Hypothèse 1:
Nom: [modèle]
Caractéristique détectée: [asymétrie, kurtosis élevé, non-stationnarité, etc.]
Justification: [Parce que les stats montrent...]
Amélioration attendue: [X% de réduction RMSE]
Données: [RSI, Volume, etc.]
Complexité: [Moyen]


IMPORTANT:
- Chaque hypothèse DOIT être ancrée dans les stats observées
- Pas de suggestions génériques, du concret basé sur les données
- Mentionne les valeurs numériques des stats pour justifier
-Donner des paragraphes bien déloppé pour chaque point
"""
    
    
    response = client.chat.completions.create(
        model="openai/gpt-oss-120b",
        messages=[{"role": "user", "content": prompt}],
        temperature=0.7,
        
    )
    
    return response.choices[0].message.content


def explain_results(data):
    """Point 2: Expliquer les résultats de manière vulgarisée"""
    print("   Génération du rapport vulgarisé...")

    models_df = data['models_results']
    # Sélectionner les top 3 modèles selon RMSE_Test
    top_models = models_df[models_df['Type'] == 'Returns'].nsmallest(3, 'RMSE_Test')
    summaries = data['full_summaries']

    # Construire un tableau récapitulatif
    recap = ""
    for idx, row in top_models.iterrows():
         recap += (
            f"\nModèle : {row['Modele']}\n"
            f"- RMSE Test : {row['RMSE_Test']:.6f}\n"
            f"- MAE Test : {row['MAE_Test']:.6f}\n"
            f"- MAPE Test : {row['MAPE_Test']:.2f}%\n"
            f"- AIC : {row.get('AIC', 'N/A')}\n"
            f"- BIC : {row.get('BIC', 'N/A')}\n")


    prompt = f"""Tu es un vulgarisateur scientifique pour investisseurs non-techniques.

RÉSULTATS DES 3 MEILLEURS MODÈLES :
{recap}

TÂCHE: Écris un RAPPORT qui explique:

1️ MÉTRIQUES EXPLIQUÉES SIMPLEMENT
   - Qu'est-ce que RMSE, MAE, MAPE , AIC , BIC? (analogies simples, pas de formules)
   - "L'erreur moyenne est de..."
   - Qu'est-ce que ça signifie pour prédire le prix?

2  Les points FORTS ET FAIBLES DE CHAQUE MODÈLE
   - Pourquoi ces modèles gagnent?
   - Ses 3 forces principales
   - Ses 2-3 limitations réelles

3️ IMPLICATIONS PRATIQUES POUR UN INVESTISSEUR
   - Comment ça aide pour investir?
   - Quel est le risque réel?
   - Comment l'utiliser correctement?

4️ COMPARAISON 
   - Pourquoi les classement est ainsi ?
   - Qu'est-ce qui différencie le 1er du 2e et 3e?

STYLE:
- Langage très simple (niveau lycée)
- Honnête sur les limites
- Pas de promesses exagérées
- Assume que le lecteur ne sait rien en ML
-Donner des paragraphes bien déloppé pour chaque point

"""

    response = client.chat.completions.create(
        model="openai/gpt-oss-120b",
        messages=[{"role": "user", "content": prompt}],
        temperature=0.5,
        
    )
    
    return response.choices[0].message.content


def generate_recommendation(data):
    """Point 3: Générer des recommandations d’investissement simulées (expliciter les limites et risques)"""
    models_df = data['models_results']
   
    top_models = models_df[models_df['Type'] == 'Returns'].nsmallest(3, 'RMSE_Test')
    recap = ""
    for idx, row in top_models.iterrows():
        recap += (
            f"\nModèle : {row['Modele']}\n"
            f"- RMSE Test : {row['RMSE_Test']:.6f}\n"
            f"- MAE Test : {row['MAE_Test']:.6f}\n"
            f"- MAPE Test : {row['MAPE_Test']:.2f}%\n"
        )

    prompt = f"""Tu es un conseiller financier prudent et objectif.

RÉSULTATS DES 3 MEILLEURS MODÈLES :
{recap}

TÂCHE : Génère une recommandation d'investissement simulée basée sur ces résultats.

Pour chaque recommandation:
- Action 
- Horizon (court/moyen/long terme)
- Mentionne les incertitudes, la volatilité, et les risques de perte.
- Des conseils pratiques pour utiliser ces prévisions de façon responsable.
- 1-2 risques majeurs
- AVERTISSEMENT clair sur les limites

IMPORTANT: 
- C'est une SIMULATION éducative, PAS un conseil professionnel
- Rappelle que les marchés sont imprévisibles
- Les modèles prédictifs comportent des erreurs
- Ne pas investir réellement sur la base de cet exercice
"""

    response = client.chat.completions.create(
        model="openai/gpt-oss-120b",
        messages=[{"role": "user", "content": prompt}],
        temperature=0.5,
    )
    return response.choices[0].message.content

def compare_human_vs_ai(data, human_analysis=None):
    """Compare les analyses humaine et IA"""
    
    # Analyse IA
    ai_analysis = explain_results(data)
    
    # Analyse humaine (exemple si non fournie)
    if not human_analysis:
        human_analysis = """
        ANALYSE HUMAINE:
       - Les rendements sont stationnaires (test ADF p < 0.05).
- Pas d'autocorrélation significative dans les résidus des modèles ARIMA/SARIMA (test Ljung-Box p > 0.05).
- L'asymétrie et les queues épaisses ne sont pas bien capturées par les modèles linéaires.
- Aucune causalité de Granger détectée entre les variables (p > 0.05).
- Le modèle ARIMA capture correctement la dynamique des rendements, mais reste limité sur les extrêmes.
- ARIMAX offre les meilleures performances sur les rendements (RMSE Test = 0.0324), grâce à l'intégration des variables exogènes (RSI, Price_Range).
- LSTM obtient un RMSE proche (0.0348), mais sa complexité rend l'interprétation plus difficile pour un investisseur.
- Le modèle GARCH Student-t capture mieux la volatilité et les extrêmes, ce qui est important pour la gestion du risque.
- Le modèle ETS ne parvient pas à bien prédire les prix de clôture (erreur élevée).
- Prophet-RNN et ARIMA-LSTM (modèles hybrides) montrent de bonnes performances, en particulier lors de changements de tendance ou de volatilité.
- Au global, ARIMAX reste le meilleur pour la prévision des rendements parmi les modèles classiques, mais les modèles deep/hybrides sont prometteurs pour des dynamiques plus complexes.

        """
    
    prompt = f"""
Compare ces deux analyses:

ANALYSE HUMAINE:
{human_analysis}

ANALYSE IA:
{ai_analysis}

Évalue:
1. Points d'ACCORD (quoi de similaire?)
2. Points de DIVERGENCE (différences principales)
3. Laquelle est plus fiable et pourquoi?
4. Combiné ensemble, qu'en conclure?
5-Donner des paragraphes bien développés pour chaque point

Sois honnête et équilibré .
"""
    
    response = client.chat.completions.create(
        model="openai/gpt-oss-120b",
        messages=[{"role": "user", "content": prompt}],
        temperature=0.6,
       
    )
    
    comparison_result = response.choices[0].message.content
    
    return {
        "human_analysis": human_analysis,
        "ai_analysis": ai_analysis,
        "comparison": comparison_result
    }

def generate_report(data, human_analysis=None):
    """Génère le rapport complet"""
    hypotheses = generate_hypotheses(data)
    explanation = explain_results(data)
    recommendation = generate_recommendation(data)
    comparison = compare_human_vs_ai(data, human_analysis)
    
    report = f"""
RAPPORT D'ANALYSE DES SÉRIES TEMPORELLES DE TESLA (TSLA)
1️ HYPOTHÈSES DE MODÈLES PROPOSÉES:
{hypotheses}
2️ EXPLICATION DES RÉSULTATS:
{explanation}
3️ RECOMMANDATION D'INVESTISSEMENT SIMULÉE:
{recommendation}
4️ COMPARAISON ANALYSE HUMAINE VS IA:
- Analyse Humaine:
{comparison['human_analysis']}
- Comparaison:
{comparison['comparison']}
*Ce rapport a été généré automatiquement à l’aide d’un LLM. Les résultats sont à visée pédagogique et ne constituent pas un conseil d’investissement.*
"""
    return report

def main():
    
    data = load_data()

    
    report = generate_report(data)

    report_dir = os.path.join(os.getcwd(), "report")
    os.makedirs(report_dir, exist_ok=True)

    report_path = os.path.join(report_dir, "rapport_tesla_llm.md")
    with open(report_path, "w", encoding="utf-8") as f:
        f.write(report)

    print(f"\n Rapport généré et exporté ici : {report_path}\n")

if __name__ == "__main__":
    main()