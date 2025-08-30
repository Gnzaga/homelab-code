#!/bin/bash
# upgrade_jupyter.sh - Script to upgrade or install JupyterHub via Helm
#
# This script will run the following Helm command:
# helm upgrade --install jupyter jupyterhub/jupyterhub --namespace jupyterhub --values config.yaml --version 4.1.0 --debug
#
# Usage:
#   ./upgrade_jupyter.sh
#
# Make sure you have Helm installed and that your KUBECONFIG is correctly set up.
# You might also need to run: chmod +x upgrade_jupyter.sh

set -e  # Exit immediately if a command exits with a non-zero status

echo "Upgrading/installing JupyterHub using Helm..."
helm upgrade --install jupyter jupyterhub/jupyterhub \
  --namespace jupyterhub \
  --values config.yaml \
  --version 4.1.0 \
  --debug

echo "JupyterHub upgrade/install completed."

