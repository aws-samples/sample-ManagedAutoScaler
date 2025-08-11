# ===================================================================
# Aurora PostgreSQL Auto-Scaling System - EventBridge Scheduler
# ===================================================================
# This file configures EventBridge Scheduler to trigger the downscale
# Lambda function every minute for continuous CPU monitoring and cost
# optimization through automatic reader removal when utilization is low.
#
# Security Enhancement: Uses Customer Managed KMS key for encryption
# at rest, providing enhanced security posture and compliance.
#
# Scheduler Flow:
# Every Minute → EventBridge Scheduler → Downscale Lambda → CPU Analysis → Remove Reader (if needed)
# ===================================================================

# ===================================================================
# ⏰ EVENTBRIDGE SCHEDULER FOR CPU MONITORING
# ===================================================================
# This schedule triggers the downscale Lambda function every minute to:
# 1. Monitor CPU utilization across all Aurora readers
# 2. Remove readers when CPU is consistently below threshold
# 3. Disable itself when no Lambda-created readers remain (cost optimization)
# 4. Uses Customer Managed KMS key for enhanced security

resource "aws_scheduler_schedule" "downscale_schedule" {
  # Schedule identification
  name        = "aurora-cpu-monitor-every-minute"
  group_name  = "default" # Using default schedule group
  description = "Monitor Aurora CPU utilization and downscale reader instances when utilization is low"

  # ===================================================================
  # 🔐 ENCRYPTION CONFIGURATION
  # ===================================================================
  # Use Customer Managed KMS key for encrypting schedule data at rest
  # This enhances security posture compared to AWS managed keys
  kms_key_arn = aws_kms_key.scheduler_key.arn

  # ===================================================================
  # 📅 SCHEDULE CONFIGURATION
  # ===================================================================

  # Initial state is DISABLED - the autoscale_up function will enable it
  # when it creates new readers. This prevents unnecessary executions
  # when no Lambda-created readers exist.
  state = "DISABLED"

  # Schedule expression - runs every minute for responsive monitoring
  # Format: rate(value unit) where unit can be minute, minutes, hour, hours, day, days
  schedule_expression = "rate(1 minute)"

  # Set timezone to UTC for consistent behavior across regions
  schedule_expression_timezone = "UTC"

  # ===================================================================
  # ⏱️ FLEXIBLE TIME WINDOW CONFIGURATION
  # ===================================================================
  # Controls when the schedule can execute within each minute

  flexible_time_window {
    # Mode "OFF" means execute at the exact scheduled time
    # Alternative: "FLEXIBLE" allows execution within a time window
    mode = "OFF"

    # If mode were "FLEXIBLE", you could specify:
    # maximum_window_in_minutes = 5  # Allow execution within 5-minute window
  }

  # ===================================================================
  # 🎯 TARGET CONFIGURATION
  # ===================================================================
  # Defines the Lambda function to invoke and execution parameters

  target {
    # Target Lambda function ARN
    arn = aws_lambda_function.downscale.arn

    # IAM role for EventBridge Scheduler to assume when invoking the function
    # This role must have permissions to invoke the Lambda function
    role_arn = aws_iam_role.eventbridge_scheduler_role.arn

    # Input payload sent to the Lambda function
    # Empty JSON object since the function doesn't require specific input
    # The function will determine what to do based on current cluster state
    input = jsonencode({})

    # Configure retry policy for failed invocations
    retry_policy {
      maximum_retry_attempts       = 185
      maximum_event_age_in_seconds = 86400
    }

    # Optional: Configure dead letter queue for failed invocations
    # dead_letter_config {
    #   arn = aws_sqs_queue.scheduler_dlq.arn
    # }
  }

  # ===================================================================
  # 🔄 LIFECYCLE MANAGEMENT
  # ===================================================================
  # This lifecycle rule prevents Terraform from overriding state changes
  # made by the Lambda functions during runtime

  lifecycle {
    # Ignore changes to the state attribute
    # The autoscale_up function enables this schedule when creating readers
    # The downscale function disables this schedule when no readers remain
    ignore_changes = [state]
  }

  # Note: EventBridge Scheduler does not support tags at this time
  # Resource identification relies on name and description fields
}

# ===================================================================
# 🔐 LAMBDA PERMISSION FOR SCHEDULER INVOCATION
# ===================================================================
# Grants EventBridge Scheduler permission to invoke the downscale Lambda function

resource "aws_lambda_permission" "allow_scheduler_to_invoke_downscale" {
  statement_id  = "AllowSchedulerInvokeDownscale"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.downscale.function_name
  principal     = "scheduler.amazonaws.com"

  # Source ARN restriction - only this specific schedule can invoke the function
  source_arn = aws_scheduler_schedule.downscale_schedule.arn
}


