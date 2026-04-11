# AWS Load Balancer Controller for RKE2

## The Problem

RKE2's built-in Cloud Controller Manager (CCM) **disables the service controller by default**:

```
--controllers=*,-route,-service
```

This means RKE2's CCM will **NOT** provision AWS Load Balancers for Kubernetes `LoadBalancer` services.

### Evidence from the logs:

```bash
$ kubectl logs -n kube-system cloud-controller-manager-ip-10-8-17-188 | grep controller
W0209 01:13:43.121575       1 controllermanager.go:306] "service-lb-controller" is disabled
```

## The Solution

Install the **AWS Load Balancer Controller** as a separate Helm chart. This is the standard approach for RKE2, EKS, and other Kubernetes distributions on AWS.

## What This Does

The AWS Load Balancer Controller:
- Provisions AWS Network Load Balancers (NLB) for Kubernetes `LoadBalancer` services
- Provisions AWS Application Load Balancers (ALB) for Kubernetes `Ingress` resources
- Manages security groups, target groups, and listeners automatically
- Supports advanced AWS features (WAF, Shield, ACM certificates, etc.)

## Files Created

1. `aws-lb-controller.tf` - Helm chart deployment
2. `aws-lb-controller-iam.tf` - IAM policy and role attachments
3. `terraform.tfvars` - Added `cluster_name` variable
4. `variables.tf` - Added `cluster_name` variable

## Deployment

```bash
cd deployments/rke-apps/1-infrastructure

# Initialize new resources
terraform init

# Review changes
terraform plan

# Deploy AWS Load Balancer Controller
terraform apply
```

## Verification

After deployment:

```bash
# Check controller is running
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Check logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Check if Traefik service gets an external IP (will take 1-2 minutes)
kubectl get svc traefik -n traefik -w

# Check AWS Console for NLB creation
# AWS Console → EC2 → Load Balancers → Region: us-west-2
```

## Expected Behavior

Once the AWS Load Balancer Controller is running:

1. It will detect the Traefik `LoadBalancer` service
2. It will create an AWS Network Load Balancer
3. The service will get an `EXTERNAL-IP` (NLB DNS name)
4. external-dns will create Route53 records automatically

## IAM Requirements

The controller needs IAM permissions to:
- Create/delete load balancers
- Manage target groups
- Create/manage security groups
- Tag AWS resources

These permissions are attached to the existing `rke-server-role` IAM role used by your RKE2 nodes.

## Troubleshooting

### Controller not starting

```bash
kubectl describe pod -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

### No load balancers created

```bash
# Check controller logs for errors
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=100

# Check if service has correct annotations
kubectl get svc traefik -n traefik -o yaml | grep -A 5 annotations
```

### IAM permission errors

If you see errors like "User: arn:aws:sts::xxx:assumed-role/... is not authorized to perform: elasticloadbalancing:CreateLoadBalancer":

1. Verify the IAM policy is attached: `terraform state show aws_iam_role_policy_attachment.aws_load_balancer_controller`
2. Check the node IAM role name matches: `data.aws_iam_role.nodes.name` should be `rke-server-role`
3. Wait 1-2 minutes for IAM propagation, then delete and recreate the controller pods

## References

- [AWS Load Balancer Controller Documentation](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [RKE2 Cloud Provider](https://docs.rke2.io/advanced#cloud-provider)
- [IAM Policy JSON](https://github.com/kubernetes-sigs/aws-load-balancer-controller/blob/main/docs/install/iam_policy.json)
