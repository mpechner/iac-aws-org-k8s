#!/bin/bash
# Install TLS certificate on OpenVPN server via SSH (run from Kubernetes CronJob or locally)
# This bypasses the AWS CLI connectivity issues on the OpenVPN server

set -e

VPN_FQDN="${VPN_FQDN:-vpn.dev.foobar.support}"
SSH_KEY="${SSH_KEY:-~/.ssh/openvpn-ssh-keypair.pem}"
SSH_USER="${SSH_USER:-openvpnas}"

echo "🔧 Installing certificate on OpenVPN server: $VPN_FQDN"

# Read certificate and key from AWS Secrets Manager (run this from a machine with AWS access)
echo "📖 Reading secret from AWS Secrets Manager..."
SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id openvpn/dev --region us-west-2 --query SecretString --output text)

# Extract certificate and key
TLS_CRT=$(echo "$SECRET_JSON" | jq -r '.["tls.crt"] // .certificate // empty')
TLS_KEY=$(echo "$SECRET_JSON" | jq -r '.["tls.key"] // .private_key // empty')

if [ -z "$TLS_CRT" ] || [ -z "$TLS_KEY" ]; then
    echo "❌ Secret missing certificate or key"
    exit 1
fi

echo "🔒 Installing certificate files via SSH..."

# Create temp files
TMP_CRT=$(mktemp)
TMP_KEY=$(mktemp)
echo "$TLS_CRT" > "$TMP_CRT"
echo "$TLS_KEY" > "$TMP_KEY"

# Copy files to OpenVPN server
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$TMP_CRT" "$SSH_USER@$VPN_FQDN:/tmp/server.crt"
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$TMP_KEY" "$SSH_USER@$VPN_FQDN:/tmp/server.key"

# Move files to correct location and configure
echo "🔧 Configuring OpenVPN Access Server..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$SSH_USER@$VPN_FQDN" "sudo bash -c 'mv /tmp/server.crt /usr/local/openvpn_as/etc/web-ssl/server.crt && mv /tmp/server.key /usr/local/openvpn_as/etc/web-ssl/server.key && chmod 644 /usr/local/openvpn_as/etc/web-ssl/server.crt && chmod 600 /usr/local/openvpn_as/etc/web-ssl/server.key'"

# Restart OpenVPN service
echo "🔄 Restarting OpenVPN Access Server..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$SSH_USER@$VPN_FQDN" "sudo systemctl restart openvpnas || sudo service openvpnas restart"

# Cleanup
rm -f "$TMP_CRT" "$TMP_KEY"

echo "✅ Certificate installed successfully on $VPN_FQDN"
echo ""
echo "Verify: https://$VPN_FQDN:943/admin (Web Server Configuration)"
