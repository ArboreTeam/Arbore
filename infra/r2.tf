# Le bucket porte 372 objets vérifiés par empreinte (migration du 2026-09-07).
# Sa destruction n'est pas récupérable depuis le dépôt : les modèles sources
# sont gitignorés et déployés hors bande.
resource "cloudflare_r2_bucket" "assets" {
  account_id   = var.cloudflare_account_id
  name         = var.r2_bucket_name
  jurisdiction = var.r2_jurisdiction

  lifecycle {
    # Un `terraform destroy` ou un plan mal relu ne doit pas pouvoir emporter
    # les assets. Le retirer volontairement est un geste conscient, pas un
    # effet de bord.
    prevent_destroy = true
  }
}
