# Network Plan

In designing this environment I heavily used chatgpt. Where in the past when creating a company 
and planning the network latout youd mess it up.   either over allocate or not account for growth.

I set the following list of criteria:
* for each account assume 2 regions (DR) and 3 AZs
* Logging, audit and managment accounts had a small use for IP addrress since they primarily 
  centralize information
* production, staging, development and test
  *  200 databases, 100-200 nodes, 10,000 pods

Security and Logging /21 to allow VPC endpoints and tools and dashboards
Managment /21 sine nothing should eve endup here.

For production, staging, development and test a /14 for account and /15 for a region
```
## Subnet Plan for Region (`10.0.0.0/15`)

| Subnet Role     | AZ   | CIDR Block    | Size       |
|------------------|------|----------------|------------|
| Public           | az1  | 10.0.0.0/22     | 1024 IPs   |
| Public           | az2  | 10.0.4.0/22     | 1024 IPs   |
| Public           | az3  | 10.0.8.0/22     | 1024 IPs   |
| EKS Nodes        | az1  | 10.0.16.0/18    | 16,384 IPs |
| EKS Nodes        | az2  | 10.0.80.0/18    | 16,384 IPs |
| EKS Nodes        | az3  | 10.0.144.0/18   | 16,384 IPs |
| EKS Pods         | az1  | 10.1.0.0/17     | 32,768 IPs |
| EKS Pods         | az2  | 10.1.128.0/18   | 16,384 IPs |
| EKS Pods         | az3  | 10.1.192.0/18   | 16,384 IPs |
| DB Subnets       | az1  | 10.0.12.0/24    | 256 IPs    |
| DB Subnets       | az2  | 10.0.13.0/24    | 256 IPs    |
| DB Subnets       | az3  | 10.0.14.0/24    | 256 IPs    |
```

All accounts
```
## CIDR and IP Range for Each Account and Region

### **Logging Account**
- **CIDR**: `10.100.0.0/22`
  - **Region 1 (us-east-1)**: `10.100.0.0 – 10.100.3.255`
  - **Region 2 (us-west-2)**: `10.100.4.0 – 10.100.7.255`

### **Audit Account**
- **CIDR**: `10.101.0.0/21`
  - **Region 1 (us-east-1)**: `10.101.0.0 – 10.101.7.255`
  - **Region 2 (us-west-2)**: `10.101.8.0 – 10.101.15.255`

### **Management Account**
- **CIDR**: `10.102.0.0/21`
  - **Region 1 (us-east-1)**: `10.102.0.0 – 10.102.7.255`
  - **Region 2 (us-west-2)**: `10.102.8.0 – 10.102.15.255`

### **Prod Account**
- **CIDR**: `10.0.0.0/14`
  - **Region 1 (us-east-1)**: `10.0.0.0 – 10.1.255.255`
  - **Region 2 (us-west-2)**: `10.2.0.0 – 10.3.255.255`

### **Staging Account**
- **CIDR**: `10.4.0.0/14`
  - **Region 1 (us-east-1)**: `10.4.0.0 – 10.5.255.255`
  - **Region 2 (us-west-2)**: `10.6.0.0 – 10.7.255.255`

### **Dev Account**
- **CIDR**: `10.8.0.0/14`
  - **Region 1 (us-east-1)**: `10.8.0.0 – 10.9.255.255`
  - **Region 2 (us-west-2)**: `10.10.0.0 – 10.11.255.255`

### **Test Account**
- **CIDR**: `10.12.0.0/14`
  - **Region 1 (us-east-1)**: `10.12.0.0 – 10.13.255.255`
  - **Region 2 (us-west-2)**: `10.14.0.0 – 10.15.255.255`

### **Network Account**
- **CIDR**: `10.16.0.0/14`
  - **Region 1 (us-east-1)**: `10.16.0.0 – 10.17.255.255`
  - **Region 2 (us-west-2)**: `10.18.0.0 – 10.19.255.255`

```

For Cross account we will setup network account for the transit gateway account cross connections

# Network Account Plan (Transit Gateway)

## Purpose

The **Network Account** is dedicated to managing centralized networking infrastructure across all AWS accounts. This includes hosting the **Transit Gateway (TGW)** for cross-account and cross-region VPC connectivity.

---

## CIDR Allocation

To avoid overlap with other account CIDRs, the network account is allocated the next block after `10.12.0.0/14`.

- **CIDR Block**: `10.16.0.0/14`
- **IP Range**: `10.16.0.0` – `10.19.255.255`
- **Total IPs**: 262,144
- **Purpose**: Transit Gateway attachments, shared networking services, VPC flow logging, NAT, endpoints

---

## Subnet Layout (per Region)

| Subnet Purpose        | Availability Zone | CIDR Block     | IP Range               |
|-----------------------|-------------------|----------------|------------------------|
| Transit Gateway (TGW) | AZ1               | 10.16.0.0/24   | 10.16.0.0 – 10.16.0.255 |
| Transit Gateway (TGW) | AZ2               | 10.16.1.0/24   | 10.16.1.0 – 10.16.1.255 |
| Transit Gateway (TGW) | AZ3               | 10.16.2.0/24   | 10.16.2.0 – 10.16.2.255 |
| Management Services   | AZ1               | 10.16.3.0/24   | 10.16.3.0 – 10.16.3.255 |
| Management Services   | AZ2               | 10.16.4.0/24   | 10.16.4.0 – 10.16.4.255 |
| Management Services   | AZ3               | 10.16.5.0/24   | 10.16.5.0 – 10.16.5.255 |

---

## Services Hosted

- Transit Gateway (TGW) with VPC attachments from all other accounts
- NAT Gateways (optional)
- VPC Endpoints (S3, DynamoDB, etc.)
- Route 53 Resolver for centralized DNS
- CloudWatch metrics forwarding
- VPC Flow Logs to centralized S3
- Optional interface endpoints for shared tools

---

## Best Practices

- Deploy TGW attachments in 3 AZs for high availability
- Use separate route tables per attachment or environment
- Apply strict NACLs and Security Groups
- Enable flow logging for traffic visibility
- Consistently tag all resources (`Environment`, `Owner`, `Purpose`, etc.)

