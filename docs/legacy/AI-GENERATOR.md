# AiGenerator — microservice déposé le 2026-09-20

Microservice Python/FastAPI qui produisait une fiche de plante à partir d'un nom
d'espèce. Déposé par #558. Le code reste accessible : `git checkout
aigenerator-final`.

## Ce qu'il faisait

Le backend Go l'appelait en HTTP interne sur `http://ai-generator:8000/generate`,
depuis `generateAndInsertPlant`, elle-même derrière deux routes réservées aux
administrateurs — `POST /plants/generate` et `/plants/generate-multiple`. Le
service demandait à un modèle de langage une fiche structurée, que le backend
complétait d'images Unsplash avant insertion dans Mongo.

Il a produit les **29 premières fiches du catalogue**, gratuitement, via le plan
Experiment de Mistral (#86, avril 2026). C'est aussi lui qui a fait entrer
Mistral dans le projet, deux ans avant que la question se repose pour le chatbot
et le diagnostic santé.

## Pourquoi il est parti

Ce n'est pas un échec technique : c'est un outil que le catalogue a dépassé.

**Aucun trafic.** Douze jours-conteneur mesurés en production et en dev le
2026-09-20 : zéro `POST /generate`, uniquement des `GET /health`.

**Aucune évolution depuis cinq mois.** Dernière modification fonctionnelle le
15 avril 2026.

**Un produit périmé.** #530 établit qu'il écrivait une fiche au schéma de 2024
dans une base de 2026. S'en servir aurait inséré une fiche fausse — ce qui
explique peut-être l'absence de trafic mieux que le désintérêt.

**Un coût réel.** Six des treize PR de dépendances en attente lui étaient
destinées (#349, #354, #355, #356, #129, #134), dont deux majeures. Plus un
conteneur, deux jobs de CI, une entrée Dependabot et trois clés d'API.

Son modèle par défaut, `mistral-small-latest`, n'existait d'ailleurs plus au
catalogue de l'organisation : le premier appel aurait rendu 429.

## Ce qui est parti avec lui

Côté Go, tout le chemin qui n'existait que pour l'appeler : `AIRequest`,
`generateAndInsertPlant`, `generatePlantWithAI`,
`generateMultiplePlantsHandler`, `trustedServiceEndpoint`,
`resolveModelFilename`, `normalizeModelNameKey`, les deux limiteurs de
génération, les deux routes d'administration, et le fichier **unsplash.go** en entier —
`fetchUnsplashImageURLs` n'avait pas d'autre appelant.

Côté infrastructure : le service `ai-generator`, la variable
`AI_GENERATOR_URL`, le `depends_on` du backend, les jobs `ai_generator` et
`build (ai-generator)`, et les deux entrées Dependabot.

## Un effet de bord qui comptait

`AI_PROVIDER` et `MISTRAL_API_KEY` étaient lues par l'AiGenerator **et**
destinées au backend. Cette collision imposait un suffixe `_BACKEND` sur les
noms de source dans `docker-compose.yml`, faute de quoi une seule valeur aurait
piloté deux services aux besoins opposés — le générateur sur Mistral, le backend
devant rester sur Gemini.

Sa dépose a supprimé la collision. Le backend a repris les noms nus.

## Si le besoin revient

Générer des fiches reste une idée valable ; c'est ce service-ci qui ne l'était
plus. Une reprise devrait partir du schéma actuel et non de celui de 2024, et
s'appuyer sur l'abstraction `LLMProvider` du backend plutôt que sur un second
service à déployer, surveiller et mettre à jour.
