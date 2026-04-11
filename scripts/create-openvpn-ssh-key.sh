#!/bin/bash
# Generate OpenVPN SSH key pair and store in AWS Secrets Manager
#
# Usage:
#   ./scripts/create-openvpn-ssh-key.sh <dev|prod> <account_id> [--force]
#
# Secret names:
#   dev  → openvpn-ssh       (matches openvpn/devvpn/sshkey.tf)
#   prod → openvpn-ssh-prod  (matches openvpn/prodvpn/sshkey.tf)
#
# Idempotent: if the secret already exists and is a valid key, the script
# prints a warning and exits without overwriting unless --force is passed.

set -euo pipefail

# ── Args ──────────────────────────────────────────────────────────────────────
ENV="${1:-}"
AWS_ACCOUNT_ID="${2:-}"
FORCE="${3:-}"

if [ -z "$ENV" ] || [ -z "$AWS_ACCOUNT_ID" ]; then
  echo "Usage: $0 <dev|prod> <account_id> [--force]"
  exit 1
fi

case "$ENV" in
  dev)
    SECRET_NAME="openvpn-ssh"
    SSH_KEY_PATH="$HOME/.ssh/openvpn-ssh-keypair.pem"
    TF_DIR="openvpn/devvpn"
    ;;
  prod)
    SECRET_NAME="openvpn-ssh-prod"
    SSH_KEY_PATH="$HOME/.ssh/openvpn-ssh-keypair-prod.pem"
    TF_DIR="openvpn/prodvpn"
    ;;
  *)
    echo "ERROR: Unknown environment '$ENV'. Use 'dev' or 'prod'."
    exit 1
    ;;
esac

REGION="us-west-2"

# ── Assume terraform-execute role ─────────────────────────────────────────────
echo "Assuming terraform-execute role in account $AWS_ACCOUNT_ID ($ENV)..."
TEMP_CREDS=$(aws sts assume-role \
  --role-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/terraform-execute" \
  --role-session-name "create-openvpn-ssh-key-${ENV}" \
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
      echo "        $0 $ENV --force"
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
ssh-keygen -t rsa -b 4096 -N "" -f "$WORK_DIR/id_rsa" -C "openvpn-ssh-${ENV}" -q

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
    --description "OpenVPN ${ENV} server SSH key pair (managed by create-openvpn-ssh-key.sh)" \
    --secret-string "$SECRET_VALUE"
fi

# ── Save local copy ───────────────────────────────────────────────────────────
cp "$WORK_DIR/id_rsa" "$SSH_KEY_PATH"
chmod 600 "$SSH_KEY_PATH"

echo ""
echo "✓ Secret '$SECRET_NAME' written to Secrets Manager (region: $REGION)"
echo "✓ Private key saved to $SSH_KEY_PATH (permissions 600)"
echo ""
echo "Next: run 'terraform apply' in $TF_DIR"
echo "  Terraform will read the public key from the secret rather than generating a new one."
echo "  To SSH to the OpenVPN server after deploy:"
echo "    ssh -i $SSH_KEY_PATH openvpnas@<SERVER_IP>"
