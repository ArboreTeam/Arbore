provider "cloudflare" {
  # Jamais en dur : fourni par TF_VAR_cloudflare_api_token, lui-même issu du jeu
  # SOPS. Le jeton a besoin de Zone:DNS:Edit et Workers R2 Storage:Edit — rien
  # de plus. Un jeton « Global API Key » donnerait à la CI le droit de supprimer
  # la zone.
  api_token = var.cloudflare_api_token
}
