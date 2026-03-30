# Service Mesh Platform

Kong API Gateway + Istio service mesh + Apollo GraphQL federation on a local Kind cluster with ArgoCD for GitOps.

## Architecture

| Component          | Tool                          |
|--------------------|-------------------------------|
| Local K8s          | Kind (2-3 nodes)              |
| API Gateway        | Kong                          |
| Service Mesh       | Istio + Envoy sidecars        |
| GraphQL Federation | Apollo Router                 |
| Subgraph: Catalog  | Kotlin / Spring Boot (DGS)    |
| Subgraph: Shipping | Go (gqlgen)                   |
| Database           | PostgreSQL (Helm)             |
| Observability      | Jaeger, Prometheus, Kiali     |
| GitOps / CD        | ArgoCD                        |
| CI                 | GitHub Actions                |

## Component Overview

### Infrastructure

- **Kind** — runs a full Kubernetes cluster locally using Docker containers as nodes. Each node is a container, so you get a realistic multi-node cluster without VMs. Destroyed with one command when you're done.
- **Local Docker Registry** — a mini Docker Hub on `localhost:5000`. Services are built and pushed here. Kind nodes pull from it directly over the local Docker network — no internet or Docker Hub account needed.
- **Helm** — package manager for Kubernetes. We use a single shared chart for all our services, with per-service values files to override image, port, resources, etc.

### Traffic Flow

- **Kong API Gateway** — the single entry point for all external traffic. Handles JWT authentication, rate limiting, and routes requests to the right backend. Runs as a Kubernetes ingress controller.
- **Apollo Router** — a GraphQL federation gateway. Sits behind Kong and composes a single unified GraphQL API from multiple subgraph services. Clients send one query; Apollo splits it across the right subgraphs.
- **Catalog (Kotlin/Spring Boot)** — a GraphQL subgraph serving product data. Uses Netflix DGS for Apollo-compatible federation.
- **Shipping (Go)** — a GraphQL subgraph serving shipping/delivery data. Uses gqlgen with the Apollo Federation plugin. Kept in Go to demonstrate a polyglot mesh.
- **PostgreSQL** — relational database deployed locally via Helm. Stands in for a managed database (RDS/CloudSQL) you'd use in production.

### Service Mesh

- **Istio** — service mesh that injects an Envoy sidecar proxy into every pod. All service-to-service traffic flows through these sidecars, giving you mTLS encryption, traffic control, and observability without changing application code.
- **Envoy sidecars** — transparent proxies injected by Istio into each pod. They intercept all inbound/outbound traffic and enforce mTLS, circuit breaking, retries, and timeouts.
- **Egress Gateway** — controls and logs all traffic leaving the mesh to external services (database, SaaS APIs). Prevents services from making unauthorized outbound calls.

#### How traffic flows through the mesh

Istio configures iptables rules inside each pod that redirect ALL traffic through the Envoy sidecar. Services don't know about it — the sidecars are fully transparent.

```
                        INBOUND (e.g. Kong → Apollo Router)
                        ─────────────────────────────────────
Kong sends to apollo-router:4000
  → request arrives at Apollo Router pod's network
  → iptables intercepts BEFORE it reaches the app container
  → Envoy sidecar receives it, terminates mTLS, applies policies
  → Envoy forwards to localhost:4000 inside the same pod
  → Apollo Router receives the plain HTTP request

                        OUTBOUND (e.g. Apollo Router → Catalog)
                        ─────────────────────────────────────────
Apollo Router sends to catalog:4001
  → iptables intercepts the outgoing traffic
  → Envoy sidecar encrypts it with mTLS
  → sends to Catalog pod's Envoy sidecar
  → Catalog's Envoy decrypts, forwards to localhost:4001
  → Catalog app receives the plain HTTP request

                        FULL REQUEST PATH
                        ─────────────────
Browser → localhost:80 → Kong Gateway (no sidecar)
  → Apollo Router pod: Envoy sidecar → Apollo Router app
    → Catalog pod: Envoy sidecar ←(mTLS)→ Envoy sidecar → Catalog app
    → Shipping pod: Envoy sidecar ←(mTLS)→ Envoy sidecar → Shipping app
```

Kong doesn't need a sidecar — it sits outside the mesh as the north-south gateway. Istio's default **permissive mode** accepts both plain and mTLS traffic, so Kong's plain HTTP requests still work. Switching to **strict mode** would require Kong to present a valid mesh certificate.

#### mTLS modes: permissive vs strict

Istio supports two mTLS modes, controlled by a `PeerAuthentication` resource:

| | Permissive (default) | Strict |
|---|---|---|
| **Accepts plaintext** | Yes — both plain HTTP and mTLS | No — mTLS only |
| **Sidecar-to-sidecar** | Encrypted (mTLS) | Encrypted (mTLS) |
| **Non-mesh to mesh** | Works (plain HTTP accepted) | Rejected (no valid cert) |
| **Security** | Weaker — attackers inside the cluster can send plain HTTP | Stronger — all traffic must be authenticated |
| **Use case** | Migration phase, or when non-mesh components (Kong) talk to mesh services | Full production lockdown |

Currently we use **permissive** (the default — no explicit `PeerAuthentication` resource exists). This is necessary because of our traffic flow:

```
Browser → Kong (NO sidecar, outside mesh) → plain HTTP → Apollo Router (HAS sidecar, inside mesh)
```

Kong sends **plain HTTP** to Apollo Router. Apollo Router's Envoy sidecar accepts it because permissive mode allows both plain and mTLS traffic.

**Why STRICT mode breaks this:**

If we apply STRICT mTLS:

```yaml
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: default
  namespace: default
spec:
  mtls:
    mode: STRICT
```

Apollo Router's sidecar will **reject** Kong's requests because Kong can't present a valid Istio mTLS certificate. The connection dies at the sidecar before reaching the app:

```
Kong → plain HTTP → Apollo Router's Envoy sidecar → REJECTED (no mTLS cert)
```

**How to enable STRICT without breaking Kong:**

Option 1 — **Exempt Apollo Router's inbound port** from strict mTLS using a port-level override:

```yaml
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: default
  namespace: default
spec:
  mtls:
    mode: STRICT
  portLevelMtls:
    4000:          # Apollo Router's port
      mode: PERMISSIVE   # allow Kong's plain HTTP on this port only
```

This gives you STRICT mTLS for all service-to-service traffic (Apollo Router ↔ Catalog ↔ Shipping) while still allowing Kong's plaintext traffic to reach Apollo Router.

Option 2 — **Add Kong to the mesh** by injecting a sidecar. Then Kong's traffic is mTLS too and STRICT works everywhere. But this adds complexity to Kong's deployment.

Option 3 — **Use Istio's ingress gateway** instead of Kong for north-south traffic. Then everything is inside the mesh. But you lose Kong's plugin ecosystem (rate limiting, JWT, etc.).

#### Service accounts as mesh identity

In Kubernetes, a ServiceAccount is just an identity attached to a pod. In a service mesh, it becomes much more important — it's how Istio identifies **who** is making a request.

When Istio injects a sidecar, it issues an mTLS certificate based on the pod's service account. The certificate contains a SPIFFE identity:

```
cluster.local/ns/<namespace>/sa/<service-account-name>
```

For example, Apollo Router gets the identity `cluster.local/ns/default/sa/apollo-router`.

This is what makes AuthorizationPolicy work:

```
Apollo Router (sa/apollo-router) → calls → Catalog
  1. Apollo Router's sidecar presents its cert: "I am sa/apollo-router"
  2. Catalog's sidecar checks AuthorizationPolicy: "Is sa/apollo-router allowed?"
  3. Match → request forwarded. No match → 403 denied.
```

Without per-service service accounts, all pods in a namespace share the `default` service account — making it impossible to distinguish callers. That's why the Helm chart creates one per service:

```yaml
# Each service gets its own identity
serviceAccount:
  create: true   # creates "catalog" SA, "shipping" SA, "apollo-router" SA
```

| Service | Service Account | SPIFFE Identity |
|---|---|---|
| Catalog | `catalog` | `cluster.local/ns/default/sa/catalog` |
| Shipping | `shipping` | `cluster.local/ns/default/sa/shipping` |
| Apollo Router | `apollo-router` | `cluster.local/ns/default/sa/apollo-router` |

#### Circuit breaker: Istio vs application-level

Istio provides infrastructure-level circuit breaking via Envoy. In practice, you use **both** Istio and an app-level library (e.g. Resilience4j) — they complement each other.

| | Istio (Envoy) | App-level (Resilience4j) |
|---|---|---|
| **Triggers on** | Connection count, pending requests, consecutive 5xx | Latency, error rate, slow call %, custom conditions |
| **Fallback** | Returns 503, app must handle it | Can return cached data, defaults, or call alternative service |
| **Granularity** | Per-service (all requests to `shipping:4002` treated the same) | Per-method/per-operation |
| **State visibility** | Via Prometheus/Kiali metrics | Queryable from app code ("is circuit open?") |
| **Code changes** | None — configured as YAML (DestinationRule) | Requires code in every service |
| **Best for** | Infrastructure safety net, prevent cascade failures across the mesh | Business-level resilience, graceful degradation |

#### S2S Authorization: Istio vs OPA (Rego)

For service-to-service authorization with scope checking (e.g., "does the calling service have `catalog:read` permission?"), there are two approaches:

**Istio (RequestAuthentication + AuthorizationPolicy)** — each service client gets a JWT with scopes. Istio validates the token at the sidecar and checks claims before the request reaches the app:

```yaml
# Validate the S2S JWT token
apiVersion: security.istio.io/v1
kind: RequestAuthentication
metadata:
  name: catalog-s2s-jwt
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: catalog
  jwtRules:
    - issuer: "https://your-idp.com"
      jwksUri: "https://your-idp.com/.well-known/jwks.json"

---
# Only allow requests with the required scope
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: catalog-require-scope
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: catalog
  action: ALLOW
  rules:
    - when:
        - key: request.auth.claims[scope]
          values: ["catalog:read"]
```

**OPA (Open Policy Agent)** — a general-purpose policy engine. Policies are written in Rego (a declarative language). OPA runs as a sidecar or external service and can evaluate anything: scopes, headers, request body, time-based rules, etc.

| | Istio JWT + AuthorizationPolicy | OPA (Rego) |
|---|---|---|
| **Setup** | YAML only — no code | Requires writing Rego policies |
| **Scope checks** | Yes — via JWT claims | Yes — plus any custom logic |
| **Granularity** | Per-service or per-path | Per-request, per-field, any attribute |
| **Code changes** | None — sidecar handles it | None — sidecar or external service |
| **Flexibility** | Standard OAuth2 patterns | Arbitrary business rules (time-based, multi-attribute, etc.) |
| **Best for** | Standard S2S scope checking | Complex authorization logic beyond simple scopes |

Use Istio's built-in JWT + AuthorizationPolicy for standard scope checks. Add OPA when you need complex rules that go beyond what JWT claims can express.

### Observability

- **Jaeger** — distributed tracing. Shows the full journey of a request across services, so you can see where time is spent and where failures happen.
- **Prometheus** — metrics collection. Scrapes latency, error rate, and throughput data from Envoy sidecars automatically.
- **Kiali** — visual dashboard for the mesh. Reads from Prometheus and Jaeger to show a live topology map with traffic flow, health status, and mTLS status.

### Platform

- **cert-manager** — automates TLS certificate creation and renewal. Locally uses self-signed certificates; in production would use Let's Encrypt or a private CA.
- **OPA/Gatekeeper** — policy engine that enforces rules on what can be deployed (e.g., "all pods must have resource limits", "no images from untrusted registries").
- **external-secrets** — syncs secrets from an external vault (HashiCorp Vault, AWS Secrets Manager) into Kubernetes Secrets. Locally uses a Vault dev server.

### Secrets Management Patterns

There are two common approaches for delivering secrets from Vault to pods in production.

#### Pattern 1: External Secrets Operator (what we use)

The external-secrets operator syncs secrets from Vault into Kubernetes Secrets. Pods reference the K8s Secret by name.

```
Vault                          external-secrets            K8s Secret              Pod
secret/data/apollo-router  →   ExternalSecret CRD    →    apollo-credentials  →   env: APOLLO_KEY
  APOLLO_KEY: "xxx"            (refreshInterval: 1m)       APOLLO_KEY: "xxx"       valueFrom:
  APOLLO_GRAPH_REF: "yyy"                                  APOLLO_GRAPH_REF: "yyy"   secretKeyRef:
                                                                                       name: apollo-credentials
```

How teams coordinate:
- The team that stores secrets in Vault also creates the ExternalSecret CRD (usually in the same repo)
- The ExternalSecret defines the K8s Secret name it will create (e.g. `apollo-credentials`)
- Consuming services reference that name in their Helm values — never the actual secret value
- Naming conventions make it discoverable: `{service}-credentials`, `{service}-db-secrets`

```yaml
# Helm values — only references the secret name, never the value
env:
  - name: APOLLO_KEY
    valueFrom:
      secretKeyRef:
        name: apollo-credentials    # ← created by ExternalSecret
        key: APOLLO_KEY
```

**Pros:** Cloud-agnostic (works with AWS SM, GCP SM, Azure KV, Vault), simple to set up, familiar K8s Secret model.
**Cons:** Secret exists at rest in etcd as a K8s Secret object.

#### Pattern 2: Vault Agent Injector (sidecar injection)

A mutating webhook injects a Vault Agent sidecar into each pod. The sidecar fetches secrets directly from Vault at pod startup and writes them to a shared in-memory volume. **No Kubernetes Secret is ever created** — the secret never touches etcd.

```
Vault                          Vault Agent Sidecar         Shared Volume           App Container
secret/data/apollo-router  →   (injected into pod)    →   /vault/secrets/apollo →  reads file at startup
  APOLLO_KEY: "xxx"            fetches at pod creation     APOLLO_KEY="xxx"
  APOLLO_GRAPH_REF: "yyy"     refreshes periodically      APOLLO_GRAPH_REF="yyy"
```

All configuration is done via pod annotations — no changes to the app code:

```yaml
# Pod annotations — that's all you need
metadata:
  annotations:
    vault.hashicorp.com/agent-inject: "true"
    vault.hashicorp.com/role: "apollo-router"
    vault.hashicorp.com/agent-inject-secret-apollo: "secret/data/apollo-router"
```

The app reads secrets from `/vault/secrets/apollo` instead of environment variables.

**Pros:** More secure — secrets never stored in etcd, injected only at runtime. Vault-native access policies.
**Cons:** Tightly coupled to Vault (can't swap backends). Adds a sidecar to every pod. App must read from files.

#### When to use which

| | Pattern 1: External Secrets | Pattern 2: Vault Agent Injector |
|---|---|---|
| **Secret storage** | In etcd as K8s Secret | Only in pod memory/volume |
| **Backend flexibility** | Any (Vault, AWS SM, GCP SM, Azure KV) | Vault only |
| **Pod overhead** | None | Extra sidecar per pod |
| **App reads from** | Environment variables or volume mounts | Files in `/vault/secrets/` |
| **Best for** | Multi-cloud, teams using multiple secret backends | Vault-heavy orgs with strict security requirements |

### CI/CD

- **ArgoCD** — GitOps continuous delivery. Watches this Git repo and automatically syncs Kubernetes manifests to the cluster whenever you push changes. The cluster state always matches what's in Git.
- **GitHub Actions** — continuous integration. Runs lint, tests, and builds Docker images on every push. Updates image tags in the repo, which triggers ArgoCD to deploy.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/)
- [Kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/docs/intro/install/)
- JDK 17+ (for Catalog service)
- Go 1.26+ (for Shipping service)
- [Rover CLI](https://www.apollographql.com/docs/rover/getting-started/) (for composing the supergraph schema)

## Layer 1 — Cluster + Core Services

### Step 1: Create the cluster

The setup script does the following (idempotent — safe to run multiple times):
1. Starts a local Docker registry on `localhost:5000`
2. Creates a Kind cluster (1 control-plane + 2 workers)
3. Connects the registry to the Kind Docker network
4. Configures containerd on each node to pull from the local registry
5. Labels the control-plane node for ingress scheduling
6. Registers the registry with the cluster via a ConfigMap

```bash
chmod +x kind/setup.sh
./kind/setup.sh
```

### Step 2: Verify the cluster and registry

```bash
# All nodes should show STATUS: Ready
kubectl get nodes

# Registry container should be running on port 5000
docker ps | grep kind-registry

# Test the full registry pipeline (push an image, run it in the cluster)
docker pull nginx:alpine
docker tag nginx:alpine localhost:5000/nginx:test
docker push localhost:5000/nginx:test
kubectl run test --image=localhost:5000/nginx:test
kubectl get pod test          # should show Running
kubectl delete pod test       # clean up
```

### Step 3: Build and push the Catalog service (Kotlin/Spring Boot)

```bash
# Build the Docker image (multi-stage: Gradle build → JRE runtime)
docker build -t localhost:5000/catalog:latest services/catalog/

# Push to local registry
docker push localhost:5000/catalog:latest

# Test locally (optional)
docker run --rm -p 4001:4001 localhost:5000/catalog:latest
curl -X POST http://localhost:4001/graphql \
  -H 'Content-Type: application/json' \
  -d '{"query":"{ products { id name price } }"}'
```

### Step 4: Build and push the Shipping service (Go)

```bash
# Build the Docker image (multi-stage: Go build → Alpine runtime)
docker build -t localhost:5000/shipping:latest services/shipping/

# Push to local registry
docker push localhost:5000/shipping:latest

# Test locally (optional)
docker run --rm -p 4002:4002 localhost:5000/shipping:latest
curl -X POST http://localhost:4002/query \
  -H 'Content-Type: application/json' \
  -d '{"query":"{ shipping(productId: \"1\") { id productId estimatedDays carrier } }"}'
```

### Step 5: Deploy services to the cluster with Helm

Each service uses the shared Helm chart (`charts/service/`) with a per-service values file from `charts/releases/`.

```bash
# Lint the chart first
helm lint charts/service

# Deploy both services
helm install catalog charts/service -f charts/releases/catalog.yaml
helm install shipping charts/service -f charts/releases/shipping.yaml

# Verify pods are running
kubectl get pods
```

### Step 6: Publish subgraph schemas to Apollo GraphOS

Apollo Router uses managed federation — it pulls the composed supergraph from Apollo GraphOS automatically. Each subgraph's schema must be published to GraphOS.

```bash
# Authenticate Rover with your Apollo key
rover config auth

# Publish Catalog schema
rover subgraph publish <YOUR_GRAPH_REF> \
  --name catalog \
  --schema services/catalog/src/main/resources/schema/schema.graphqls \
  --routing-url http://catalog:4001/graphql

# Publish Shipping schema
rover subgraph publish <YOUR_GRAPH_REF> \
  --name shipping \
  --schema services/shipping/internal/graph/schema.graphqls \
  --routing-url http://shipping:4002/query
```

In production, this is automated by the CI pipeline on every merge.

### Step 7: Build, push, and deploy Apollo Router

```bash
# Build and push
docker build -t localhost:5000/apollo-router:latest apollo/
docker push localhost:5000/apollo-router:latest

# Update charts/releases/apollo.yaml with your APOLLO_KEY and APOLLO_GRAPH_REF

# Deploy
helm install apollo-router charts/service -f charts/releases/apollo.yaml

# Verify all three pods are running
kubectl get pods
```

### Step 8: Test the federated GraphQL endpoint

```bash
kubectl port-forward svc/apollo-router 4000:4000
```

In another terminal — this single query hits both subgraphs through the Router:

```bash
curl -X POST http://localhost:4000 \
  -H 'Content-Type: application/json' \
  -d '{"query":"{ products { id name price } shipping(productId: \"1\") { carrier estimatedDays } }"}'
```

## Layer 2 — API Gateway (Kong)

Kong is the single entry point for all external traffic (north-south). It handles authentication,
rate limiting, and routes requests to the Apollo Router inside the cluster.

```
Browser → localhost:80 → Kind port mapping → Kong Gateway → Apollo Router → Subgraphs
```

### Step 1: Install Kong via Helm

```bash
helm repo add kong https://charts.konghq.com
helm repo update
helm install kong kong/ingress -n kong --create-namespace -f kong/values.yaml
```

Wait for both pods to be ready:

```bash
kubectl get pods -n kong --watch
```

### Step 2: Patch Kong for Kind hostPort

The Kong Helm chart doesn't support hostPort natively. This patch binds Kong's proxy
to ports 80/443 on the control-plane node so `localhost:80` reaches it.

This is only needed for local Kind clusters — in production, a cloud LoadBalancer handles this.

```bash
chmod +x kong/patch-hostport.sh
./kong/patch-hostport.sh
```

Verify Kong is reachable:

```bash
# Should return a Kong 404 (no routes configured yet)
curl -i http://localhost
```

### Step 3: Deploy Apollo Router with Ingress

The Apollo Router's Helm values file includes an Ingress resource that tells Kong
to route all traffic to the Router. This was already configured in `charts/releases/apollo.yaml`.

```bash
helm upgrade apollo-router charts/service -f charts/releases/apollo.yaml
```

### Step 4: Apply Kong plugins

Rate limiting — 60 requests per minute per client:

```bash
kubectl apply -f kong/plugins/rate-limit.yaml
```

### Step 5: Test the full traffic flow

```bash
# This goes: localhost → Kong → Apollo Router → Catalog + Shipping
curl -i -X POST http://localhost/graphql \
  -H 'Content-Type: application/json' \
  -d '{"query":"{ products { id name price } shipping(productId: \"1\") { carrier estimatedDays } }"}'
```

Check for `X-RateLimit-Remaining` header in the response to confirm rate limiting is active.

## Layer 3 — Service Mesh (Istio)

Istio adds mTLS encryption, circuit breaking, and observability between services
without any code changes. Envoy sidecars are injected into every pod transparently.

### Step 1: Install Istio

```bash
brew install istioctl
istioctl install --set profile=demo -y
kubectl get pods -n istio-system
```

Wait for `istiod`, `istio-ingressgateway`, and `istio-egressgateway` to be Running.

### Step 2: Enable sidecar injection

Label the default namespace so Istio automatically injects Envoy sidecars into every new pod:

```bash
kubectl label namespace default istio-injection=enabled
```

### Step 3: Restart services to pick up sidecars

```bash
kubectl rollout restart deployment catalog shipping apollo-router
kubectl get pods --watch
```

Each pod should now show `2/2` Ready (app container + Envoy sidecar).

### Step 4: Install Kiali and Prometheus

```bash
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.26/samples/addons/prometheus.yaml
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.26/samples/addons/kiali.yaml
kubectl get pods -n istio-system --watch
```

Open the Kiali dashboard:

```bash
istioctl dashboard kiali
```

### Step 5: Apply circuit breaker on Shipping

```bash
kubectl apply -f istio/circuit-breaker.yaml
kubectl get destinationrule
```

### Step 6: Verify the mesh

Send traffic and check Kiali's Traffic Graph (select `default` namespace):

```bash
for i in (seq 1 30)
  curl -s -X POST http://localhost/ -H 'Content-Type: application/json' -d '{"query":"{ products { id name } }"}'
  sleep 0.5
end
```

You should see the full topology: Kong → Apollo Router → Catalog + Shipping.

## Layer 4 — Observability

Distributed tracing with Jaeger, metrics with Prometheus, and mesh visualization with Kiali.
Prometheus and Kiali were already installed in Layer 3.

### Step 1: Install Jaeger

```bash
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.26/samples/addons/jaeger.yaml
kubectl get pods -n istio-system --watch
```

### Step 2: Enable tracing across the mesh

By default, Istio knows about Jaeger but doesn't send traces. This telemetry resource activates it
with 100% sampling (in production, use 1-10%):

```bash
kubectl apply -f istio/telemetry.yaml
```

### Step 3: View traces

Open Jaeger:

```bash
istioctl dashboard jaeger
```

Generate traffic, then in Jaeger:
1. Select a service from the dropdown (e.g. `apollo-router`)
2. Click **Find Traces**
3. Click a trace to see the full request journey across services

### Observability dashboards

| Tool | Command | What it shows |
|------|---------|---------------|
| Kiali | `istioctl dashboard kiali` | Mesh topology, traffic flow, mTLS status |
| Jaeger | `istioctl dashboard jaeger` | Distributed traces across services |
| Prometheus | `istioctl dashboard prometheus` | Raw metrics (latency, error rate, throughput) |

## Layer 5 — Platform Services

Production-hardening tools: TLS certificates, deployment policies, and secrets management.

### Step 1: cert-manager (TLS certificates)

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager -n cert-manager --create-namespace --set crds.enabled=true
kubectl get pods -n cert-manager --watch
```

Create a self-signed issuer for local development:

```bash
kubectl apply -f platform/cert-manager/cluster-issuer.yaml
kubectl get clusterissuer   # should show Ready: True
```

### Step 2: OPA/Gatekeeper (deployment policies)

```bash
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts
helm repo update
helm install gatekeeper gatekeeper/gatekeeper -n gatekeeper-system --create-namespace
kubectl get pods -n gatekeeper-system --watch
```

Apply sample policy (require resource limits on all pods):

```bash
kubectl apply -f platform/opa/require-resource-limits-template.yaml
kubectl apply -f platform/opa/require-resource-limits.yaml
kubectl get constrainttemplate
kubectl get k8srequireresourcelimits
```

### Step 3: external-secrets + Vault (secrets management)

Install Vault dev server:

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
helm install vault hashicorp/vault -n vault --create-namespace --set "server.dev.enabled=true"
kubectl get pods -n vault --watch
```

Store secrets in Vault and create the auth token:

```bash
kubectl create secret generic vault-token -n vault --from-literal=token=root
kubectl exec -n vault vault-0 -- vault kv put secret/apollo-router \
  APOLLO_KEY="<your-apollo-key>" \
  APOLLO_GRAPH_REF="<your-graph-ref>"
```

Install external-secrets operator:

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update
helm install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace
kubectl get pods -n external-secrets --watch
```

Connect to Vault and sync the Apollo credentials:

```bash
kubectl apply -f platform/external-secrets/secret-store.yaml
kubectl apply -f platform/external-secrets/apollo-external-secret.yaml
kubectl get clustersecretstore vault-backend   # should show Ready: True
kubectl get externalsecret                      # should show SecretSynced
kubectl get secret apollo-credentials           # Kubernetes Secret created from Vault
```

## Layer 6 — GitOps (ArgoCD)

ArgoCD watches this git repo and automatically syncs Kubernetes resources to the cluster.
Push changes to `main` — ArgoCD detects drift and deploys automatically. No manual `helm install/upgrade` needed.

### Step 1: Install ArgoCD

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --server-side --force-conflicts
kubectl get pods -n argocd --watch
```

### Step 2: Access the ArgoCD UI

```bash
# Get the initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Port-forward the UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Open **https://localhost:8080** — login with `admin` and the password above.

### Step 3: Install ArgoCD CLI and login

```bash
brew install argocd
argocd login localhost:8080 --insecure --username admin --password $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
```

### Step 4: Remove existing manual Helm releases

ArgoCD will take ownership of these services. Remove the manually installed releases first to avoid conflicts:

```bash
helm uninstall catalog
helm uninstall shipping
helm uninstall apollo-router
```

### Step 5: Apply the root app

The app-of-apps pattern: one root Application watches the `argocd/` directory and automatically creates all child Applications.

```
root-app (watches argocd/ directory)
  ├── catalog     → charts/service + charts/releases/catalog.yaml
  ├── shipping    → charts/service + charts/releases/shipping.yaml
  └── apollo-router → charts/service + charts/releases/apollo.yaml
```

```bash
kubectl apply -f argocd/root-app.yaml
argocd app sync root-app
```

### Step 6: Verify

All apps should show **Synced** and **Healthy** in the ArgoCD UI:

```bash
argocd app list
```

### Deploying changes with ArgoCD

From now on, to deploy changes:

1. Edit code or config locally
2. Build and push new image to `localhost:5000`
3. Update the image tag in `charts/releases/<service>.yaml`
4. `git commit && git push`
5. ArgoCD detects the change and syncs automatically

No more `helm install/upgrade` — git is the source of truth.

## Teardown

Removes the cluster and all workloads. Nothing persists after this.

```bash
kind delete cluster --name service-mesh-platform
docker rm -f kind-registry
```

## Project Structure

```
service-mesh-platform/
  kind/                     # Cluster config and setup script
  services/
    catalog/                # Kotlin/Spring Boot GraphQL subgraph
    shipping/               # Go GraphQL subgraph
  apollo/                   # Apollo Router (supergraph federation)
  charts/
    service/                # Shared Helm chart for all services
    releases/               # Per-service Helm values overrides
  istio/                    # Istio mesh config (VirtualService, mTLS, etc.)
  kong/                     # Kong gateway plugins (JWT, rate limiting)
  observability/            # Jaeger, Prometheus, Kiali
  platform/                 # cert-manager, OPA, external-secrets
  argocd/                   # ArgoCD Application CRDs
  .github/workflows/        # CI pipelines
```

See [PLAN.md](PLAN.md) for the full implementation plan and layer breakdown.
