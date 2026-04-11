#!/usr/bin/env bash
# Drain Karpenter-managed nodes gracefully before tearing down an EKS cluster.
#
# Why this exists:
#   Karpenter owns the NodePool → NodeClaim → EC2 reconcile loop. If you
#   terraform-destroy the Karpenter helm release (or the EKS cluster itself)
#   while NodeClaims still exist, the controller pod dies before it can
#   terminate its instances. Terraform removes the helm release, Karpenter
#   state lives in etcd, etcd goes with the control plane — and the EC2s
#   become orphans that keep running (and billing) with nothing to manage
#   them.
#
#   The fix is to drain *while Karpenter is still alive*: delete the
#   NodePool CRs (and any stragglers as NodeClaim CRs) so Karpenter sees
#   its fleet is no longer needed and terminates each EC2 itself, which is
#   the only teardown path that cleanly releases the instance profile,
#   detaches ENIs, etc.
#
# Usage:
#   ./scripts/drain-karpenter-nodes.sh <cluster_name> [role_arn]
#
#   Env overrides:
#     AWS_REGION           default: us-west-2
#     AWS_ASSUME_ROLE_ARN  default: unset. If set (or passed as arg 2), the
#                          script assume-roles before calling AWS APIs.
#                          Does NOT affect kubectl — configure that
#                          yourself via `aws eks update-kubeconfig` first.
#     TIMEOUT_SECONDS      default: 600 (how long to wait for EC2s to terminate)
#     POLL_INTERVAL        default: 15  (seconds between AWS poll checks)
#
# Prerequisites:
#   - kubectl context pointing at the cluster you intend to drain.
#     The script will refuse to proceed if it can't reach the API server.
#   - AWS credentials (or an assume-role target) with permission to
#     describe and terminate EC2 instances in the cluster region.
#
# What it does NOT do:
#   - Does not delete your application workloads. Scale them down first if
#     you care about clean shutdown; Karpenter will consolidate and
#     eventually drain nodes either way, but graceful app shutdown is on
#     you.
#   - Does not touch the Karpenter helm release itself. After this script
#     reports success, the helm release is safe to destroy because there
#     are no NodeClaims left for it to manage.

set -euo pipefail

# ── Args & env ──────────────────────────────────────────────────────────────
CLUSTER_NAME="${1:-}"
if [[ -z "$CLUSTER_NAME" ]]; then
  echo "ERROR: cluster name is required" >&2
  echo "Usage: $0 <cluster_name> [role_arn]" >&2
  exit 2
fi

if [[ -n "${2:-}" ]]; then
  export AWS_ASSUME_ROLE_ARN="$2"
fi

REGION="${AWS_REGION:-us-west-2}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-600}"
POLL_INTERVAL="${POLL_INTERVAL:-15}"

echo "=== drain-karpenter-nodes ==="
echo "  cluster    = $CLUSTER_NAME"
echo "  region     = $REGION"
echo "  timeout    = ${TIMEOUT_SECONDS}s"
echo "  assume role = ${AWS_ASSUME_ROLE_ARN:-<none, using default creds>}"
echo ""

# ── Step 1: verify kubectl can reach the cluster ────────────────────────────
echo "[1/5] Verifying kubectl context..."
if ! kubectl version --request-timeout=5s >/dev/null 2>&1; then
  echo "ERROR: kubectl cannot reach the cluster API. Run:" >&2
  echo "  aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION" >&2
  exit 1
fi
CONTEXT=$(kubectl config current-context 2>/dev/null || echo "<unknown>")
echo "      current context: $CONTEXT"

# ── Step 2: assume role (for AWS CLI only, not kubectl) ─────────────────────
if [[ -n "${AWS_ASSUME_ROLE_ARN:-}" ]]; then
  echo "[2/5] Assuming role ${AWS_ASSUME_ROLE_ARN}..."
  CREDS=$(aws sts assume-role \
    --role-arn "$AWS_ASSUME_ROLE_ARN" \
    --role-session-name "drain-karpenter-nodes" \
    --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
    --output text)
  export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | awk '{print $1}')
  export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | awk '{print $2}')
  export AWS_SESSION_TOKEN=$(echo "$CREDS" | awk '{print $3}')
else
  echo "[2/5] No AWS_ASSUME_ROLE_ARN set, using default credentials."
fi

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
echo "      AWS account: $ACCOUNT"

# ── Step 3: delete NodePool CRs ─────────────────────────────────────────────
echo "[3/5] Deleting NodePool resources..."
if kubectl get crd nodepools.karpenter.sh >/dev/null 2>&1; then
  NODEPOOLS=$(kubectl get nodepool -o name 2>/dev/null || true)
  if [[ -n "$NODEPOOLS" ]]; then
    echo "$NODEPOOLS" | while read -r np; do
      echo "      deleting $np"
      kubectl delete "$np" --wait=false --ignore-not-found
    done
  else
    echo "      no NodePool resources found"
  fi
else
  echo "      nodepools.karpenter.sh CRD not installed (Karpenter already gone?)"
fi

# ── Step 4: delete any lingering NodeClaim CRs as belt-and-braces ───────────
echo "[4/5] Deleting NodeClaim resources (belt-and-braces)..."
if kubectl get crd nodeclaims.karpenter.sh >/dev/null 2>&1; then
  NODECLAIMS=$(kubectl get nodeclaim -o name 2>/dev/null || true)
  if [[ -n "$NODECLAIMS" ]]; then
    echo "$NODECLAIMS" | while read -r nc; do
      echo "      deleting $nc"
      kubectl delete "$nc" --wait=false --ignore-not-found
    done
  else
    echo "      no NodeClaim resources found"
  fi
else
  echo "      nodeclaims.karpenter.sh CRD not installed"
fi

# ── Step 5: poll AWS until Karpenter-tagged instances in this cluster are gone ──
echo "[5/5] Waiting up to ${TIMEOUT_SECONDS}s for Karpenter EC2 instances to terminate..."
DEADLINE=$(( $(date +%s) + TIMEOUT_SECONDS ))

while true; do
  INSTANCES=$(aws ec2 describe-instances --region "$REGION" \
    --filters \
      "Name=tag:karpenter.sh/nodepool,Values=*" \
      "Name=tag:karpenter.k8s.aws/cluster,Values=${CLUSTER_NAME}" \
      "Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down" \
    --query 'Reservations[].Instances[].InstanceId' \
    --output text 2>/dev/null || true)

  if [[ -z "$INSTANCES" ]]; then
    echo ""
    echo "SUCCESS: no Karpenter-tagged instances remain for cluster '$CLUSTER_NAME' in $REGION."
    echo "The Karpenter helm release is now safe to destroy."
    exit 0
  fi

  COUNT=$(echo "$INSTANCES" | wc -w | tr -d ' ')
  NOW=$(date +%s)
  REMAINING=$(( DEADLINE - NOW ))

  if (( REMAINING <= 0 )); then
    echo ""
    echo "TIMEOUT: ${COUNT} Karpenter-tagged instance(s) still present after ${TIMEOUT_SECONDS}s:" >&2
    echo "$INSTANCES" | tr ' ' '\n' | sed 's/^/  /' >&2
    echo "" >&2
    echo "Diagnose why Karpenter is not terminating them:" >&2
    echo "  kubectl -n karpenter logs deploy/karpenter" >&2
    echo "  kubectl get nodeclaim" >&2
    echo "" >&2
    echo "Or force-terminate via AWS CLI (last resort — leaks instance profiles):" >&2
    echo "  aws ec2 terminate-instances --region $REGION --instance-ids $INSTANCES" >&2
    exit 1
  fi

  echo "      still $COUNT instance(s) present (${REMAINING}s remaining), waiting ${POLL_INTERVAL}s..."
  sleep "$POLL_INTERVAL"
done
