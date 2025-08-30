Kubernetes Manifests and Helm Values

Structure:
- apps/: Applications deployed to the cluster (Deployments, Services, Helm values, scripts).
- infra/: Cluster infrastructure components (e.g., MetalLB, GPU configs).

Usage:
- Apply all included manifests: `kubectl apply -k .`
- Or apply a single app/infra: `kubectl apply -k apps/jellyfin` (example)

Notes:
- Some folders contain Helm values (e.g., `apps/jupyterhub/config.yaml`, `infra/gpu/gpu-ops-vals.yaml`) and are not included in Kustomize builds.
- MetalLB files here include config and monitoring resources; install MetalLB core components separately if needed.

Helm-Managed Components
- JupyterHub (Helm):
  - Add repo: `helm repo add jupyterhub https://jupyterhub.github.io/helm-chart/ && helm repo update`
  - Namespace: `kubectl create namespace jupyterhub --dry-run=client -o yaml | kubectl apply -f -`
  - Install/upgrade:
    - `helm upgrade --install jupyter jupyterhub/jupyterhub -n jupyterhub -f kubernetes/apps/jupyterhub/config.yaml --version 4.1.0`
  - Script (optional): `kubernetes/apps/jupyterhub/upgrade.sh`
  - Security: move any client secrets out of git; prefer a Kubernetes Secret and reference it via values. Example: `apps/jupyterhub/jupyterhub-oauth-secret.example.yaml`.

- NVIDIA GPU Operator (Helm):
  - Add repo: `helm repo add nvidia https://nvidia.github.io/gpu-operator && helm repo update`
  - Namespace: `kubectl create namespace gpu-operator --dry-run=client -o yaml | kubectl apply -f -`
  - Install/upgrade:
    - `helm upgrade --install gpu-operator nvidia/gpu-operator -n gpu-operator -f kubernetes/infra/gpu/gpu-ops-vals.yaml`
  - Ensure GPU nodes are labeled/selectable per values (e.g., `compute-type=gpu`).
