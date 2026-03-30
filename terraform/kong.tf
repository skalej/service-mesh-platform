resource "helm_release" "kong" {
  depends_on = [null_resource.istio_install, helm_release.gatekeeper]

  name             = "kong"
  repository       = "https://charts.konghq.com"
  chart            = "ingress"
  namespace        = "kong"
  create_namespace = true
  wait             = true

  values = [file("${path.module}/../kong/values.yaml")]
}

resource "null_resource" "kong_hostport_patch" {
  depends_on = [helm_release.kong]

  provisioner "local-exec" {
    command = "sh ${path.module}/../kong/patch-hostport.sh"
  }
}

resource "null_resource" "kong_plugins" {
  depends_on = [null_resource.kong_hostport_patch]

  provisioner "local-exec" {
    command = <<-EOT
        kubectl apply -f ${path.module}/../kong/plugins/rate-limit.yaml
        kubectl apply -f ${path.module}/../kong/ingress.yaml
      EOT
  }
}