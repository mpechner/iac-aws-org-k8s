#!/bin/bash
# Setup TLS Certificate Sync for OpenVPN Access Server
# This script verifies prerequisites and runs the Ansible playbook

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration - can be overridden with environment variables
VPN_FQDN="${VPN_FQDN:-vpn.dev.foobar.support}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/openvpn-ssh}"
TLS_SECRET_NAME="${TLS_SECRET_NAME:-openvpn/dev}"
AWS_REGION="${AWS_REGION:-us-west-2}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🔧 OpenVPN TLS Certificate Sync Setup"
echo "======================================"
echo "VPN FQDN: $VPN_FQDN"
echo "SSH Key: $SSH_KEY"
echo "Secret: $TLS_SECRET_NAME"
echo ""

# Check 1: Ansible is installed
echo "📋 Checking prerequisites..."
if ! command -v ansible-playbook &>/dev/null; then
    echo -e "${RED}❌ Ansible is not installed${NC}"
    echo "Install Ansible:"
    echo "  macOS:   brew install ansible"
    echo "  Ubuntu:  sudo apt install ansible"
    echo "  Python:  pip install ansible"
    exit 1
fi
echo -e "${GREEN}✅ Ansible installed: $(ansible-playbook --version | head -1)${NC}"

# Check 2: SSH key exists
if [ ! -f "$SSH_KEY" ]; then
    echo -e "${RED}❌ SSH key not found: $SSH_KEY${NC}"
    echo "Generate or obtain the SSH key for OpenVPN server access"
    exit 1
fi
echo -e "${GREEN}✅ SSH key exists: $SSH_KEY${NC}"

# Check 3: AWS CLI is available (optional but recommended)
if command -v aws &>/dev/null; then
    AWS_VERSION=$(aws --version 2>&1 | awk '{print $1}')
    echo -e "${GREEN}✅ AWS CLI: $AWS_VERSION${NC}"
    
    # Check AWS credentials work
    if aws sts get-caller-identity &>/dev/null; then
        AWS_ACCOUNT=$(aws sts get-caller-identity --query 'Account' --output text)
        echo -e "${GREEN}✅ AWS credentials valid (Account: $AWS_ACCOUNT)${NC}"
    else
        echo -e "${YELLOW}⚠️  AWS credentials not configured or invalid${NC}"
        echo "   Run: aws configure"
        echo "   Or: export AWS_PROFILE=your-profile"
    fi
else
    echo -e "${YELLOW}⚠️  AWS CLI not installed (optional - only needed for verification)${NC}"
fi

# Check 4: Verify secret exists (if AWS CLI is available)
# Use public endpoint to bypass VPC endpoint timing issues from public subnet
if command -v aws &>/dev/null && aws sts get-caller-identity &>/dev/null; then
    echo ""
    echo "🔍 Checking AWS Secrets Manager..."
    if aws --endpoint-url "https://secretsmanager.${AWS_REGION}.amazonaws.com" secretsmanager describe-secret --secret-id "$TLS_SECRET_NAME" --region "$AWS_REGION" &>/dev/null; then
        echo -e "${GREEN}✅ Secret '$TLS_SECRET_NAME' exists in $AWS_REGION${NC}"
    else
        echo -e "${YELLOW}⚠️  Secret '$TLS_SECRET_NAME' not found in $AWS_REGION${NC}"
        echo "   The sync script will retry every 30 minutes until the secret is available."
        echo "   Make sure the OpenVPN TLS Certificate Pipeline is deployed (Step 10)."
        
        # Skip interactive prompt if AUTO_APPROVE is set (for Terraform)
        if [ -z "${AUTO_APPROVE:-}" ]; then
            read -p "Continue anyway? (y/n) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        else
            echo "   AUTO_APPROVE set - continuing..."
        fi
    fi
fi

# Check 5: Server connectivity
echo ""
echo "🔍 Testing connectivity to OpenVPN server..."
if ping -c 1 -W 5 "$VPN_FQDN" &>/dev/null; then
    echo -e "${GREEN}✅ Server reachable: $VPN_FQDN${NC}"
else
    echo -e "${YELLOW}⚠️  Cannot ping $VPN_FQDN${NC}"
    echo "   Checking if DNS resolves..."
    if host "$VPN_FQDN" &>/dev/null; then
        echo -e "${GREEN}✅ DNS resolves: $(host "$VPN_FQDN" | head -1)${NC}"
    else
        echo -e "${RED}❌ DNS does not resolve for $VPN_FQDN${NC}"
        echo "   Use IP address instead or fix DNS"
        exit 1
    fi
fi

# Check 6: SSH connectivity
echo ""
echo "🔍 Testing SSH connectivity..."
SSH_OK=false
SSH_ATTEMPTS="${SSH_ATTEMPTS:-3}"
SSH_WAIT="${SSH_WAIT:-20}"

for i in $(seq 1 $SSH_ATTEMPTS); do
    if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY" "openvpnas@$VPN_FQDN" "echo 'SSH OK'" &>/dev/null; then
        echo -e "${GREEN}✅ SSH connection successful${NC}"
        SSH_OK=true
        break
    else
        if [ $i -lt $SSH_ATTEMPTS ]; then
            echo -e "${YELLOW}⚠️  SSH attempt $i/$SSH_ATTEMPTS failed, waiting ${SSH_WAIT}s for instance to boot...${NC}"
            sleep $SSH_WAIT
        fi
    fi
done

if [ "$SSH_OK" = false ]; then
    if [ -n "${AUTO_APPROVE:-}" ]; then
        echo -e "${YELLOW}⚠️  Cannot SSH to OpenVPN server after $SSH_ATTEMPTS attempts.${NC}"
        echo "   Instance may still be booting. TLS sync was NOT installed."
        echo "   Run manually once the server is ready:"
        echo "     cd $(pwd) && SSH_KEY=$SSH_KEY VPN_FQDN=$VPN_FQDN ./setup-tls-sync.sh"
        exit 0
    else
        echo -e "${RED}❌ Cannot SSH to OpenVPN server${NC}"
        echo "   Check:"
        echo "   - Security group allows SSH from your IP"
        echo "   - Key permissions: chmod 600 $SSH_KEY"
        echo "   - Instance is running and has public IP"
        exit 1
    fi
fi

# All checks passed
echo ""
echo -e "${GREEN}✅ All prerequisites met!${NC}"
echo ""

# Run Ansible
echo "🚀 Running Ansible playbook..."
echo "================================"
cd "$SCRIPT_DIR"

export VPN_FQDN
export ANSIBLE_HOST_KEY_CHECKING=False
export ANSIBLE_SSH_ARGS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
# Use /tmp for Ansible temp files (openvpnas user has limited home permissions)
export ANSIBLE_REMOTE_TMP=/tmp/.ansible-openvpnas

ansible-playbook \
    -i "${VPN_FQDN}," \
    -e "vpn_fqdn=${VPN_FQDN}" \
    -e "tls_secret_name=${TLS_SECRET_NAME}" \
    -e "tls_secret_region=${AWS_REGION}" \
    --private-key="$SSH_KEY" \
    -u openvpnas \
    openvpn-tls-sync.yml

PLAYBOOK_RESULT=$?

echo ""
if [ $PLAYBOOK_RESULT -eq 0 ]; then
    echo -e "${GREEN}✅ TLS sync configured successfully!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. SSH to the server: ssh -i $SSH_KEY openvpnas@$VPN_FQDN"
    echo "  2. Check sync log: sudo tail -20 /var/log/openvpn-tls-sync.log"
    echo "  3. Verify certificate: sudo openssl x509 -in /usr/local/openvpn_as/etc/web-ssl/server.crt -noout -text"
    echo ""
    echo "The certificate will be automatically updated every 30 minutes via cron."
else
    echo -e "${RED}❌ Ansible playbook failed${NC}"
    exit 1
fi
