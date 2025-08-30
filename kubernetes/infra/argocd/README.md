Argo CD

Install
- Add Helm repo: `helm repo add argo https://argoproj.github.io/argo-helm && helm repo update`
- Namespace: `kubectl apply -f kubernetes/infra/argocd/namespace.yaml`
- Install via Helm:
  - `helm upgrade --install argocd argo/argo-cd -n argocd -f kubernetes/infra/argocd/values.yaml`
- Get initial admin password: `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo`

Access
- Service type is LoadBalancer (MetalLB). Optionally set a static IP in values.
- Or use `kubectl port-forward svc/argocd-server -n argocd 8080:80` and open http://localhost:8080

Connect Repo (SSH)
- Create a read-only deploy key on GitHub and add it to the repo.
- Apply example with your private key: `kubectl apply -f kubernetes/infra/argocd/argocd-repo-ssh-cred.example.yaml`
- Alternatively add the repo via the Argo CD UI/CLI.

Sync Apps
- Apply the Argo CD Application objects: `kubectl apply -k kubernetes/infra/argocd`
- The `homelab-kubernetes` app points to `path: kubernetes` and will sync the top-level Kustomization.

Notes
- values.yaml enables ApplicationSet and exposes the server as a LoadBalancer.
- Do not commit real SSH keys; use the example file locally or configure via the UI.
