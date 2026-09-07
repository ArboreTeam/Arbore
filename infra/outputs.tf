output "r2_s3_endpoint" {
  description = "Valeur à reporter dans STORAGE_S3_ENDPOINT (hôte seul, sans schéma ni chemin)."
  value       = "${var.cloudflare_account_id}.${var.r2_jurisdiction}.r2.cloudflarestorage.com"
}

output "api_url" {
  value = "https://${var.api_hostname}"
}

output "web_url" {
  value = "https://${var.web_hostname}"
}
