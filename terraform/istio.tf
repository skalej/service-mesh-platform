resource "null_resource" "istio_install" {
  depends_on = [kind_cluster.default]

  provisioner "local-exec" {
    command = "istioctl install --set profile=${var.istio_profile} -y"
  }
}

resource "kubernetes_labels" "istio_injection" {
  depends_on = [null_resource.istio_install]

  api_version = "v1"
  kind        = "Namespace"
  metadata {
    name = "default"
  }
  labels = {
    "istio-injection" = "enabled"
  }
}

resource "null_resource" "istio_telemetry" {
  depends_on = [null_resource.istio_install]

  provisioner "local-exec" {
    command = "kubectl apply -f ${path.module}/../istio/telemetry.yaml"
  }
}