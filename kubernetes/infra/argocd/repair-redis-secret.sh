#!/usr/bin/env bash
set -euo pipefail

ns=argocd
echo "[+] Ensuring Redis secret exists (empty password for disabled auth)"
kubectl -n "$ns" apply -f - <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: argocd-redis
  namespace: argocd
type: Opaque
stringData:
  redis-password: ""
EOF

echo "[+] Restarting Argo CD components to pick up secret"
kubectl -n "$ns" rollout restart deploy/argocd-redis || true
kubectl -n "$ns" rollout restart deploy/argocd-repo-server || true
kubectl -n "$ns" rollout restart deploy/argocd-server || true
kubectl -n "$ns" rollout restart statefulset/argocd-application-controller || true

echo "[+] Waiting for argocd-server rollout"
kubectl -n "$ns" rollout status deploy/argocd-server --timeout=5m

echo "[+] Pods:" && kubectl -n "$ns" get pods -o wide
echo "[+] Endpoints:" && kubectl -n "$ns" get ep argocd-server

ip=$(kubectl -n "$ns" get svc argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
if [[ -n "${ip:-}" ]]; then
  echo "[+] Testing http://$ip/"
  curl -v --max-time 5 "http://$ip/" >/dev/null 2>&1 || true
  echo "[i] If not immediately reachable, give MetalLB ~10s to converge and retry."
else
  echo "[!] No External IP on argocd-server service yet."
fi

echo "[+] Initial admin password:"
kubectl -n "$ns" get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo

echo "[+] Done."

