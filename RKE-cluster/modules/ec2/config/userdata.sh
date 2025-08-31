#!/bin/bash
set -e

# Update and install prerequisites (prefer IPv4; avoid PPA)
apt-get update -o Acquire::ForceIPv4=true -y || true
apt-get install -y git software-properties-common python3-pip python3-boto3 python3-botocore ansible || true

# Ensure recent boto libs (upgrade to >=1.34.0)
pip3 install --no-cache-dir --upgrade 'boto3>=1.34.0' 'botocore>=1.34.0' || true

# Install and enable AWS Systems Manager (SSM) Agent
apt-get install -y snapd || true
snap install amazon-ssm-agent --classic
systemctl enable --now snap.amazon-ssm-agent.amazon-ssm-agent.service

# Prepare Ansible workspace for the default user
DEFAULT_USER="ubuntu"
mkdir -p "/home/$${DEFAULT_USER}/ansible-playbook"
chown -R "$${DEFAULT_USER}:$${DEFAULT_USER}" "/home/$${DEFAULT_USER}/ansible-playbook"

## Variables (these will be replaced by Terraform via envsubst or inline variables)
#PLAYBOOK_REPO="${PLAYBOOK_REPO}"
#PLAYBOOK_DIR="/opt/ansible-playbook"
#PLAYBOOK_FILE="${PLAYBOOK_FILE}"
#
## Clone or update playbook repo
#if [ ! -d "$PLAYBOOK_DIR" ]; then
#  git clone "$PLAYBOOK_REPO" "$PLAYBOOK_DIR"
#else
#  cd "$PLAYBOOK_DIR"
#  git pull origin main
#fi
#
## Run the playbook locally
#ansible-playbook -i "localhost," -c local "$PLAYBOOK_DIR/$PLAYBOOK_FILE"
#