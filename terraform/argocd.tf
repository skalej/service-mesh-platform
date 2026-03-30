resource "kubernetes_namespace" "argocd" {
  depends_on = [kind_cluster.default]

  metadata {
    name = "argocd"
  }
}

resource "null_resource" "argocd_install" {
  depends_on = [kubernetes_namespace.argocd]

  provisioner "local-exec" {
    command = "kubectl apply -n argocd --server-side -f https://raw.githubusercontent.com/argoproj/argo-cd/${var.argocd_version}/manifests/install.yaml"
  }
}

resource "null_resource" "argocd_wait" {
  depends_on = [null_resource.argocd_install]

  provisioner "local-exec" {
    command = "kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=120s"
  }
}

resource "null_resource" "argocd_root_app" {
  depends_on = [
    null_resource.argocd_wait,
    null_resource.istio_telemetry,
    null_resource.kong_plugins,
    null_resource.observability,
    null_resource.external_secrets_config,
    null_resource.cert_manager_issuer,
    null_resource.opa_constraints,
  ]

  provisioner "local-exec" {
    command = "kubectl apply -f ${path.module}/../argocd/root-app.yaml"
  }
}

data "kubernetes_secret" "argocd_admin" {
  depends_on = [null_resource.argocd_wait]

  metadata {
    name      = "argocd-initial-admin-secret"
    namespace = "argocd"
  }
}