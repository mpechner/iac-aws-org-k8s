#!/bin/bash
# Setup kubectl configuration for RKE2 cluster
# Usage: ./setup-k9s.sh <server-ip-address>

set -e

if [ -z "$1" ]; then
  echo "Error: Server IP address required"
  echo "Usage: $0 <server-ip-address>"
  echo "Example: $0 10.8.91.172"
  exit 1
fi

SERVER_IP=$1
SSH_KEY="${HOME}/.ssh/rke-key"
KUBECONFIG_FILE="${HOME}/.kube/dev-rke2.yaml"
CONTEXT_NAME="dev-rke2"

echo "Setting up kubectl configuration for RKE2 cluster..."
echo "Server IP: ${SERVER_IP}"

# Clean up any old dev-rke2 context and cluster from previous deployments
echo "Cleaning up old configurations..."
kubectl config delete-context ${CONTEXT_NAME} 2>/dev/null || true
kubectl config delete-cluster default 2>/dev/null || true
kubectl config delete-user default 2>/dev/null || true

# Check if SSH key exists
if [ ! -f "${SSH_KEY}" ]; then
  echo "Error: SSH key not found at ${SSH_KEY}"
  echo "Please copy the rke-ssh private key from AWS Secrets Manager first"
  exit 1
fi

# Copy kubeconfig from server
echo "Copying kubeconfig from server..."
scp -i "${SSH_KEY}" ubuntu@${SERVER_IP}:/etc/rancher/rke2/rke2.yaml "${KUBECONFIG_FILE}"

# Update server URL
echo "Updating server URL..."
sed -i '' "s|server: https://127.0.0.1:6443|server: https://${SERVER_IP}:6443|" "${KUBECONFIG_FILE}"

# Rename context
echo "Renaming context to ${CONTEXT_NAME}..."
kubectl --kubeconfig "${KUBECONFIG_FILE}" config rename-context default "${CONTEXT_NAME}" 2>/dev/null || \
kubectl --kubeconfig "${KUBECONFIG_FILE}" config rename-context rke2 "${CONTEXT_NAME}" 2>/dev/null || \
echo "Context already named ${CONTEXT_NAME}"

# Merge with existing kubeconfig
echo "Merging with existing kubeconfig..."
KUBECONFIG="${HOME}/.kube/config:${KUBECONFIG_FILE}" kubectl config view --flatten > "${HOME}/.kube/merged"
mv "${HOME}/.kube/merged" "${HOME}/.kube/config"

# Set permissions
chmod 600 "${HOME}/.kube/config"

echo ""
echo "✓ Kubectl configuration complete!"
echo ""
echo "You can now use:"
echo "  kubectl config use-context ${CONTEXT_NAME}"
echo "  kubectl get nodes"
echo "  k9s"
echo ""
