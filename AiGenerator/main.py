# ai_generator.py (FastAPI microservice)

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from openai import OpenAI
import os
import json
import traceback

client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))

app = FastAPI()


class PlantRequest(BaseModel):
    name: str


@app.post("/generate")
async def generate_plant_info(req: PlantRequest):
    """
    Génère une fiche complète de soin pour une plante dans 4 langues
    (fr, en, es, de), structurée par sous-parties :
    - description + plantType
    - sun
    - water
    - soilAndPot
    - health
    - lifeCycle
    - care
    """
    try:
        completion = client.chat.completions.create(
            model="gpt-4o-mini",
            response_format={"type": "json_object"},
            messages=[
                {
                    "role": "system",
                    "content": (
                        "Tu es un expert botaniste spécialisé en plantes d'intérieur et d'extérieur. "
                        "Tu dois répondre STRICTEMENT avec un objet JSON valide (aucun texte autour). "
                        "La structure JSON attendue est la suivante :\n\n"
                        "{\n"
                        '  "fr": {\n'
                        '    "description": "Texte court décrivant la plante en français.",\n'
                        '    "plantType": "Type général de la plante (ex: Plante d\'intérieur, Plante grimpante, Succulente, etc.).",\n'
                        '    "sun": {\n'
                        '      "lightType": "Type de lumière recommandé (ex: Lumière vive indirecte).",\n'
                        '      "durationPerDay": "Durée d’exposition conseillée par jour (ex: 8–12 h / jour).",\n'
                        '      "orientation": "Orientation idéale des fenêtres (ex: Est ou Ouest).",\n'
                        '      "windowDistance": "Distance recommandée par rapport à la fenêtre.",\n'
                        '      "recommendedRooms": ["Liste de pièces recommandées (salon, bureau, etc.)."],\n'
                        '      "tips": ["Quelques conseils pratiques sur la lumière et le placement."]\n'
                        "    },\n"
                        '    "water": {\n'
                        '      "frequency": "Fréquence d’arrosage (ex: 1 fois par semaine).",\n'
                        '      "amount": "Quantité d’eau approximative ou indication (ex: arroser jusqu’à ce que l’eau s’écoule).",\n'
                        '      "method": "Méthode d’arrosage (par le dessus, trempage, vider la soucoupe, etc.).",\n'
                        '      "humidity": "Niveau d’humidité de l’air souhaité et conseils (ex: 40–60 %, brumisation).",\n'
                        '      "signsLack": "Signes de manque d’eau.",\n'
                        '      "signsExcess": "Signes d’excès d’eau.",\n'
                        '      "recommendedWater": "Type d’eau recommandé (température ambiante, peu calcaire, etc.)."\n'
                        "    },\n"
                        '    "soilAndPot": {\n'
                        '      "substrate": "Type de substrat recommandé.",\n'
                        '      "drainage": "Infos sur le drainage (trous au fond, billes d’argile, etc.).",\n'
                        '      "potSize": "Taille de pot recommandée par rapport à la motte.",\n'
                        '      "repotFrequency": "Fréquence de rempotage (ex: tous les 1–2 ans).",\n'
                        '      "repotSigns": "Signes qui indiquent qu’il faut rempoter."\n'
                        "    },\n"
                        '    "health": {\n'
                        '      "commonProblems": ["Liste courte de problèmes fréquents."],\n'
                        '      "symptomsAndCauses": ["Symptôme : cause probable."],\n'
                        '      "pests": ["Parasites fréquents (cochenilles, araignées rouges, etc.)."],\n'
                        '      "treatments": ["Traitements simples et accessibles pour l’utilisateur."],\n'
                        '      "prevention": ["Conseils de prévention pour garder la plante en bonne santé."]\n'
                        "    },\n"
                        '    "lifeCycle": {\n'
                        '      "growth": "Infos sur la période et le rythme de croissance.",\n'
                        '      "flowering": "Infos sur la floraison (si pertinente pour la plante).",\n'
                        '      "dormancy": "Comportement en période de repos/dormance et ajustements nécessaires.",\n'
                        '      "fertilizer": "Type et fréquence d’engrais.",\n'
                        '      "pruning": "Conseils de taille et d’entretien de la structure."\n'
                        "    },\n"
                        '    "care": {\n'
                        '      "weekly": ["Actions d’entretien hebdomadaires."],\n'
                        '      "monthly": ["Actions d’entretien mensuelles."],\n'
                        '      "yearly": ["Actions annuelles (rempotage, taille plus importante, etc.)."],\n'
                        '      "extraTips": ["Astuces supplémentaires pour optimiser la santé et l’esthétique de la plante."]\n'
                        "    }\n"
                        "  },\n"
                        '  "en": { ... même structure mais en anglais ... },\n'
                        '  "es": { ... en espagnol ... },\n'
                        '  "de": { ... en allemand ... }\n'
                        "}\n\n"
                        "Contraintes importantes :\n"
                        "- Tu DOIS renvoyer les 4 langues : fr, en, es, de.\n"
                        "- Les clés de structure (description, plantType, sun, water, soilAndPot, health, lifeCycle, care, etc.) sont en anglais et identiques pour toutes les langues.\n"
                        "- Les textes doivent être CONCIS, pratiques et faciles à comprendre pour un débutant.\n"
                        '- Remplis TOUS les champs avec un contenu utile : n’utilise jamais null, "N/A" ou des chaînes vides.\n'
                        "- Ne commente pas ta réponse, ne rajoute pas de texte hors du JSON."
                    ),
                },
                {
                    "role": "user",
                    "content": (
                        f"Génère une fiche de soin complète pour la plante « {req.name} ».\n"
                        "Respecte exactement la structure JSON décrite dans les instructions système.\n"
                        "Adapte les conseils spécifiquement à cette plante.\n"
                        'Rédige en français pour "fr", en anglais pour "en", en espagnol pour "es" et en allemand pour "de".\n'
                        "Ne renvoie que l'objet JSON, sans texte supplémentaire."
                    ),
                },
            ],
            temperature=0.7,
        )

        raw = completion.choices[0].message.content
        data = json.loads(raw)
        return data

    except Exception as e:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Erreur IA : {str(e)}")
