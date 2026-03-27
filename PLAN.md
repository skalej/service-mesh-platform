# Service Mesh Platform — Implementation Plan

## Architecture Overview
Kong API Gateway + Istio service mesh + Apollo GraphQL federation
running on a local Kind cluster with ArgoCD for GitOps CD.

## Tech Stack
| Component          | Tool                        |
|--------------------|-----------------------------|
| Local K8s          | Kind                        |
| API Gateway        | Kong (Helm)                 |
| Service Mesh       | Istio + Envoy sidecars      |
| GraphQL Federation | Apollo Router               |
| Subgraph: Catalog  | Kotlin / Spring Boot        |
| Subgraph: Shipping | Go (net/http + gqlgen)       |
| Database           | PostgreSQL (Helm, local)    |
| Observability      | Jaeger, Prometheus, Kiali   |
| Policy Engine      | OPA / Gatekeeper            |
| Secrets            | external-secrets (+ Vault dev) |
| Certificates       | cert-manager (self-signed)  |
| GitOps / CD        | ArgoCD                      |
| CI                 | GitHub Actions              |

## Repo Structure
```
service-mesh-platform/
  services/
    catalog/                # Kotlin/Spring Boot subgraph
      build.gradle.kts
      src/
      Dockerfile
    shipping/               # Go subgraph
      go.mod
      cmd/
      Dockerfile
  apollo/                   # Apollo Router config + Dockerfile
  charts/
    service/                # Shared Helm chart for all our services
      Chart.yaml
      values.yaml           # Defaults (replicas, port, probes, resources)
      templates/
        deployment.yaml
        service.yaml
        configmap.yaml
        hpa.yaml
        serviceaccount.yaml
        _helpers.tpl
    releases/               # Per-service value overrides
      catalog.yaml          # image, env, port, replicas for Catalog
      shipping.yaml         # image, env, port, replicas for Shipping
      apollo.yaml           # image, env, port for Apollo Router
      postgres.yaml         # Bitnami chart values override
  istio/                    # VirtualService, DestinationRule, Gateway, ServiceEntry
  kong/                     # Kong plugin configs, rate-limit, JWT
  observability/            # Jaeger, Prometheus, Kiali manifests/values
  platform/
    cert-manager/
    opa/
    external-secrets/
  argocd/                   # ArgoCD Application CRDs (app-of-apps)
  kind/                     # Kind cluster config + setup scripts
  .github/
    workflows/              # CI pipeline
  PLAN.md
```

## Helm Strategy
- **One shared `charts/service/` chart** — standard template for all our services
  (Deployment, Service, ConfigMap, HPA, ServiceAccount)
- **Per-service values files** in `charts/releases/` override image, env, ports, resources
- **Third-party charts** (Kong, PostgreSQL, ArgoCD, Istio addons) installed via Helm
  with values files in their respective directories
- ArgoCD deploys each service as a separate Helm release using the shared chart +
  the matching values file from `charts/releases/`

## Implementation Layers

### Layer 1 — Cluster + Core Services ✓
- [x] Kind cluster config (expose ports 80/443, local Docker registry)
- [x] Cluster creation + registry setup script
- [x] Catalog service: Kotlin/Spring Boot GraphQL subgraph + Dockerfile
- [x] Shipping service: Go GraphQL subgraph (gqlgen) + Dockerfile
- [ ] PostgreSQL: deploy via Bitnami Helm chart
- [x] Apollo Router: managed federation via Apollo GraphOS
- [x] Shared Helm chart (`charts/service/`) with standard templates
- [x] Per-service values files in `charts/releases/` (catalog, shipping, apollo)
- [x] Verify: `kubectl port-forward` to Apollo, query both subgraphs

### Layer 2 — API Gateway (Kong) ✓
- [x] Install Kong ingress controller via Helm
- [x] Ingress/HTTPRoute rules: external traffic -> Kong -> Apollo
- [ ] JWT authentication plugin (deferred — will add when needed)
- [x] Rate limiting plugin
- [x] Verify: curl through Kong to Apollo

### Layer 3 — Service Mesh (Istio) ✓
- [x] Install Istio (demo profile via istioctl)
- [x] Label namespaces for automatic sidecar injection
- [x] Re-deploy services to pick up Envoy sidecars
- [ ] PeerAuthentication: enforce STRICT mTLS mesh-wide (deferred — Kong needs sidecar first)
- [x] DestinationRule: circuit breaker on Shipping subgraph
- [ ] Egress Gateway + ServiceEntry for external DB / SaaS (deferred — no external DB yet)
- [x] Verify: Kiali shows mesh topology

### Layer 4 — Observability ✓
- [x] Jaeger: distributed tracing (Istio addon)
- [x] Prometheus: metrics scraping from Envoy sidecars
- [x] Kiali: mesh visualization (reads Prometheus + Jaeger)
- [x] Telemetry resource: enabled 100% trace sampling mesh-wide
- [x] Verify: end-to-end trace visible in Jaeger UI

### Layer 5 — Platform Services ✓
- [x] cert-manager: install + self-signed ClusterIssuer
- [x] OPA/Gatekeeper: install + resource limits ConstraintTemplate + Constraint (warn mode)
- [x] external-secrets: install + local Vault dev server + ClusterSecretStore + Apollo credentials ExternalSecret
- [x] Verify: certificates issued, policies enforced, secrets synced from Vault

### Layer 6 — GitOps (ArgoCD)
- [ ] Install ArgoCD in-cluster via Helm
- [ ] ArgoCD Application CRDs pointing at this repo's k8s/ directory
- [ ] App-of-apps pattern: one root Application manages all others
- [ ] Verify: ArgoCD UI shows synced apps, auto-syncs on git push

### Layer 7 — CI Pipeline (GitHub Actions)
- [ ] Workflow: lint + test for Catalog (Kotlin)
- [ ] Workflow: lint + test for Shipping (Go)
- [ ] Workflow: build + push Docker images to registry
- [ ] Workflow: update image tags in k8s manifests (triggers ArgoCD sync)
- [ ] Verify: push triggers full CI -> CD loop

## Cluster Lifecycle
```bash
# Create
./kind/setup.sh

# Destroy (removes everything)
kind delete cluster --name service-mesh-platform
```

## Key Decisions
1. **Kind over k3d/minikube** — user already has it, familiar
2. **ArgoCD over Flux** — user already has experience with it
3. **Shared Helm chart for our services** — one chart, per-service values overrides
4. **Helm for third-party installs** — Kong, PostgreSQL, ArgoCD, Istio addons
5. **Local Docker registry** — avoids pushing to Docker Hub during dev
6. **Incremental layers** — each layer is independently verifiable before moving on
