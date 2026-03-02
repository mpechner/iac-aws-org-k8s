# OpenVPN Module Outputs

output "openvpn_server_id" {
  description = "ID of the OpenVPN server instance"
  value       = aws_instance.openvpn.id
}

output "openvpn_public_ip" {
  description = "Public IP address of the OpenVPN server"
  value       = aws_eip.openvpn.public_ip
}

output "openvpn_private_ip" {
  description = "Private IP address of the OpenVPN server"
  value       = aws_instance.openvpn.private_ip
}

output "openvpn_security_group_id" {
  description = "ID of the OpenVPN security group"
  value       = aws_security_group.openvpn.id
}

output "ssh_command" {
  description = "SSH command to connect to the OpenVPN server"
  value       = "ssh -i ~/.ssh/${var.key_name}.pem ${var.ssh_username}@${aws_eip.openvpn.public_ip}"
}

output "vpn_connection_info" {
  description = "OpenVPN Access Server connection information"
  value = {
    server_ip    = aws_eip.openvpn.public_ip
    admin_url    = "https://${aws_eip.openvpn.public_ip}:943/admin"
    client_url   = "https://${aws_eip.openvpn.public_ip}:943/"
    default_user = "openvpn"
  }
}

output "vpn_dns_settings" {
  description = "DNS to set in Configuration → VPN Settings"
  value = {
    primary_dns   = "10.8.0.2"
    secondary_dns = "8.8.8.8"
    ui_path       = "Configuration → VPN Settings"
  }
}

output "vpn_fqdn" {
  description = "VPN hostname (vpn.<domain_name>). Set when route53_zone_id and domain_name are provided."
  value       = var.route53_zone_id != "" && var.domain_name != "" ? "vpn.${var.domain_name}" : null
}

output "tls_sync_enabled" {
  description = "Whether TLS certificate sync is enabled via Ansible"
  value       = var.enable_tls_sync
}

output "tls_sync_info" {
  description = "Information about the TLS sync setup"
  value = var.enable_tls_sync ? {
    secret_name   = var.tls_secret_name
    sync_script   = "/usr/local/bin/sync-vpn-tls.sh"
    log_file      = "/var/log/openvpn-tls-sync.log"
    check_command = "ssh -i ~/.ssh/${var.key_name}.pem ${var.ssh_username}@${aws_eip.openvpn.public_ip} 'sudo crontab -l | grep openvpn'"
  } : null
}
