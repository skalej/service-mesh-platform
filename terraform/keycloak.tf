# ---- Keycloak ----

# Create the namespace explicitly so the ExternalSecret can be applied
# before the Helm release runs (Helm would create it too late).
resource "kubernetes_namespace" "keycloak" {
  depends_on = [kind_cluster.default]

  metadata {
    name = "keycloak"
  }
}

# Apply the keycloak ExternalSecret and wait for the K8s secret to sync
# before the Helm release runs — the pod mounts keycloak-credentials at
# startup and gets stuck in CreateContainerConfigError if it doesn't exist.
#
# Depends on external_secrets_config (not external_secrets directly) so the
# ClusterSecretStore is guaranteed to be applied before this ExternalSecret.
resource "null_resource" "keycloak_secret" {
  depends_on = [
    null_resource.external_secrets_config,
    kubernetes_namespace.keycloak,
  ]

  triggers = {
    script = sha256(<<-EOT
        kubectl apply -f ${path.module}/../platform/external-secrets/keycloak-external-secret.yaml
        kubectl wait --for=condition=Ready externalsecret/keycloak-credentials -n keycloak --timeout=60s
      EOT
    )
  }

  provisioner "local-exec" {
    command = <<-EOT
        kubectl apply -f ${path.module}/../platform/external-secrets/keycloak-external-secret.yaml
        kubectl wait --for=condition=Ready externalsecret/keycloak-credentials -n keycloak --timeout=60s
      EOT
  }
}

resource "helm_release" "keycloak" {
  depends_on = [null_resource.keycloak_secret]

  name       = "keycloak"
  chart      = "keycloakx"
  repository = "https://codecentric.github.io/helm-charts"
  namespace  = kubernetes_namespace.keycloak.metadata[0].name
  wait       = true
  timeout    = 300

  values = [<<-YAML
    args:
      - start-dev

    extraEnv: |
      - name: KEYCLOAK_ADMIN
        valueFrom:
          secretKeyRef:
            name: keycloak-credentials
            key: KEYCLOAK_ADMIN
      - name: KEYCLOAK_ADMIN_PASSWORD
        valueFrom:
          secretKeyRef:
            name: keycloak-credentials
            key: KEYCLOAK_ADMIN_PASSWORD
  YAML
  ]
}
