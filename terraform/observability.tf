resource "null_resource" "observability" {
  depends_on = [null_resource.istio_install]

  provisioner "local-exec" {
    command = <<-EOT
        kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.24/samples/addons/jaeger.yaml
        kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.24/samples/addons/prometheus.yaml
        kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.24/samples/addons/kiali.yaml
      EOT
  }
}