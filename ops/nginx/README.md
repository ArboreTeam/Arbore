# `ops/nginx/` — configuration du reverse-proxy

Appliquée par `deploy.sh` vers `/etc/nginx/conf.d/`, validée par `nginx -t`
**avant** rechargement. Une configuration invalide interrompt le déploiement
sans toucher au service en cours.

## Ce qui n'est PAS ici

Les **certificats** `/etc/ssl/cloudflare/origin.{pem,key}` — ce sont des
secrets, et ils restent hors dépôt. Une machine neuve doit les recevoir avant
que les blocs `listen 443` ne fonctionnent ; nginx refusera de démarrer sinon.

C'est le troisième geste manuel d'une migration, après l'installation de Docker
et la pose de la clé age.
