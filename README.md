# tf_take2
Another attempt at creating AWS infrastructure

A few years ago I created a AWS eks env in this repo https://github.com/mpechner/terraform_play

In the last 3 years workng at a company that used kubernetes, what makes a reasonable environment 
has matured.

[Network Plan](Network-Plan.md)

# Bootstrap
## Get the VPC infrastructure going
```
cd VPC
terraform apply
cd ..
```
## Bring ip VPN
```
cd openvpn/terraform
terraform apply
```
The output will provide important information for connecting. Since the security group is using my comcast public IP feel safe with defaults.  BUT WE ALL KNOW THIS IS BAD! The default password is not set.
```
vpn_connection_info = {
  "admin_url" = "https://54.214.242.159:943/admin"
  "client_url" = "https://54.214.242.159:943/"
  "default_user" = "openvpn"
  "server_ip" = "54.214.242.159"
}
```
Get the ssh key from secret openvpn-ssh and save the private key to ~/.ssh/openvpn.pem
```
chmod 600 ~/.ssh/openvpn.pem 
```
Set the default password
```
ssh -i ~/.ssh/openvpn-ssh-keypair.pem openvpnas@54.214.242.159
```

```
cd /usr/local/openvpn_as/scripts/
sudo ./sacli --user openvpn --new_pass APASSWORD SetLocalPassword
```
sign in and Agree to the terms

Create your user. Evern for play, to not use default admin profile
https://54.214.242.159:943/admin/user_permissions - create new user
From the commandline as root, run  sacli to set the users password.

Download the users profile
https://54.214.242.159:943/
login and download the profile. User-locked or autologin.  Again, since this is a lab and not production on server locked to a specific IP address, I an using the autologin profile.

## bring up the EC2 instances
```
cd RKE-CLUSTER/dev-cluster/ec2
terraform apply
```
copy the secret rke-ssh private key to ~/.ssh/rke-key and set perm 0600

## bring up RKE server/agents
Make sure the ec2 nodes are fully up.
You must be connected to the VPN now.
```
cd RKE-CLUSTER/dev-cluster/rke
terraform apply
```
# k9s
Change 10.8.91.172 to the correct IP address
```
scp -i ~/.ssh/rke-key ubuntu@10.8.91.172:/etc/rancher/rke2/rke2.yaml ~/.kube/dev-rke2.yaml
sed -i '' 's|server: https://127.0.0.1:6443|server: https://10.8.91.172:6443|' ~/.kube/dev-rke2.yaml
kubectl --kubeconfig ~/.kube/dev-rke2.yaml config rename-context rke2 dev-rke2
KUBECONFIG="$HOME/.kube/config:$HOME/.kube/dev-rke2.yaml" kubectl config view --flatten > $HOME/.kube/merged
    mv $HOME/.kube/merged $HOME/.kube/config
```