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

## 🚀 Quick Start

### 1. Clone and Setup
```bash
cd openvpn/devvpn
# Optional: cp backend.hcl.example backend.hcl and terraform init -backend-config=backend.hcl
```

### 2. Configure Variables
Use defaults or create `devvpn/terraform.tfvars` to override:
```hcl
# Optional: subnet_id and vpc_id default from VPC remote state
# Optional: Your IP is auto-detected; override if needed:
# comcast_ip = "203.0.113.1/32"

# Optional: Create Route53 A record so VPN is reachable at vpn.<domain_name>
# For devvpn the FQDN is vpn.dev.foobar.support. Get zone ID from route53/delegate or: aws route53 list-hosted-zones-by-name --dns-name dev.foobar.support
# route53_zone_id = "Z0xxxxxxxxxxxx"
# domain_name     = "dev.foobar.support"   # default; hostname is always "vpn"
```

### 3. Run Terraform

```bash
cd openvpn/devvpn
terraform init
terraform plan    # optional: preview
terraform apply
```

### 4. Update OS and Access OpenVPN Admin Interface

**Important: First, update the OS and reboot before configuring:**
```bash
ssh -i ~/.ssh/openvpn-ssh-keypair.pem openvpnas@<SERVER_IP>

sudo apt update
sudo apt upgrade -y
sudo reboot
```

After reboot, access the Admin Interface:
Visit: `https://YOUR_SERVER_IP:943/admin` (or `https://vpn.dev.foobar.support:943/admin` if `route53_zone_id` is set)

**Default credentials:**
- Username: `openvpn`
- Password: `openvpn`

### 5. Configure Hostname and DNS (required for deployment)

Set the hostname to the full domain name, then configure DNS so clients can resolve internal AWS services and private hosted zones. Do this right after deploying the VPN (step 2 in the deployment order).

**Steps (OpenVPN 3.0.1+ new web interface):**
1. Open the Admin UI: `https://YOUR_SERVER_IP:943/admin`
2. Go to **VPN Server** (left sidebar) → **Network Settings** tab and set the **Hostname (or IP address)** to the full domain name (e.g. `vpn.dev.foobar.support`). Interface should be "All interfaces". Click **Save** at the top right.
3. Go to **Access Controls** (left sidebar) → **Internet Access and DNS** tab.
4. Configure DNS settings:

**DNS Settings:**
- Select **Split-Tunnel**
- **Push DNS:** On
- **Select DNS Servers:** Custom
- **DNS Server**: `10.8.0.2` (AWS VPC internal DNS for dev VPC)
- Click **Add another DNS server** and add `8.8.8.8`

**DNS Resolution Zones (Optional):**
- **DNS Resolution Zones**: `foobar.support`
- **Default Domain Suffix (optional)**: `foobar.support`
  
  This ensures VPN clients can resolve:
  - `nginx.dev.foobar.support` → internal NLB IPs
  - `traefik.dev.foobar.support` → internal dashboard
  - `rancher.dev.foobar.support` → Kubernetes management UI
  - Any other services using your private Route53 hosted zone

**Important:** Make sure "Do not alter clients' DNS server settings" is **DISABLED/OFF**.

**VPC-Specific DNS Resolvers:**
Different VPCs use different DNS resolver IPs. The DNS server is always at `VPC_CIDR + 2`:
- **Dev VPC** (`10.8.0.0/16`): DNS at `10.8.0.2`
- **Staging VPC** (`10.4.0.0/16`): DNS at `10.4.0.2`
- **Prod VPC** (`10.0.0.0/16`): DNS at `10.0.0.2`
- **Test VPC** (`10.12.0.0/16`): DNS at `10.12.0.2`

**After Configuration:**
1. Changes are auto-saved when you click **Save**. The VPN service will update.
2. Reconnect your VPN client
3. Test DNS resolution:
   ```bash
   dig nginx.dev.foobar.support
   # Should return private IPs like 10.8.x.x
   ```

**Using sacli (command line):** You can set hostname and all DNS settings from the server instead of the Admin UI. SSH in as root (or use `sudo`), then run from `/usr/local/openvpn_as/scripts/`. Adjust `HOSTNAME` and `DNS_ZONE` for your environment.

```bash
cd /usr/local/openvpn_as/scripts
mkdir -p out && sudo chown openvpnas:openvpnas out

# 1. Hostname (VPN Server → Network Settings) — use your VPN FQDN
HOSTNAME="vpn.dev.foobar.support"
sudo ./sacli --key "host.name" --value "$HOSTNAME" ConfigPut

# 2. "custom" = use explicit DNS servers (not auto-detected); always proxy through AS
sudo ./sacli --key "vpn.client.routing.reroute_dns" --value "custom" ConfigPut
sudo ./sacli --key "dnsproxy.mode" --value "always" ConfigPut

# 3. Primary DNS (AWS VPC resolver), secondary (public fallback), domain suffix
DNS_PRIMARY="10.8.0.2"
DNS_SECONDARY="8.8.8.8"
DNS_ZONE="foobar.support"
sudo ./sacli --key "vpn.server.dhcp_option.dns.0" --value "$DNS_PRIMARY" ConfigPut
sudo ./sacli --key "vpn.server.dhcp_option.dns.1" --value "$DNS_SECONDARY" ConfigPut
sudo ./sacli --key "vpn.server.dhcp_option.adapter_domain_suffix" --value "$DNS_ZONE" ConfigPut

# 4. Save and update running server
sudo ./sacli start
```

**Note:** `vpn.server.config_text` replaces any existing custom server directives. If you have other directives (e.g. **Advanced → Additional OpenVPN Config**), run `./sacli ConfigQuery`, add the three `push` lines above to the exported config, then use `ConfigReplace` with that file instead of `ConfigPut`. For other VPCs use that VPC’s DNS resolver (e.g. `10.4.0.2` for 10.4.0.0/16).

### 6. Download Client Configurations
Visit: `https://YOUR_SERVER_IP:944/`


## 📁 Project Structure

```
openvpn/
├── module/                    # Reusable OpenVPN Terraform module
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── userdata.sh
├── devvpn/                    # Dev environment (uses module)
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── terraform.tf
│   ├── sshkey.tf
│   └── backend.hcl.example
└── README.md
```

## Troubleshooting

### "no matching EC2 Subnet found" or "AccessDeniedException" on Secrets Manager

Your Terraform state and OpenVPN resources (subnets, secrets, EC2) are in **one AWS account** (e.g. REDACTED_ACCOUNT_ID). If you run `terraform apply` with credentials for a **different account** (e.g. REDACTED_ACCOUNT_ID), you'll see:

- `Error: no matching EC2 Subnet found` (subnet is in the other account)
- `AccessDeniedException: ... is not authorized to perform secretsmanager:DescribeSecret on resource: arn:aws:...:REDACTED_ACCOUNT_ID:secret:...`

**Fix:** Run Terraform with credentials that can access the account where the state and resources live.

```bash
# See which account your current credentials use
aws sts get-caller-identity

# Then use a profile or role that targets the OpenVPN account (e.g. REDACTED_ACCOUNT_ID)
cd openvpn/devvpn
AWS_PROFILE=your-dev-account-profile terraform apply
```

If you use SSO, switch to the account that owns the OpenVPN VPC and state (same account ID as in the state S3 bucket and resource ARNs).

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

To override auto-detection and use a specific IP, set it in `devvpn/terraform.tfvars`:
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

#### DNS Not Resolving Internal Domains

If you can't access internal services (e.g., `nginx.dev.foobar.support`):

1. **Verify VPN DNS Configuration:**
   ```bash
   # On macOS/Linux, check if VPN pushed DNS settings
   scutil --dns | grep "nameserver\|domain"
   
   # Should show 10.8.0.2 (or your VPC's DNS) as a nameserver
   ```

2. **Test DNS Resolution:**
   ```bash
   # Should return private IPs (10.8.x.x)
   dig nginx.dev.foobar.support
   
   # If it returns NXDOMAIN, DNS settings weren't pushed
   ```

3. **Reconnect VPN:**
   - Disconnect and reconnect your VPN client
   - DNS settings are only applied on connection

4. **Check OpenVPN Admin Settings (Access Controls → Internet Access and DNS in 3.0.1+):**
   - Verify **Split-Tunnel** is selected
   - Verify **Push DNS** is On
   - Verify **Select DNS Servers** is Custom with `10.8.0.2` and `8.8.8.8`
   - Verify **DNS Resolution Zones** includes your internal domain
   - Click **Save** at the top right

5. **Manual DNS Test (from VPN):**
   ```bash
   # Query AWS VPC DNS directly
   nslookup nginx.dev.foobar.support 10.8.0.2
   
   # Should return private IPs
   ```

#### SSH Connection Failed
- Check security group allows SSH from your IP
- Use the private key from Secrets Manager (openvpn-ssh) or the `ssh_command` output
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
cd openvpn/devvpn
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
