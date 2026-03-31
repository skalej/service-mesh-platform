resource "null_resource" "observability" {
  depends_on = [null_resource.istio_install]

  provisioner "local-exec" {
    command = <<-EOT
        kubectl apply -f ${path.module}/../observability/jaeger.yaml
        kubectl apply -f ${path.module}/../observability/prometheus.yaml
        kubectl apply -f ${path.module}/../observability/kiali.yaml
      EOT
  }
}