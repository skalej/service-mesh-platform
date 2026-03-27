#!/bin/sh
# ---------------------------------------------------------------------------
# Patches the Kong gateway deployment to use hostPort on ports 80 and 443.
#
# Why: The Kong Helm chart does not support hostPort natively.
# Kind requires hostPort to route localhost:80/443 from your Mac
# to the Kong proxy pod on the control-plane node.
#
# This is only needed for local Kind clusters.
# In production, a cloud LoadBalancer handles external access instead.
# ---------------------------------------------------------------------------

set -e

echo "Patching Kong gateway to use hostPort 80 and 443..."
kubectl patch deployment kong-gateway -n kong --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/ports", "value": [
    {"name": "admin-tls", "containerPort": 8444, "protocol": "TCP"},
    {"name": "proxy",     "containerPort": 8000, "protocol": "TCP", "hostPort": 80},
    {"name": "proxy-tls", "containerPort": 8443, "protocol": "TCP", "hostPort": 443},
    {"name": "status",    "containerPort": 8100, "protocol": "TCP"}
  ]}
]'

echo "Waiting for rollout..."
kubectl rollout status deployment kong-gateway -n kong --timeout=60s

echo "Done! Kong proxy is now reachable at localhost:80 and localhost:443."
