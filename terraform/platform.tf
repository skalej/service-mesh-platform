# ---- cert-manager ----

resource "helm_release" "cert_manager" {
  depends_on = [kind_cluster.default]

  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  wait             = true

  set {
    name  = "installCRDs"
    value = "true"
  }
}

resource "null_resource" "cert_manager_issuer" {
  depends_on = [helm_release.cert_manager]

  provisioner "local-exec" {
    command = "kubectl apply -f ${path.module}/../platform/cert-manager/cluster-issuer.yaml"
  }
}

# ---- OPA / Gatekeeper ----

resource "helm_release" "gatekeeper" {
  depends_on = [kind_cluster.default]

  name             = "gatekeeper"
  repository       = "https://open-policy-agent.github.io/gatekeeper/charts"
  chart            = "gatekeeper"
  namespace        = "gatekeeper-system"
  create_namespace = true
  wait             = true
  timeout          = 300
}

resource "null_resource" "opa_constraints" {
  depends_on = [helm_release.gatekeeper]

  provisioner "local-exec" {
    command = <<-EOT
        kubectl apply -f ${path.module}/../platform/opa/require-resource-limits-template.yaml
        sleep 5
        kubectl apply -f ${path.module}/../platform/opa/require-resource-limits.yaml
      EOT
  }
}

# ---- Vault ----

resource "helm_release" "vault" {
  depends_on = [kind_cluster.default]

  name             = "vault"
  repository       = "https://helm.releases.hashicorp.com"
  chart            = "vault"
  namespace        = "vault"
  create_namespace = true
  wait             = true

  set {
    name  = "server.dev.enabled"
    value = "true"
  }

  set {
    name  = "server.dev.devRootToken"
    value = "root"
  }
}

resource "null_resource" "vault_init" {
  depends_on = [helm_release.vault]

  provisioner "local-exec" {
    command = <<-EOT
        kubectl wait --for=condition=ready pod/vault-0 -n vault --timeout=120s
        kubectl exec -n vault vault-0 -- vault kv put secret/apollo GRAPH_VARIANT=local
        kubectl create secret generic vault-token -n vault --from-literal=token=root --dry-run=client -o yaml | kubectl apply -f -
      EOT
  }
}

# ---- external-secrets ----

resource "helm_release" "external_secrets" {
  depends_on = [kind_cluster.default]

  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  wait             = true
}

resource "null_resource" "external_secrets_config" {
  depends_on = [helm_release.external_secrets, null_resource.vault_init]

  provisioner "local-exec" {
    command = <<-EOT
        kubectl apply -f ${path.module}/../platform/external-secrets/secret-store.yaml
        sleep 5
        kubectl apply -f ${path.module}/../platform/external-secrets/apollo-external-secret.yaml
      EOT
  }
}