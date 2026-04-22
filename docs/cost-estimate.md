# Hourly Cost Estimate — RKE2 and EKS Labs

All prices are on-demand **us-west-2** list prices (Apr 2026). Both labs share a
common VPC/VPN layer; cluster stacks are mutually exclusive (only one runs at a
time, per the vCPU-quota constraint noted in `CLAUDE.md`).

Data-transfer and usage-driven charges (NAT data processing, VPC-endpoint data
processing, NLB LCUs, CloudWatch Logs ingest, S3 PUTs, inter-AZ traffic, EBS
snapshots) are **excluded** — they're generally small in a lab but vary.

---

## Shared / always-on (Common)

| Resource | Qty | Unit $/hr | $/hr |
|---|---:|---:|---:|
| OpenVPN — `t3.small` (`openvpn/devvpn/variables.tf:41`) | 1 | 0.0208 | 0.0208 |
| OpenVPN root 20 GB gp3 (`openvpn/devvpn/variables.tf:47`) | 20 GB | 0.08/GB-mo | 0.0022 |
| OpenVPN Elastic IP (public IPv4 is metered) | 1 | 0.005 | 0.0050 |
| NAT Gateway — `single_nat_gateway = true` (`VPC/dev/variables.tf:86`) | 1 | 0.045 | 0.0450 |
| Interface VPC endpoints × 3 AZs (6 services — see below) | 18 ENIs | 0.010 | 0.1800 |
| **Common subtotal** |  |  | **~$0.253 /hr** |

**Interface endpoint services** (`VPC/dev/variables.tf:75`): `ecr.api`, `ecr.dkr`,
`ssm`, `ssmmessages`, `ec2messages`, `sts`. Gateway endpoints (`s3`, `dynamodb`)
are free. Each interface endpoint places one ENI per AZ (3 AZs) per
`VPC/modules/vpc/mainf.tf:116`.

> **Biggest single line item in the common layer.** Because the lab also runs a
> NAT gateway, these endpoints are largely redundant for egress. Setting
> `enable_vpc_endpoints = false` in `VPC/dev/terraform.tfvars` drops the common
> baseline from ~$0.25/hr to **~$0.07/hr** with no functional loss for this lab.
> The endpoints only pay off when trying to *eliminate* NAT (Lambda-in-VPC,
> air-gapped workloads).

### If 8 interface endpoints are actually deployed

The Terraform in this repo declares **6 interface** services (+2 free gateway =
8 total objects). If the live VPC actually has 8 *interface* endpoints (e.g.
`logs`, `kms`, `ec2`, `elasticloadbalancing` added out-of-band), recompute:

| Interface endpoints | $/hr (× 3 AZs) | $/mo |
|---:|---:|---:|
| 6 (repo default) | 0.18 | 131 |
| 8 | 0.24 | 175 |

---

## RKE2 lab (on top of common)

| Resource | Qty | Unit $/hr | $/hr |
|---|---:|---:|---:|
| Nodes — `t3a.large` (3 servers + 3 agents, `RKE-cluster/dev-cluster/ec2/main.tf:8,12`) | 6 | 0.0752 | 0.4512 |
| EBS gp3 root (~50 GB Ubuntu 22.04 default × 6) | 300 GB | 0.08/GB-mo | 0.0329 |
| Traefik NLB (provisioned by `deployments/rke-apps/1-infrastructure/`) | ~1 | ~0.025 | 0.0250 |
| S3 etcd backups + 1 Secrets Manager token (`dev-rke2-token`) | — | — | ~0.001 |
| **RKE2 subtotal** |  |  | **~$0.510 /hr** |
| **RKE2 lab total (common + RKE2)** |  |  | **≈ $0.76 /hr** (~$554/mo) |

Node count is fixed, so the RKE2 total has no meaningful variability.

---

## EKS lab (on top of common)

| Resource | Qty | Unit $/hr | $/hr |
|---|---:|---:|---:|
| EKS control plane (`EKS-cluster/eks-cluster/2-cluster/main.tf:30`) | 1 | 0.10 | 0.1000 |
| Bootstrap managed node group — `t3.medium` × 3 (`2-cluster/variables.tf:82,88`) | 3 | 0.0416 | 0.1248 |
| EBS gp3 50 GB × 3 (`3-karpenter/node-pools.tf:39`) | 150 GB | 0.08/GB-mo | 0.0164 |
| Traefik NLB (`deployments/eks-apps/1-infrastructure/`) | ~1 | ~0.025 | 0.0250 |
| KMS CMK for EKS secrets (`1-iam/kms.tf`) | 1 | $1/mo | 0.0014 |
| **EKS subtotal (no Karpenter nodes running)** |  |  | **~$0.267 /hr** |
| **EKS lab idle total (common + EKS)** |  |  | **≈ $0.52 /hr** (~$380/mo) |

### Karpenter variable cost

Both NodePools are capped at **16 vCPU / 64 GiB**
(`EKS-cluster/eks-cluster/3-karpenter/node-pools.tf:56–156`) across
`m5a.large` / `m5a.xlarge`.

| Scenario | Additional $/hr |
|---|---:|
| 1× `m5a.large` on-demand | +0.086 |
| 1× `m5a.large` spot (~70% off) | +0.026 |
| NodePool at cap, all on-demand (e.g. 2× `m5a.xlarge`) | +0.344 |
| NodePool at cap, all spot | +0.103 |

Under a real workload the EKS lab lands **≈ $0.55–$0.90 /hr**, up to
**≈ $0.86 /hr** worst case at the pool cap on-demand.

---

## Summary

| Lab | Idle baseline | Realistic with workload |
|---|---:|---:|
| RKE2 | **~$0.76 /hr** | same (fixed node count) |
| EKS | **~$0.52 /hr** | **~$0.55 – $0.90 /hr** |

## Cost-reduction quick wins

1. **Disable interface VPC endpoints** — saves ~$0.18/hr (~$131/mo). NAT
   gateway already provides egress to all the target services. Set
   `enable_vpc_endpoints = false` in `VPC/dev/terraform.tfvars`.
2. **Tear down the lab when not in use.** Baseline is ~$0.25/hr even with no
   cluster; with a cluster up it's $0.5–0.8/hr. A day's usage is $6–20; a full
   month idle is ~$380–560.
3. **Prefer the EKS lab for ad-hoc work** — its bootstrap node group is only
   3× `t3.medium` vs. RKE2's 6× `t3a.large`, and Karpenter scales to zero when
   workloads are gone.
4. **Favor spot in Karpenter NodePools** — the `spot-interruptible` NodePool
   already exists; prefer it for non-critical workloads (~70% off on-demand).
5. **NAT gateway is already cost-optimized** (`single_nat_gateway = true`).
   No action needed.
