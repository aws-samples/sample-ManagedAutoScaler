# ===================================================================
# Aurora PostgreSQL Auto-Scaling System - EventBridge Scheduler KMS
# ===================================================================
# This file implements KMS (Key Management Service) encryption for
# EventBridge Scheduler to protect schedule data and payloads at rest.
# This enhances security posture by using Customer Managed Keys (CMK)
# instead of AWS managed keys.
#
# Security Benefits:
# - Schedule data encrypted at rest using customer-managed KMS key
# - Key rotation enabled for enhanced security
# - Least privilege access controls for key usage
# - Audit trail for all key operations via CloudTrail
# - Compliance with enterprise security requirements
# ===================================================================

# ===================================================================
# 🔐 KMS KEY FOR EVENTBRIDGE SCHEDULER ENCRYPTION
# ===================================================================
# Customer-managed KMS key specifically for encrypting EventBridge
# Scheduler data. This provides better security and control compared to
# AWS-managed keys.

resource "aws_kms_key" "scheduler_key" {
  description = "KMS key for Aurora AutoScaler EventBridge Scheduler encryption"

  # ===================================================================
  # 🔄 KEY ROTATION AND LIFECYCLE
  # ===================================================================

  # Deletion window - time before key is permanently deleted if deletion is requested
  # 7 days is the minimum, provides time to recover from accidental deletion
  deletion_window_in_days = 7

  # Enable automatic key rotation annually for enhanced security
  # AWS will create new key material while keeping the same key ID
  enable_key_rotation = true

  # ===================================================================
  # 🔒 KEY POLICY - DEFINES WHO CAN USE THE KEY
  # ===================================================================
  # This policy follows the principle of least privilege while allowing
  # necessary access for EventBridge Scheduler and administrative operations

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # ===================================================================
      # ROOT ACCOUNT PERMISSIONS
      # ===================================================================
      # Allows the AWS account root user full access to the key
      # This is required for key management and administrative operations
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
      # EVENTBRIDGE SCHEDULER SERVICE PERMISSIONS
      # ===================================================================
      # Allows EventBridge Scheduler service to encrypt/decrypt schedule data
      # Scoped to the specific account for security
      {
        Sid    = "Allow EventBridge Scheduler service to use the key"
        Effect = "Allow"
        Principal = {
          Service = "scheduler.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",          # Encrypt schedule data
          "kms:Decrypt",          # Decrypt schedule data at runtime
          "kms:ReEncrypt*",       # Re-encrypt data with new key material
          "kms:GenerateDataKey*", # Generate data keys for encryption
          "kms:DescribeKey",      # Describe key properties
          "kms:CreateGrant",      # Create grants for service operations
          "kms:ListGrants",       # List existing grants
          "kms:RevokeGrant"       # Revoke grants when no longer needed
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            # Restrict to EventBridge Scheduler in this account only
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },

      # ===================================================================
      # LAMBDA EXECUTION ROLE PERMISSIONS
      # ===================================================================
      # Allows Lambda execution role to use the key for scheduler operations
      # This is needed when Lambda functions update scheduler state
      {
        Sid    = "Allow Lambda execution role to use the key"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.lambda_role.arn
        }
        Action = [
          "kms:Decrypt",        # Decrypt when reading schedule data
          "kms:DescribeKey",    # Describe key properties
          "kms:GenerateDataKey" # Generate data keys for operations
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            # Restrict to operations in the deployment region
            "aws:RequestedRegion" = var.region
          }
        }
      }
    ]
  })

  # ===================================================================
  # 🏷️ RESOURCE TAGGING
  # ===================================================================

  tags = {
    Name        = "Aurora AutoScaler EventBridge Scheduler Encryption Key"
    Environment = var.environment
    Project     = "Aurora-AutoScaler"
    Purpose     = "EventBridge-Scheduler-Encryption"
    KeyType     = "Customer-Managed"
    Rotation    = "Enabled"
    Service     = "EventBridge-Scheduler"
  }
}

# ===================================================================
# 🏷️ KMS KEY ALIAS FOR EASY REFERENCE
# ===================================================================
# Creates a human-readable alias for the KMS key, making it easier
# to reference in other resources and for operational purposes

resource "aws_kms_alias" "scheduler_key_alias" {
  name          = "alias/aurora-autoscaler-scheduler"
  target_key_id = aws_kms_key.scheduler_key.key_id
}

# ===================================================================
# 🔐 IAM POLICY FOR LAMBDA SCHEDULER KMS ACCESS
# ===================================================================
# This policy grants the Lambda execution role permission to use
# the KMS key for EventBridge Scheduler operations

resource "aws_iam_role_policy" "lambda_scheduler_kms_policy" {
  name = "aurora-lambda-scheduler-kms-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowSchedulerKMSOperations"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",        # Decrypt schedule data when reading
          "kms:DescribeKey",    # Describe key properties
          "kms:GenerateDataKey" # Generate data keys for operations
        ]
        Resource = aws_kms_key.scheduler_key.arn
        Condition = {
          StringEquals = {
            # Restrict operations to the deployment region
            "aws:RequestedRegion" = var.region
          }
        }
      }
    ]
  })
}
