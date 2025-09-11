from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import openai
import os
import json
import re

# Configure ton client OpenAI (clé d'API dans une variable d'environnement)
client = openai.OpenAI(api_key=os.getenv("OPENAI_API_KEY"))

app = FastAPI()

class PlantRequest(BaseModel):
    name: str

@app.post("/generate")
async def generate_plant_info(req: PlantRequest):
    try:
        completion = client.chat.completions.create(
            model="gpt-3.5-turbo",  # Tu peux mettre gpt-4o si tu veux plus de qualité
            messages=[
                {
                    "role": "system",
                    "content": (
                        "Tu es un expert botaniste. Réponds uniquement avec un objet JSON contenant les clés "
                        "'fr', 'en', 'es', 'de'. Chaque langue contient un objet avec les clés : "
                        "'type', 'description', 'origine', 'lumière', 'arrosage', 'température', 'floraison', 'conseils', 'sol'. "
                        "Pas d'explication, pas de texte autour, juste un JSON pur."
                    )
                },
                {
                    "role": "user",
                    "content": f"""Génère une fiche pour la plante "{req.name}" :
- type, description, origine, lumière, arrosage, température, floraison, conseils, sol

En 4 langues (fr, en, es, de).

Ne mets que l'objet JSON pur."""
                }
            ],
            temperature=0.7
        )

        raw = completion.choices[0].message.content.strip()
        print("🧠 Réponse brute de GPT :")
        print(raw)

        match = re.search(r'\{.*\}', raw, re.DOTALL)
        if not match:
            raise ValueError("Aucun JSON détecté")

        clean_json = match.group(0)
        data = json.loads(clean_json)

        return data

    except Exception as e:
        print("❌ Erreur globale :", e)
        raise HTTPException(status_code=500, detail="Erreur lors du parsing de la réponse IA")
