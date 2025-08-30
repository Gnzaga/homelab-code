Stacks Directory

This directory is generated from Portainer exports to help track and deploy container stacks in a source-controlled, human-friendly structure.

Layout

- docker/<name>[/--<endpoint>[-alt]>]/
  - docker-compose.yml: Compose file with a header comment describing the stack and services.
  - .env (optional): Variables exported from Portainer’s stack.env with a warning header.
- k8s/<name>[/--<endpoint>[-alt]>]/
  - k8s-deployment.yml: Kubernetes manifest with a header comment.
- index.csv: Index mapping Portainer stack IDs to destination paths.

How To Use

- Review each stack’s header comments for a quick summary of services/images.
- Update .env files to rotate sensitive values before sharing.
- Deploy docker stacks with: `docker compose up -d` inside each stack directory.
- Apply k8s manifests with: `kubectl apply -f .` inside the workload directory.

Regenerating

- The script `scripts/organize-portainer.ps1` parses `portainer_dump/export-*.json` and mirrors files from `portainer_dump/compose/<id>/` into this structure with added comments.
  - Safe to re-run; it overwrites the generated files with updated headers from the latest export.
  - By default, stacks are grouped by name (no numeric suffixes). If multiple stacks share the same name, the directory is suffixed with `--<endpoint>`; if there’s still a collision, `-alt` is appended.

Notes

- Original Portainer dump is preserved in `portainer_dump/` and should remain unchanged.
- Endpoint names are taken from the export; unknown endpoints are grouped as `endpoint-<id>`.
