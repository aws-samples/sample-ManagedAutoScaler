# ===================================================================
# Aurora PostgreSQL Auto-Scaling System - EventBridge Configuration
# ===================================================================
# This file configures EventBridge to capture RDS insufficient capacity
# events and trigger the autoscale_up Lambda function. The system uses
# precise event pattern matching to ensure only relevant RDS events
# trigger scaling actions.
#
# Event Flow:
# RDS Insufficient Capacity → EventBridge Rule → Lambda Function → New Reader
# ===================================================================

# ===================================================================
# 🎯 EVENTBRIDGE RULE FOR RDS INSUFFICIENT CAPACITY EVENTS
# ===================================================================
# This rule captures RDS-EVENT-0031 (insufficient capacity) events
# and triggers the autoscale_up Lambda function to create new readers

resource "aws_cloudwatch_event_rule" "insufficient_capacity" {
  name        = "rds-insufficient-capacity"
  description = "Trigger AutoScale Lambda on RDS-EVENT-0031 insufficient capacity events"

  # Event pattern for precise matching of RDS-EVENT-0031 insufficient capacity events
  # This pattern was refined based on actual EventBridge event structure analysis
  # from Lambda logs showing the exact JSON format received by the function
  event_pattern = jsonencode({
    # Event source - all RDS events come from aws.rds
    source = ["aws.rds"]

    # Event type - specifically RDS DB Instance events
    detail-type = ["RDS DB Instance Event"]

    # Event details for precise filtering
    detail = {
      # EventID - the official RDS event code for insufficient capacity
      # This is the most reliable way to identify RDS-EVENT-0031 events
      EventID = ["RDS-EVENT-0031"]

      # Source identifier pattern - only events from our target cluster
      # This ensures we only respond to events from the cluster we're scaling
      SourceIdentifier = [{
        prefix = var.db_cluster_id
      }]
    }
  })

  # Enable the rule by default
  state = "ENABLED"

  tags = {
    Name        = "Aurora AutoScaler EventBridge Rule"
    Environment = var.environment
    Project     = "Aurora-AutoScaler"
    Purpose     = "RDS-Event-Capture"
    EventType   = "RDS-EVENT-0031"
    Trigger     = "Insufficient-Capacity"
  }
}

# ===================================================================
# 🎯 EVENTBRIDGE TARGET CONFIGURATION
# ===================================================================
# Defines the Lambda function as the target for the EventBridge rule
# When the rule matches an event, it will invoke the autoscale_up function

resource "aws_cloudwatch_event_target" "autoscale_target" {
  rule      = aws_cloudwatch_event_rule.insufficient_capacity.name
  target_id = "AutoScaleLambda"
  arn       = aws_lambda_function.autoscale_up.arn

  # Optional: Add input transformation to pass specific event data to Lambda
  # Currently using default event structure, but could be customized if needed
}

# ===================================================================
# 🔐 LAMBDA PERMISSION FOR EVENTBRIDGE INVOCATION
# ===================================================================
# Grants EventBridge permission to invoke the autoscale_up Lambda function
# This is required for EventBridge to successfully trigger the function

resource "aws_lambda_permission" "allow_eventbridge_to_invoke_autoscale" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.autoscale_up.function_name
  principal     = "events.amazonaws.com"

  # Source ARN restriction - only this specific EventBridge rule can invoke the function
  source_arn = aws_cloudwatch_event_rule.insufficient_capacity.arn
}


