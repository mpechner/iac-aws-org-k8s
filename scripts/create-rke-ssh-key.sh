#!/bin/bash
# Generate RKE SSH key pair and store in AWS Secrets Manager
#
# Secret name:  rke-ssh   (must match RKE-cluster/dev-cluster/ec2/sshkey.tf)
# Local copy:   ~/.ssh/rke-key
#
# Run this BEFORE: RKE-cluster/dev-cluster/ec2 terraform apply
#
# Usage:
#   ./scripts/create-rke-ssh-key.sh
#
# Account ID is read from RKE-cluster/dev-cluster/ec2/terraform.tfvars (aws_account_id = "...").
# Override by setting AWS_ACCOUNT_ID in the environment.
#
# Idempotent: if the secret already exists and is a valid key, the script
# prints a warning and exits without overwriting unless --force is passed.

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
SECRET_NAME="rke-ssh"           # must match sshkey.tf aws_secretsmanager_secret.rke_ssh_keypair.name
REGION="us-west-2"              # must match provider region
SSH_KEY_PATH="$HOME/.ssh/rke-key"
FORCE="${1:-}"
TFVARS="RKE-cluster/dev-cluster/ec2/terraform.tfvars"

# ── Resolve account ID ────────────────────────────────────────────────────────
# Prefer env var override; fall back to aws_account_id in the component's terraform.tfvars.
if [ -z "${AWS_ACCOUNT_ID:-}" ]; then
  if [ -f "$TFVARS" ]; then
    AWS_ACCOUNT_ID=$(grep -E '^\s*aws_account_id\s*=' "$TFVARS" | head -1 | sed 's/.*=\s*"\([^"]*\)".*/\1/')
  fi
fi
if [ -z "${AWS_ACCOUNT_ID:-}" ]; then
  echo "ERROR: Could not determine account ID. Set aws_account_id in $TFVARS or export AWS_ACCOUNT_ID."
  exit 1
fi

# ── Assume terraform-execute role ─────────────────────────────────────────────
echo "Assuming terraform-execute role in account $AWS_ACCOUNT_ID..."
TEMP_CREDS=$(aws sts assume-role \
  --role-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/terraform-execute" \
  --role-session-name "create-rke-ssh-key" \
  --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
  --output text)

export AWS_ACCESS_KEY_ID=$(echo "$TEMP_CREDS"    | awk '{print $1}')
export AWS_SECRET_ACCESS_KEY=$(echo "$TEMP_CREDS" | awk '{print $2}')
export AWS_SESSION_TOKEN=$(echo "$TEMP_CREDS"     | awk '{print $3}')

# ── Idempotency check ─────────────────────────────────────────────────────────
EXISTING=$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_NAME" \
  --region "$REGION" \
  --query SecretString \
  --output text 2>/dev/null || echo "")

if [ -n "$EXISTING" ]; then
  EXISTING_KEY=$(echo "$EXISTING" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('private_key',''))" 2>/dev/null || echo "")
  if echo "$EXISTING_KEY" | grep -q "BEGIN.*PRIVATE KEY"; then
    if [ "$FORCE" = "--force" ]; then
      echo "WARNING: Secret '$SECRET_NAME' already contains a valid key. --force passed — overwriting."
    else
      echo "INFO: Secret '$SECRET_NAME' already contains a valid RSA private key."
      echo "      To overwrite, pass --force:"
      echo "        $0 --force"
      echo ""
      echo "Fetching existing key to $SSH_KEY_PATH..."
      echo "$EXISTING_KEY" > "$SSH_KEY_PATH"
      chmod 600 "$SSH_KEY_PATH"
      echo "✓ Existing key written to $SSH_KEY_PATH (no new key generated)"
      exit 0
    fi
  fi
fi

# ── Generate key pair ─────────────────────────────────────────────────────────
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

echo "Generating 4096-bit RSA key pair..."
ssh-keygen -t rsa -b 4096 -N "" -f "$WORK_DIR/id_rsa" -C "rke-ssh" -q

PRIVATE_KEY=$(cat "$WORK_DIR/id_rsa")
PUBLIC_KEY=$(cat "$WORK_DIR/id_rsa.pub")

# ── Write to Secrets Manager ──────────────────────────────────────────────────
SECRET_VALUE=$(python3 -c "
import json, sys
print(json.dumps({'private_key': sys.argv[1], 'public_key': sys.argv[2]}))
" "$PRIVATE_KEY" "$PUBLIC_KEY")

if aws secretsmanager describe-secret \
     --secret-id "$SECRET_NAME" \
     --region "$REGION" \
     --output text > /dev/null 2>&1; then
  echo "Updating existing secret '$SECRET_NAME'..."
  aws secretsmanager put-secret-value \
    --secret-id "$SECRET_NAME" \
    --region "$REGION" \
    --secret-string "$SECRET_VALUE"
else
  echo "Creating secret '$SECRET_NAME'..."
  aws secretsmanager create-secret \
    --name "$SECRET_NAME" \
    --region "$REGION" \
    --description "RKE node SSH key pair (managed by create-rke-ssh-key.sh)" \
    --secret-string "$SECRET_VALUE"
fi

# ── Save local copy ───────────────────────────────────────────────────────────
cp "$WORK_DIR/id_rsa" "$SSH_KEY_PATH"
chmod 600 "$SSH_KEY_PATH"

echo ""
echo "✓ Secret '$SECRET_NAME' written to Secrets Manager (region: $REGION)"
echo "✓ Private key saved to $SSH_KEY_PATH (permissions 600)"
echo ""
echo "Next: run 'terraform apply' in RKE-cluster/dev-cluster/ec2"
echo "  The tls_private_key resource will be ignored because the secret already exists."
echo "  To SSH to nodes after deploy:"
echo "    ssh -i $SSH_KEY_PATH ubuntu@<SERVER_IP>"
