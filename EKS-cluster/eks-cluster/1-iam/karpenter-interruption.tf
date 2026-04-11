# ------------------------------------------------------------------------------
# Karpenter Interruption Queue
#
# Karpenter watches this SQS queue for EC2 interruption events and proactively
# drains nodes before they are terminated. Without this, pods on spot nodes
# get hard-killed with no graceful termination.
#
# EventBridge rules feed four event types into the queue:
#   1. Spot interruption warnings      (2-min warning before termination)
#   2. Rebalance recommendations       (suggestion to move off at-risk capacity)
#   3. Instance state-change notices   (terminated/stopped — confirm eviction)
#   4. AWS Health scheduled changes    (planned maintenance windows)
# ------------------------------------------------------------------------------

resource "aws_sqs_queue" "karpenter_interruption" {
  name                      = "${var.cluster_name}-karpenter-interruption"
  message_retention_seconds = 300 # events are acted on quickly; no need to retain long
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue_policy" "karpenter_interruption" {
  queue_url = aws_sqs_queue.karpenter_interruption.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEventBridgeToSendMessages"
        Effect = "Allow"
        Principal = {
          Service = ["events.amazonaws.com", "sqs.amazonaws.com"]
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.karpenter_interruption.arn
      }
    ]
  })
}

# ── EventBridge Rules ─────────────────────────────────────────────────────────

resource "aws_cloudwatch_event_rule" "spot_interruption" {
  name        = "${var.cluster_name}-karpenter-spot-interruption"
  description = "Karpenter: EC2 Spot Instance Interruption Warning"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Spot Instance Interruption Warning"]
  })
}

resource "aws_cloudwatch_event_target" "spot_interruption" {
  rule = aws_cloudwatch_event_rule.spot_interruption.name
  arn  = aws_sqs_queue.karpenter_interruption.arn
}

resource "aws_cloudwatch_event_rule" "rebalance_recommendation" {
  name        = "${var.cluster_name}-karpenter-rebalance"
  description = "Karpenter: EC2 Instance Rebalance Recommendation"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance Rebalance Recommendation"]
  })
}

resource "aws_cloudwatch_event_target" "rebalance_recommendation" {
  rule = aws_cloudwatch_event_rule.rebalance_recommendation.name
  arn  = aws_sqs_queue.karpenter_interruption.arn
}

resource "aws_cloudwatch_event_rule" "instance_state_change" {
  name        = "${var.cluster_name}-karpenter-state-change"
  description = "Karpenter: EC2 Instance State-change Notification"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance State-change Notification"]
    detail = {
      state = ["terminated", "stopped", "stopping"]
    }
  })
}

resource "aws_cloudwatch_event_target" "instance_state_change" {
  rule = aws_cloudwatch_event_rule.instance_state_change.name
  arn  = aws_sqs_queue.karpenter_interruption.arn
}

resource "aws_cloudwatch_event_rule" "health_event" {
  name        = "${var.cluster_name}-karpenter-health"
  description = "Karpenter: AWS Health scheduled maintenance events"

  event_pattern = jsonencode({
    source      = ["aws.health"]
    detail-type = ["AWS Health Event"]
  })
}

resource "aws_cloudwatch_event_target" "health_event" {
  rule = aws_cloudwatch_event_rule.health_event.name
  arn  = aws_sqs_queue.karpenter_interruption.arn
}
