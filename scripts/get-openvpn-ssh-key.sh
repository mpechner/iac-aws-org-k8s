#!/bin/bash
# Get OpenVPN SSH private key from AWS Secrets Manager
# Usage: ./scripts/get-openvpn-ssh-key.sh [secret-name]
# If no secret name provided, defaults to: openvpn-ssh

set -e

# Default to OpenVPN SSH key secret (created by openvpn/terraform)
SECRET_NAME="${1:-openvpn-ssh}"
SSH_KEY_PATH="$HOME/.ssh/openvpn-ssh-keypair.pem"

echo "Fetching OpenVPN SSH key from Secrets Manager..."
echo "Secret: $SECRET_NAME"

# Assume the terraform-execute role to access dev account
echo "Assuming terraform-execute role..."
TEMP_CREDS=$(aws sts assume-role \
  --role-arn "arn:aws:iam::REDACTED_ACCOUNT_ID:role/terraform-execute" \
  --role-session-name "get-openvpn-ssh-key" \
  --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
  --output text)

export AWS_ACCESS_KEY_ID=$(echo $TEMP_CREDS | awk '{print $1}')
export AWS_SECRET_ACCESS_KEY=$(echo $TEMP_CREDS | awk '{print $2}')
export AWS_SESSION_TOKEN=$(echo $TEMP_CREDS | awk '{print $3}')

# Get the private key from AWS Secrets Manager
# The secret contains JSON with private_key and public_key fields
aws secretsmanager get-secret-value \
  --secret-id "$SECRET_NAME" \
  --region us-west-2 \
  --query SecretString \
  --output text | jq -r '.private_key' > "$SSH_KEY_PATH"

if [ ! -s "$SSH_KEY_PATH" ]; then
  echo "ERROR: Failed to retrieve SSH key or key is empty"
  rm -f "$SSH_KEY_PATH"
  exit 1
fi

# Verify it's a valid PEM key
if ! head -1 "$SSH_KEY_PATH" | grep -q "BEGIN.*PRIVATE KEY"; then
  echo "ERROR: Retrieved key is not in valid PEM format"
  echo "Key content:"
  head -3 "$SSH_KEY_PATH"
  rm -f "$SSH_KEY_PATH"
  exit 1
fi

# Set proper permissions
chmod 600 "$SSH_KEY_PATH"

echo "✓ SSH key saved to $SSH_KEY_PATH"
echo "✓ Permissions set to 600"
echo ""
echo "Connect to OpenVPN server (use server IP from terraform output):"
echo "  ssh -i ~/.ssh/openvpn-ssh-keypair.pem openvpnas@<SERVER_IP>"
