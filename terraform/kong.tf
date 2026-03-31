# Gateway API CRDs must be installed before Kong so the controller can
# register the GatewayClass and watch HTTPRoute/ReferenceGrant resources.
resource "null_resource" "gateway_api_crds" {
  depends_on = [kind_cluster.default]

  provisioner "local-exec" {
    command = "kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml"
  }
}

resource "helm_release" "kong" {
  depends_on = [null_resource.istio_install, helm_release.gatekeeper, null_resource.gateway_api_crds]

  name             = "kong"
  repository       = "https://charts.konghq.com"
  chart            = "ingress"
  namespace        = "kong"
  create_namespace = true
  wait             = true

  values = [file("${path.module}/../kong/values.yaml")]
  # forces redeployment if values change
  force_update = true
}

# resource "kubernetes_manifest" "kong_gateway_class" {
#   manifest = {
#     apiVersion = "gateway.networking.k8s.io/v1beta1"
#     kind       = "GatewayClass"
#     metadata = {
#       name = "kong"
#     }
#     spec = {
#       controllerName = "konghq.com/gateway-controller"
#     }
#   }
#
#   depends_on = [helm_release.kong]
# }
#
# resource "kubernetes_manifest" "kong_gateway" {
#   manifest = {
#     apiVersion = "gateway.networking.k8s.io/v1beta1"
#     kind       = "Gateway"
#     metadata = {
#       name      = "kong-gateway"
#       namespace = "kong"
#     }
#     spec = {
#       gatewayClassName = "kong"
#       listeners = [
#         {
#           name     = "http"
#           protocol = "HTTP"
#           port     = 80
#         }
#       ]
#     }
#   }
#
#   depends_on = [kubernetes_manifest.kong_gateway_class]
# }

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
        kubectl apply -f ${path.module}/../kong/plugins/jwt.yaml
        kubectl apply -f ${path.module}/../kong/ingress.yaml
      EOT
  }
}
