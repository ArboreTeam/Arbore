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
    try:
        completion = client.chat.completions.create(
            model="gpt-4o-mini",  # ou gpt-4o / gpt-3.5-turbo selon ton quota
            response_format={ "type": "json_object" },
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

        raw = completion.choices[0].message.content
        # Ici, 'raw' est déjà une string JSON valide.
        data = json.loads(raw)

        return data

    except Exception as e:
        # Log complet côté serveur pour debug
        traceback.print_exc()
        raise HTTPException(
            status_code=500,
            detail=f"Erreur IA : {str(e)}"
        )
