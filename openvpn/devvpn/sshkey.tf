# SSH key pair for OpenVPN server (stored in Secrets Manager)
# The private key is written to ~/.ssh/openvpn-ssh for Ansible/SSH access

# Generate new SSH key pair
resource "tls_private_key" "openvpn_ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Create/recreate the secret in Secrets Manager
resource "aws_secretsmanager_secret" "openvpn_ssh_keypair" {
  name                           = "openvpn-ssh"
  recovery_window_in_days        = 0
  force_overwrite_replica_secret = true
}

# Store the key in Secrets Manager
resource "aws_secretsmanager_secret_version" "openvpn_ssh_keypair_version" {
  secret_id = aws_secretsmanager_secret.openvpn_ssh_keypair.id
  secret_string = jsonencode({
    private_key = tls_private_key.openvpn_ssh.private_key_pem
    public_key  = tls_private_key.openvpn_ssh.public_key_openssh
  })
}

# Read the secret back (ensures we get the actual stored value)
data "aws_secretsmanager_secret_version" "openvpn_ssh_keypair" {
  secret_id  = aws_secretsmanager_secret.openvpn_ssh_keypair.id
  depends_on = [aws_secretsmanager_secret_version.openvpn_ssh_keypair_version]
}

# Create AWS key pair
resource "aws_key_pair" "openvpn_ssh" {
  key_name   = "openvpn-ssh-keypair"
  public_key = tls_private_key.openvpn_ssh.public_key_openssh
}

# Write SSH private key to local file for Ansible/SSH access
# This reads from Secrets Manager so it works even if the key was created in a previous run
resource "local_file" "openvpn_ssh_private_key" {
  content         = jsondecode(data.aws_secretsmanager_secret_version.openvpn_ssh_keypair.secret_string)["private_key"]
  filename        = "${pathexpand("~/.ssh")}/openvpn-ssh"
  file_permission = "0600"

  depends_on = [data.aws_secretsmanager_secret_version.openvpn_ssh_keypair]
}
