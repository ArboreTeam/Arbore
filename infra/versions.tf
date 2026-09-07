terraform {
  # Épinglé au CLI, comme le lockfile l'est aux providers. `use_lockfile` sur le
  # backend S3 (verrouillage natif, sans DynamoDB) requiert Terraform >= 1.10 —
  # R2 n'offre pas DynamoDB, c'est donc le seul verrou disponible ici.
  required_version = "~> 1.10"

  required_providers {
    cloudflare = {
      source = "cloudflare/cloudflare"
      # Le provider est passé en v5 avec un renommage massif des ressources
      # (`cloudflare_record` → `cloudflare_dns_record`, entre autres). La
      # contrainte majeure n'est pas cosmétique : un `~> 4.0` produirait un plan
      # qui détruit et recrée tout.
      version = "~> 5.0"
    }
  }

  # Configuration partielle : le reste vient de `envs/<env>.backend.hcl`, passé
  # à `terraform init -backend-config=`. C'est ce qui donne un state distinct
  # par environnement sans dupliquer le code (#401 §3).
  #
  # Le state contient les secrets EN CLAIR (clés R2, user Atlas). Il ne doit
  # jamais être commité — cf. .gitignore à la racine de infra/.
  backend "s3" {}
}
