# OpenVPN Terraform Outputs

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

output "detected_admin_ip" {
  description = "Detected or configured admin IP address used for security group rules"
  value       = local.admin_ip
}

output "openvpn_dns_name" {
  description = "DNS name for the OpenVPN server (if Route53 record created)"
  value       = var.create_dns_record ? "vpn.${var.domain}" : ""
}

output "ssh_command" {
  description = "SSH command to connect to the OpenVPN server"
  value       = "ssh -i ~/.ssh/${aws_key_pair.openvpn_ssh.key_name}.pem ${var.ssh_username}@${aws_eip.openvpn.public_ip}"
}

output "vpn_connection_info" {
  description = "OpenVPN Access Server connection information"
  value = {
    server_ip   = aws_eip.openvpn.public_ip
    admin_url   = "https://${aws_eip.openvpn.public_ip}:943/admin"
    client_url  = "https://${aws_eip.openvpn.public_ip}:943/"
    default_user = "openvpn"
  }
}
