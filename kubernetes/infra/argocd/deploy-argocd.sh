#!/usr/bin/env bash
set -euo pipefail

echo "[+] Checking prerequisites (kubectl, helm)"
command -v kubectl >/dev/null 2>&1 || { echo "kubectl not found"; exit 1; }
command -v helm >/dev/null 2>&1 || { echo "helm not found"; exit 1; }

K8S_DIR="$(cd "$(dirname "$0")/../../.." && pwd)/kubernetes"

echo "[+] Creating namespace 'argocd'"
kubectl apply -f "$K8S_DIR/infra/argocd/namespace.yaml"

echo "[+] Adding Argo Helm repo"
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update

echo "[+] Installing/Upgrading Argo CD via Helm"
helm upgrade --install argocd argo/argo-cd \
  -n argocd \
  -f "$K8S_DIR/infra/argocd/values.yaml"

echo "[+] Waiting for argocd-server rollout"
kubectl -n argocd rollout status deploy/argocd-server --timeout=5m

echo "[+] Applying Argo CD Applications (bootstrap)"
kubectl apply -k "$K8S_DIR/infra/argocd"

echo "[+] Argo CD server service:" 
kubectl -n argocd get svc argocd-server -o wide || true

echo "[+] Initial admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo

cat <<INFO

Next steps:
- If the repo is private, add a read-only deploy key and configure repo credentials in Argo CD.
- Example secret template: kubernetes/infra/argocd/argocd-repo-ssh-cred.example.yaml (do not commit real keys).
- Access UI via LoadBalancer IP from the service above or port-forward:
  kubectl -n argocd port-forward svc/argocd-server 8080:80
  URL: http://localhost:8080  User: admin  Password: (printed above)
INFO

echo "[+] Done."

