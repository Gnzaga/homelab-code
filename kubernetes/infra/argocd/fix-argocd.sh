#!/usr/bin/env bash
set -euo pipefail

ns=argocd
K8S_DIR="$(cd "$(dirname "$0")/../../.." && pwd)/kubernetes"

echo "[+] Ensuring namespace exists"
kubectl get ns "$ns" >/dev/null 2>&1 || kubectl create ns "$ns"

echo "[+] Helm upgrade Argo CD with safe defaults (no Dex, Redis w/o auth)"
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update >/dev/null

helm upgrade --install argocd argo/argo-cd \
  -n "$ns" \
  --reuse-values \
  --set dex.enabled=false \
  --set redis.enabled=true \
  --set redis.auth.enabled=false \
  --set server.service.type=LoadBalancer \
  --set configs.params.server.insecure=true

echo "[+] Waiting for argocd-server rollout"
kubectl -n "$ns" rollout status deploy/argocd-server --timeout=5m

echo "[+] Current pods"
kubectl -n "$ns" get pods -o wide

echo "[+] Service details"
kubectl -n "$ns" get svc argocd-server -o wide

extip=$(kubectl -n "$ns" get svc argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
if [[ -n "${extip:-}" ]]; then
  echo "[+] External IP: $extip — testing HTTP"
  set +e
  curl -v --max-time 5 "http://$extip/" >/dev/null 2>&1
  rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    echo "[!] Could not reach http://$extip yet. MetalLB may need a moment to program ARP/NDP. Retrying in 10s..."
    sleep 10
    curl -v --max-time 5 "http://$extip/" || true
  else
    echo "[+] Reached Argo CD at http://$extip"
  fi
else
  echo "[!] No External IP assigned yet. Wait a few seconds and re-check: kubectl -n $ns get svc argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].ip}'" 
fi

echo "[+] Initial admin password:"
kubectl -n "$ns" get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo

echo "[+] Done."

