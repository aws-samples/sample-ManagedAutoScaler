# ===================================================================
# Aurora PostgreSQL Auto-Scaling System - Dead Letter Queue (DLQ)
# ===================================================================
# This file implements a Dead Letter Queue (DLQ) system for capturing
# and analyzing failed Lambda function executions. The DLQ provides
# visibility into system failures and enables debugging of scaling
# issues without losing important error information.
#
# DLQ Benefits:
# - Captures failed Lambda executions for analysis
# - Prevents loss of critical error information
# - Enables debugging and troubleshooting
# - Supports operational monitoring and alerting
# - Encrypted storage for security compliance
# ===================================================================

# ===================================================================
# 📬 SQS DEAD LETTER QUEUE FOR LAMBDA FAILURES
# ===================================================================
# This SQS queue receives failed Lambda function executions from both
# the autoscale_up and downscale functions. Messages in this queue
# indicate system failures that require investigation.

resource "aws_sqs_queue" "lambda_dlq" {
  name = "aurora-autoscaler-dlq"

  # ===================================================================
  # ⏰ MESSAGE RETENTION CONFIGURATION
  # ===================================================================

  # How long messages are retained in the queue before automatic deletion
  # Configurable via variable to balance storage costs vs. debugging needs
  message_retention_seconds = var.dlq_message_retention_seconds

  # ===================================================================
  # 🔐 ENCRYPTION CONFIGURATION
  # ===================================================================

  # Enable server-side encryption using customer-managed KMS key
  # This ensures failed execution data is encrypted at rest
  kms_master_key_id = aws_kms_key.lambda_dlq_key.arn

  # Optional: Configure additional SQS settings
  # visibility_timeout_seconds = 300        # How long messages are hidden after being received
  # max_receive_count = 3                   # Maximum times a message can be received
  # delay_seconds = 0                       # Delay before new messages become visible
  # receive_wait_time_seconds = 0           # Long polling wait time

  # ===================================================================
  # 🏷️ RESOURCE TAGGING
  # ===================================================================

  tags = {
    Name        = "Aurora AutoScaler Dead Letter Queue"
    Environment = var.environment
    Project     = "Aurora-AutoScaler"
    Purpose     = "Failed-Lambda-Executions"
    MessageType = "Error-Analysis"
  }
}

# ===================================================================
# 🔐 KMS KEY FOR DLQ ENCRYPTION
# ===================================================================
# Customer-managed KMS key specifically for encrypting DLQ messages
# This provides enhanced security for potentially sensitive error data

resource "aws_kms_key" "lambda_dlq_key" {
  description = "KMS key for Aurora AutoScaler Dead Letter Queue encryption"

  # ===================================================================
  # 🔄 KEY LIFECYCLE CONFIGURATION
  # ===================================================================

  # Deletion window - provides recovery time if key deletion is requested
  deletion_window_in_days = 7

  # Enable automatic key rotation for enhanced security
  enable_key_rotation = true

  # ===================================================================
  # 🔒 KEY POLICY - MULTI-SERVICE ACCESS
  # ===================================================================
  # This policy allows both SQS and Lambda services to use the key
  # while maintaining security boundaries

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # ===================================================================
      # ROOT ACCOUNT PERMISSIONS
      # ===================================================================
      # Full administrative access for key management
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },

      # ===================================================================
      # LAMBDA SERVICE PERMISSIONS
      # ===================================================================
      # Lambda needs to encrypt messages when sending to DLQ
      {
        Sid    = "Allow Lambda service to use the key"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",        # Decrypt messages when reading from DLQ
          "kms:GenerateDataKey" # Generate keys for message encryption
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },

      # ===================================================================
      # SQS SERVICE PERMISSIONS
      # ===================================================================
      # SQS needs to encrypt/decrypt messages in the queue
      {
        Sid    = "Allow SQS service to use the key"
        Effect = "Allow"
        Principal = {
          Service = "sqs.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",        # Decrypt messages for delivery
          "kms:GenerateDataKey" # Generate keys for message encryption
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })

  # ===================================================================
  # 🏷️ RESOURCE TAGGING
  # ===================================================================

  tags = {
    Name        = "Aurora AutoScaler DLQ KMS Key"
    Environment = var.environment
    Project     = "Aurora-AutoScaler"
    Purpose     = "DLQ-Message-Encryption"
    KeyType     = "Customer-Managed"
    Rotation    = "Enabled"
  }
}

# ===================================================================
# 🏷️ KMS KEY ALIAS FOR OPERATIONAL CONVENIENCE
# ===================================================================
# Human-readable alias for the DLQ KMS key

resource "aws_kms_alias" "lambda_dlq_key_alias" {
  name          = "alias/aurora-autoscaler-dlq"
  target_key_id = aws_kms_key.lambda_dlq_key.key_id
}


