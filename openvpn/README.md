# OpenVPN Server on AWS

A complete OpenVPN Access Server solution using **Terraform** for infrastructure. This setup provides a secure, scalable VPN solution with up to 5 concurrent users using the official OpenVPN Access Server AMI.

## 🏗️ Architecture

- **Terraform**: Creates EC2 instance, security groups, networking, and Elastic IP
- **OpenVPN Access Server**: Pre-configured AMI with web-based admin interface
- **Professional Features**: User management, certificate generation, and monitoring
- **5-User License**: Affordable licensing for small teams

## 🔒 Security Features

- **Automatic IP Detection**: Your public IP is auto-detected and used to restrict admin access
- **Restricted SSH Access**: Only accessible from your detected/specified IP address
- **Certificate-based Authentication**: No password-based attacks possible
- **Strong Encryption**: AES-256-GCM with SHA256 authentication
- **Network Isolation**: VPN clients get isolated IP range (10.8.0.0/24)
- **Firewall Protection**: UFW with minimal open ports

## 📋 Prerequisites

### Required
- AWS CLI configured with appropriate permissions
- Terraform >= 1.0 installed
- SSH key pair in AWS
- Existing VPC and subnet

### Instance Type Recommendation
- **t3.small** (default): Optimal for OpenVPN Access Server
- **t3.medium**: Better performance for 5+ concurrent users
- **t3.micro**: Minimum viable (may have performance issues)

### Optional
- Route53 hosted zone (for DNS records)
- Domain name

## 🚀 Quick Start

### 1. Clone and Setup
```bash
cd openvpn
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

### 2. Configure Variables
Edit `terraform/terraform.tfvars`:
```hcl
# Required: Update these values
subnet_id = "subnet-your-actual-subnet-id"
key_pair_name = "your-aws-key-pair-name"

# Optional: Your IP will be auto-detected. Override only if needed:
# comcast_ip = "203.0.113.1/32"
```

### 3. Deploy Infrastructure
```bash
chmod +x scripts/deploy-infrastructure.sh
./scripts/deploy-infrastructure.sh
```

### 4. Access OpenVPN Admin Interface
Visit: `https://YOUR_SERVER_IP:943/admin`

**Default credentials:**
- Username: `openvpn`
- Password: `openvpn`

### 5. Download Client Configurations
Visit: `https://YOUR_SERVER_IP:944/`

## 📁 Project Structure

```
openvpn/
├── terraform/                 # Infrastructure as Code
│   ├── main.tf               # Main Terraform configuration
│   ├── variables.tf          # Variable definitions
│   ├── outputs.tf            # Output values
│   ├── terraform.tf          # Provider and backend config
│   ├── userdata.sh           # EC2 instance startup script
│   └── terraform.tfvars      # Your configuration values
├── scripts/                   # Deployment scripts
│   └── deploy-infrastructure.sh
└── README.md                 # This file
```

## 🔧 Manual Steps (If Needed)

### Finding Your Comcast IP
```bash
# Get your current public IP
curl ifconfig.me
# or
curl ipinfo.io/ip
```

### Creating AWS Key Pair
```bash
# Generate SSH key
ssh-keygen -t rsa -b 4096 -f ~/.ssh/openvpn-key

# Import to AWS
aws ec2 import-key-pair \
  --key-name openvpn-key \
  --public-key-material fileb://~/.ssh/openvpn-key.pub
```

### Manual Certificate Generation
If you need to generate additional client certificates:

```bash
# SSH to the server
ssh -i ~/.ssh/openvpn-key.pem ubuntu@YOUR_SERVER_IP

# Generate new client certificate
cd /etc/openvpn/easy-rsa
./easyrsa build-client-full client2 nopass

# Copy to web directory
cp pki/issued/client2.crt /var/www/html/certs/
cp pki/private/client2.key /var/www/html/certs/
```

## 📱 Client Setup

### OpenVPN Connect (Official Client)
1. Download from [https://openvpn.net/client/](https://openvpn.net/client/)
2. Import the `client-config.ovpn` file
3. Connect to your VPN

### Other Clients
- **macOS**: Tunnelblick, Viscosity
- **Linux**: OpenVPN CLI, NetworkManager
- **Windows**: OpenVPN GUI, Viscosity
- **Mobile**: OpenVPN Connect app

## 🔍 Troubleshooting

### Auto-Detected IP Address

By default, Terraform automatically detects your public IP address and uses it to restrict SSH and admin web access. The detected IP will be shown in the outputs after `terraform apply`:

```bash
detected_admin_ip = "203.0.113.1/32"
```

To override auto-detection and use a specific IP, set it in `terraform.tfvars`:
```hcl
comcast_ip = "203.0.113.1/32"
```

### Finding Your Public IP Manually

```bash
# Get your current public IP
curl ifconfig.me
# or
curl ipinfo.io/ip
```

### Common Issues

#### SSH Connection Failed
- Check security group allows SSH from your IP
- Verify key pair name in terraform.tfvars
- Ensure instance is running and healthy

#### OpenVPN Access Server Issues
```bash
# Check OpenVPN Access Server status
sudo systemctl status openvpnas

# Check logs
sudo tail -f /var/log/openvpnas.log
```

#### Certificate Issues
```bash
# Verify certificate validity
openssl x509 -in /etc/openvpn/server/server.crt -text -noout

# Check certificate chain
openssl verify -CAfile /etc/openvpn/server/ca.crt /etc/openvpn/server/server.crt
```

### Log Locations
- **OpenVPN Access Server**: `/var/log/openvpnas.log`
- **System**: `/var/log/syslog`
- **Access Server**: `/usr/local/openvpn_as/logs/`

## 🗑️ Cleanup

### Destroy Infrastructure
```bash
cd terraform
terraform destroy
```

### Remove OpenVPN Access Server
```bash
# SSH to server and uninstall if needed
sudo /usr/local/openvpn_as/bin/ovpn-init --remove
```

## 📊 Monitoring

### Check VPN Status
```bash
# View connected clients
sudo cat /usr/local/openvpn_as/logs/openvpn.log

# Check OpenVPN Access Server process
ps aux | grep openvpnas
```

### Performance Monitoring
```bash
# Check system resources
htop
iotop
nethogs
```

## 🔐 Security Best Practices

1. **Regular Updates**: Keep Ubuntu and OpenVPN updated
2. **Certificate Rotation**: Rotate certificates annually
3. **Access Logging**: Monitor VPN access logs
4. **Backup**: Backup certificates and configurations
5. **Network Monitoring**: Monitor for unusual traffic patterns

## 📞 Support

For issues or questions:
1. Check the troubleshooting section above
2. Review OpenVPN logs on the server
3. Verify AWS security group settings
4. Check Terraform and Ansible outputs

## 📄 License

This project is open source. OpenVPN Access Server has a 5-user license included with the AMI.

## 🆕 Updates

- **v1.0**: Initial release with Terraform
- OpenVPN Access Server 5-user license
- Professional web-based admin interface
- Automated certificate generation
- Restricted SSH access
- Professional VPN solution
