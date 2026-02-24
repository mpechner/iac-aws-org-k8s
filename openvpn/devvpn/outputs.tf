# OpenVPN dev environment outputs

output "openvpn_server_id" {
  description = "ID of the OpenVPN server instance"
  value       = module.openvpn.openvpn_server_id
}

output "openvpn_public_ip" {
  description = "Public IP address of the OpenVPN server"
  value       = module.openvpn.openvpn_public_ip
}

output "openvpn_private_ip" {
  description = "Private IP address of the OpenVPN server"
  value       = module.openvpn.openvpn_private_ip
}

output "openvpn_security_group_id" {
  description = "ID of the OpenVPN security group"
  value       = module.openvpn.openvpn_security_group_id
}

output "detected_admin_ip" {
  description = "Admin CIDR used for security group rules"
  value       = local.admin_ip
}

output "ssh_command" {
  description = "SSH command to connect to the OpenVPN server"
  value       = module.openvpn.ssh_command
}

output "vpn_connection_info" {
  description = "OpenVPN Access Server connection information"
  value       = module.openvpn.vpn_connection_info
}

output "vpn_dns_settings" {
  description = "DNS to set in Configuration → VPN Settings"
  value       = module.openvpn.vpn_dns_settings
}

output "vpn_fqdn" {
  description = "VPN hostname (vpn.<domain_name>). Set when route53_zone_id is provided."
  value       = module.openvpn.vpn_fqdn
}
