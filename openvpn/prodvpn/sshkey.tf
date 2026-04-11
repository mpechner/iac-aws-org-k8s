# SSH key pair for OpenVPN prod server — Terraform creates the EC2 Key Pair from the secret.
# The secret is created by scripts/create-openvpn-ssh-key.sh before terraform apply.

data "aws_secretsmanager_secret_version" "openvpn_ssh_keypair" {
  secret_id = "openvpn-ssh-prod"
}

# Create EC2 Key Pair from the public key in the secret
resource "aws_key_pair" "openvpn_ssh" {
  key_name   = "openvpn-ssh-keypair"
  public_key = jsondecode(data.aws_secretsmanager_secret_version.openvpn_ssh_keypair.secret_string)["public_key"]
}
