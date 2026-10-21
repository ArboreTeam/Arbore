variable "cloudflare_api_token" {
  description = "Jeton API Cloudflare (Zone:DNS:Edit + Workers R2 Storage:Edit)."
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Identifiant du compte Cloudflare, propriétaire des buckets R2."
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Identifiant de la zone arbore.app."
  type        = string
}

variable "environment" {
  description = "Type d'environnement (#401) : dev, test, pre-prod, prod."
  type        = string

  validation {
    condition     = contains(["dev", "test", "pre-prod", "prod"], var.environment)
    error_message = "environment doit valoir dev, test, pre-prod ou prod."
  }
}

variable "domain" {
  description = "Domaine racine servant cet environnement."
  type        = string
  default     = "arbore.app"
}

variable "api_hostname" {
  description = "Nom d'hôte du backend Go. Varie par environnement (#401 §3)."
  type        = string
}

variable "web_hostname" {
  description = "Nom d'hôte de l'application Next.js."
  type        = string
}

variable "origin_ip" {
  description = <<-EOT
    Adresse IPv4 de la machine servant cet environnement.
    Le pare-feu d'origine n'accepte que les plages Cloudflare sur :80
    (cf. ops/systemd/cf-http-firewall.service) : ces enregistrements DOIVENT
    rester proxifiés, sinon l'origine devient injoignable.
  EOT
  type        = string
}

variable "r2_bucket_name" {
  description = "Bucket R2 des modèles 3D et miniatures."
  type        = string
}

variable "r2_jurisdiction" {
  description = "Juridiction R2. « eu » maintient les données dans l'UE et impose le préfixe .eu. dans l'endpoint S3."
  type        = string
  default     = "eu"
}

variable "manage_zone_records" {
  description = <<-EOT
    Gérer les enregistrements de zone (apex, messagerie, site vitrine) ?
    Vrai en production seulement : ils appartiennent au domaine, pas à un
    environnement. Un environnement de dev qui les redéclarerait entrerait en
    conflit avec ceux de la production.
  EOT
  type        = bool
  default     = false
}

variable "enable_dev_hostnames" {
  description = <<-EOT
    Créer les noms d'hôte de l'environnement de dev (`api-dev`).
    Par défaut ils pointent la MÊME machine que la production : les deux piles
    cohabitent sur le VPS, nginx les distingue par `server_name`.
    Pour les faire pointer ailleurs, voir `dev_origin_ip`.
  EOT
  type        = bool
  default     = false
}

variable "generator_origin_ip" {
  description = <<-EOT
    Adresse IPv4 servant l'atelier 3D, quand elle DIFFÈRE de `origin_ip`.
    Vide = l'atelier suit la production.

    L'atelier est un OUTIL, pas une surface d'utilisateur : il n'est pas
    appelé par l'app mobile. Il doit vivre là où se trouvent les modèles
    qu'il produit, sinon chaque livraison demande un transfert à la main
    entre deux machines (#652).

    Le déplacer ne déplace aucune donnée de base : son état est un fichier,
    `/data/generator/etat.json`, et son code n'accède pas à Mongo. Ce qui
    bouge, c'est quel disque il lit.

    Même contrainte que `origin_ip` : l'enregistrement reste proxifié.
  EOT
  type        = string
  default     = ""
}

variable "dev_origin_ip" {
  description = <<-EOT
    Adresse IPv4 servant l'environnement de dev, quand elle DIFFÈRE de
    `origin_ip`. Vide = dev suit la production, ce qui reste le cas normal.

    Sa raison d'être est la migration de VPS (#652) : basculer `api-dev` seul
    éprouve toute la chaîne Cloudflare — proxy, certificat d'origine, pare-feu
    — contre la machine neuve, sans toucher au trafic réel. Sans cette
    variable, les trois enregistrements partagent `origin_ip` et il faut tout
    basculer d'un coup.

    Même contrainte que `origin_ip` : l'enregistrement reste proxifié, sinon
    le pare-feu d'origine rend la machine injoignable.
  EOT
  type        = string
  default     = ""
}
