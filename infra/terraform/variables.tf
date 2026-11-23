# ---------------------------------------------------------------------------
# Variables PERSONNELLES (à mettre dans terraform.tfvars, jamais commité)
# ---------------------------------------------------------------------------

variable "project_id" {
  description = "ID du projet GCP de la personne qui déploie."
  type        = string
}

variable "owner" {
  description = "Prénom (minuscules) de la personne qui déploie, ajouté en label GCP."
  type        = string
  default     = "team"
}

variable "admin_cidrs" {
  description = "IP publiques autorisées en SSH (ex: [\"203.0.113.7/32\"]). Obtenir la sienne : curl -4 ifconfig.me"
  type        = list(string)
}

# ---------------------------------------------------------------------------
# Variables COMMUNES : ne pas les surcharger pendant la campagne de mesures,
# sinon les résultats ne sont plus comparables entre membres de l'équipe.
# ---------------------------------------------------------------------------

variable "cluster_name" {
  description = "Préfixe des ressources (doit rester court, minuscules)."
  type        = string
  default     = "cbench"
}

variable "region" {
  type    = string
  default = "europe-west1"
}

variable "zone" {
  type    = string
  default = "europe-west1-b"
}

variable "subnet_cidr" {
  type    = string
  default = "10.10.0.0/24"
}

variable "worker_count" {
  description = "Nombre de workers. 3 workers + 1 master en 2 vCPU = 8 vCPU (plafond de l'essai gratuit GCP)."
  type        = number
  default     = 3
}

variable "master_machine_type" {
  type    = string
  default = "n2-standard-2"
}

variable "worker_machine_type" {
  description = "n2 = vCPU dédiés (pas de crédits CPU comme e2/t3/B-series) => mesures stables."
  type        = string
  default     = "n2-standard-2"
}

variable "min_cpu_platform" {
  description = "Force la même génération de CPU pour tous les clusters de l'équipe. Mettre null si indisponible dans la zone."
  type        = string
  default     = "Intel Ice Lake"
  nullable    = true
}

variable "image_project" {
  type    = string
  default = "ubuntu-os-cloud"
}

variable "image_family" {
  type    = string
  default = "ubuntu-2404-lts-amd64"
}

variable "image_name" {
  description = "Image exacte à utiliser (figée au tag v1.0 pour que tout le monde ait le même OS). Vide = dernière image de la famille."
  type        = string
  default     = ""
}

variable "boot_disk_gb" {
  type    = number
  default = 20
}

variable "data_disk_type" {
  description = "pd-balanced : SSD réseau à performances prévisibles. Éviter pd-standard (HDD lent et très variable)."
  type        = string
  default     = "pd-balanced"
}

variable "worker_data_disk_gb" {
  description = "Disque /data des workers : HDFS + fichiers de shuffle Spark."
  type        = number
  default     = 200
}

variable "master_data_disk_gb" {
  description = "Disque /data du master : métadonnées NameNode, Prometheus, logs."
  type        = number
  default     = 50
}

variable "ssh_user" {
  type    = string
  default = "ubuntu"
}

variable "ssh_public_key_path" {
  description = "Clé publique déposée sur les VMs (générée par `make keys`)."
  type        = string
  default     = "../../.secrets/id_ed25519.pub"
}

variable "ssh_private_key_path" {
  description = "Chemin de la clé privée tel que vu par Ansible (dans la toolbox : ~/.ssh/cluster_key)."
  type        = string
  default     = "~/.ssh/cluster_key"
}
