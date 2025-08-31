resource "tls_private_key" "rke_ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_secretsmanager_secret" "rke_ssh_keypair" {
  name = "rke-ssh"
  recovery_window_in_days = 0  # Delete immediately on destroy
  force_overwrite_replica_secret = true
}

resource "aws_secretsmanager_secret_version" "rke_ssh_keypair_version" {
  secret_id = aws_secretsmanager_secret.rke_ssh_keypair.id
  secret_string = jsonencode({
    private_key = tls_private_key.rke_ssh.private_key_pem
    public_key  = tls_private_key.rke_ssh.public_key_openssh
  })
}

resource "aws_key_pair" "rke_ssh" {
  key_name   = "rke-ssh-keypair"
  public_key = tls_private_key.rke_ssh.public_key_openssh
}