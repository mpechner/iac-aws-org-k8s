#!/bin/bash
set -e

# Update and install prerequisites
apt-get update -y
apt-get install -y git software-properties-common

# Install Ansible (Ubuntu PPA)
apt-add-repository --yes --update ppa:ansible/ansible
apt-get install -y ansible

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