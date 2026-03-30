resource "kind_cluster" "default" {
  name           = var.cluster_name
  wait_for_ready = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"
      extra_port_mappings {
        container_port = 80
        host_port      = 80
      }
      extra_port_mappings {
        container_port = 443
        host_port      = 443
      }
    }
    node { role = "worker" }
    node { role = "worker" }
  }
}

resource "null_resource" "local_registry" {
  depends_on = [kind_cluster.default]

  provisioner "local-exec" {
    command = <<-EOT
        if docker inspect kind-registry >/dev/null 2>&1; then
          echo "Registry already running, skipping."
        else
          docker run -d --restart=always --name kind-registry -p "127.0.0.1:${var.registry_port}:5000" registry:2
        fi
      EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = "docker rm -f kind-registry || true"
  }
}

resource "null_resource" "connect_registry" {
  depends_on = [null_resource.local_registry]

  provisioner "local-exec" {
    command = <<-EOT
        if docker network inspect kind | grep -q kind-registry; then
          echo "Registry already on kind network, skipping."
        else
          docker network connect kind kind-registry
        fi
      EOT
  }
}

resource "null_resource" "configure_containerd" {
  depends_on = [null_resource.connect_registry]

  provisioner "local-exec" {
    command = <<-EOT
        REGISTRY_DIR="/etc/containerd/certs.d/localhost:${var.registry_port}"
        for NODE in $(kind get nodes --name ${var.cluster_name}); do
          docker exec "$NODE" mkdir -p "$REGISTRY_DIR"
          printf '[host."http://kind-registry:5000"]\n  capabilities = ["pull", "resolve", "push"]\n' | docker exec -i "$NODE" sh -c "cat > $REGISTRY_DIR/hosts.toml"
        done
      EOT
  }
}

resource "kubernetes_labels" "ingress_ready" {
  depends_on = [kind_cluster.default]

  api_version = "v1"
  kind        = "Node"
  metadata {
    name = "${var.cluster_name}-control-plane"
  }
  labels = {
    "ingress-ready" = "true"
  }
}

resource "kubernetes_config_map" "local_registry_hosting" {
  depends_on = [kind_cluster.default]

  metadata {
    name      = "local-registry-hosting"
    namespace = "kube-public"
  }

  data = {
    "localRegistryHosting.v1" = <<-EOF
host: "localhost:${var.registry_port}"
help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF
  }
}

