output "kubeconfig_path" {
  description = "Path to the Kind cluster kubeconfig"
  value       = kind_cluster.default.kubeconfig_path
}

output "argocd_admin_password" {
  description = "ArgoCD initial admin password"
  sensitive   = true
  value       = data.kubernetes_secret.argocd_admin.data["password"]
}

output "registry_url" {
  description = "Local Docker registry URL"
  value       = "localhost:${var.registry_port}"
}