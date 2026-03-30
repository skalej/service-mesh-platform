variable "cluster_name" {
  description = "Name of the Kind cluster"
  type        = string
  default     = "service-mesh-platform"
}

variable "registry_port" {
  description = "Local Docker registry port"
  type        = number
  default     = 5000
}

variable "istio_profile" {
  description = "Istio installation profile"
  type        = string
  default     = "demo"
}

variable "argocd_version" {
  description = "ArgoCD manifest version tag"
  type        = string
  default     = "stable"
}