#!/bin/sh
# ---------------------------------------------------------------------------
# Setup script for the service-mesh-platform Kind cluster.
#
# What it does:
#   1. Starts a local Docker registry on localhost:5000
#   2. Creates a 2-node Kind cluster (1 control-plane + 1 worker)
#   3. Connects the registry to the Kind Docker network
#   4. Configures containerd on each node to pull from the local registry
#   5. Labels the control-plane node for ingress scheduling
#   6. Registers the registry with the cluster via a ConfigMap
#
# The script is idempotent — safe to run multiple times.
# It skips any step where the resource already exists.
#
# Usage:
#   chmod +x kind/setup.sh
#   ./kind/setup.sh
#
# Teardown:
#   kind delete cluster --name service-mesh-platform
#   docker rm -f kind-registry
# ---------------------------------------------------------------------------

set -e  # Exit immediately if any command fails

CLUSTER_NAME="service-mesh-platform"
REGISTRY_NAME="kind-registry"
REGISTRY_PORT="5000"

# ---- Step 1: Local Docker registry ----------------------------------------
# We run a local registry so we can push images to localhost:5000 and
# have the Kind nodes pull from it — no Docker Hub account needed.

if docker inspect "${REGISTRY_NAME}" >/dev/null 2>&1; then
  echo "Registry '${REGISTRY_NAME}' already running, skipping."
else
  echo "Starting local Docker registry on port ${REGISTRY_PORT}..."
  docker run -d \
    --restart=always \
    --name "${REGISTRY_NAME}" \
    -p "127.0.0.1:${REGISTRY_PORT}:5000" \
    registry:2
fi

# ---- Step 2: Kind cluster -------------------------------------------------
# Creates the cluster using cluster-config.yaml which sets up:
#   - Port mappings (80/443) for ingress
#   - 1 control-plane + 1 worker node

if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  echo "Cluster '${CLUSTER_NAME}' already exists, skipping."
else
  echo "Creating Kind cluster '${CLUSTER_NAME}'..."
  kind create cluster \
    --name "${CLUSTER_NAME}" \
    --config "$(dirname "$0")/cluster-config.yaml"
fi

# ---- Step 3: Connect registry to Kind network -----------------------------
# Kind nodes run inside the "kind" Docker network.
# The registry container needs to be on the same network
# so nodes can pull images from it using the container name.

if docker network inspect kind | grep -q "${REGISTRY_NAME}"; then
  echo "Registry already connected to 'kind' network, skipping."
else
  echo "Connecting registry to Kind network..."
  docker network connect kind "${REGISTRY_NAME}"
fi

# ---- Step 4: Configure containerd to use the local registry ----------------
# Tell containerd inside each Kind node that "localhost:5000" should be
# fetched from the "kind-registry" container on the Docker network.
#
# We do this post-creation because containerdConfigPatches in the Kind
# config caused kubelet failures on K8s v1.35.

REGISTRY_DIR="/etc/containerd/certs.d/localhost:${REGISTRY_PORT}"
for NODE in $(kind get nodes --name "${CLUSTER_NAME}"); do
  echo "Configuring registry mirror on node '${NODE}'..."
  docker exec "${NODE}" mkdir -p "${REGISTRY_DIR}"
  docker exec -i "${NODE}" sh -c "cat > ${REGISTRY_DIR}/hosts.toml" <<TOML
[host."http://${REGISTRY_NAME}:5000"]
  capabilities = ["pull", "resolve", "push"]
TOML
done

# ---- Step 5: Label control-plane node for ingress --------------------------
# Kong ingress controller uses a nodeSelector to find the node with
# host port mappings (80/443). This label tells it where to schedule.
#
# Note: we do this post-creation because kubeadmConfigPatches with
# kubeletExtraArgs is broken on K8s v1.35 (deprecated v1beta3 API).

echo "Labeling control-plane node for ingress..."
kubectl label node "${CLUSTER_NAME}-control-plane" ingress-ready=true --overwrite

# ---- Step 6: Register the registry with the cluster -----------------------
# This ConfigMap in kube-public is a Kind convention.
# It tells tooling (Tilt, Skaffold, etc.) where the local registry lives.

echo "Creating local-registry-hosting ConfigMap..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "localhost:${REGISTRY_PORT}"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF

echo ""
echo "Done! Cluster '${CLUSTER_NAME}' is ready."
echo "  Nodes:    kubectl get nodes"
echo "  Registry: localhost:${REGISTRY_PORT}"
