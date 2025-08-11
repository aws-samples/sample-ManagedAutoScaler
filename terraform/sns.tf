# ===================================================================
# Aurora PostgreSQL Auto-Scaling System - SNS Notifications
# ===================================================================
# This file configures Amazon Simple Notification Service (SNS) to
# provide real-time alerts about auto-scaling events, system status
# changes, and error conditions. Notifications help operators monitor
# the system and respond to issues quickly.
#
# Notification Types:
# - Reader instance creation/deletion events
# - Scaling failures and capacity issues
# - EventBridge scheduler state changes
# - Error conditions and system alerts
# ===================================================================

# ===================================================================
# 📧 SNS TOPIC FOR AURORA SCALING ALERTS
# ===================================================================
# Central topic for all Aurora auto-scaling notifications
# This topic receives messages from both Lambda functions about
# scaling events, errors, and system state changes

resource "aws_sns_topic" "aurora_scaling_alerts" {
  name = "aurora-scaling-alerts"

  # ===================================================================
  # 🔐 ENCRYPTION CONFIGURATION
  # ===================================================================
  # Use AWS managed KMS key for SNS encryption
  # For enhanced security, consider using a customer-managed KMS key
  kms_master_key_id = "alias/aws/sns"

  # Alternative: Use customer-managed KMS key for enhanced control
  # kms_master_key_id = aws_kms_key.sns_encryption_key.arn

  # ===================================================================
  # 📋 TOPIC POLICY (Optional)
  # ===================================================================
  # Uncomment and customize if you need specific access controls
  # policy = jsonencode({
  #   Version = "2012-10-17"
  #   Statement = [
  #     {
  #       Sid    = "AllowLambdaPublish"
  #       Effect = "Allow"
  #       Principal = {
  #         AWS = aws_iam_role.lambda_role.arn
  #       }
  #       Action   = "sns:Publish"
  #       Resource = "*"
  #       Condition = {
  #         StringEquals = {
  #           "aws:SourceAccount" = data.aws_caller_identity.current.account_id
  #         }
  #       }
  #     }
  #   ]
  # })

  # ===================================================================
  # 🏷️ RESOURCE TAGGING
  # ===================================================================

  tags = {
    Name        = "Aurora AutoScaler Alerts Topic"
    Environment = var.environment
    Project     = "Aurora-AutoScaler"
    Purpose     = "Scaling-Notifications"
    MessageType = "Operational-Alerts"
  }
}

# ===================================================================
# 📬 EMAIL SUBSCRIPTION FOR NOTIFICATIONS
# ===================================================================
# Creates an email subscription to the SNS topic if an email address
# is provided. This allows operators to receive scaling alerts via email.

resource "aws_sns_topic_subscription" "aurora_email_subscription" {
  # Only create subscription if notification_email is provided and not default
  count = var.notification_email != "" && var.notification_email != "your-email@example.com" ? 1 : 0

  topic_arn = aws_sns_topic.aurora_scaling_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email

  # ===================================================================
  # 📧 EMAIL SUBSCRIPTION NOTES
  # ===================================================================
  # After Terraform creates this subscription:
  # 1. AWS will send a confirmation email to the specified address
  # 2. The recipient must click "Confirm subscription" in the email
  # 3. Only after confirmation will notifications be delivered
  # 4. The subscription will show as "PendingConfirmation" until confirmed
}


