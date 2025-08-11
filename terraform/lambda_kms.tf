# ===================================================================
# Aurora PostgreSQL Auto-Scaling System - Lambda KMS Encryption
# ===================================================================
# This file implements KMS (Key Management Service) encryption for
# Lambda environment variables to protect sensitive configuration data
# at rest. This is a security best practice that ensures sensitive
# information like database cluster IDs and SNS topic ARNs are encrypted.
#
# Security Benefits:
# - Environment variables encrypted at rest using customer-managed KMS key
# - Key rotation enabled for enhanced security
# - Least privilege access controls for key usage
# - Audit trail for all key operations via CloudTrail
# ===================================================================

# ===================================================================
# 🔐 KMS KEY FOR LAMBDA ENVIRONMENT VARIABLE ENCRYPTION
# ===================================================================
# Customer-managed KMS key specifically for encrypting Lambda environment
# variables. This provides better security and control compared to
# AWS-managed keys.

resource "aws_kms_key" "lambda_env_key" {
  description = "KMS key for Aurora AutoScaler Lambda environment variable encryption"

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
  # necessary access for Lambda functions and administrative operations

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
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region
          }
        }
      },

      # ===================================================================
      # LAMBDA SERVICE PERMISSIONS
      # ===================================================================
      # Allows Lambda service to decrypt environment variables and create grants
      # Scoped to the specific account for security
      {
        Sid    = "Allow Lambda service to use the key"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",         # Decrypt environment variables at runtime
          "kms:GenerateDataKey", # Generate data keys for encryption
          "kms:CreateGrant"      # Create grants for Lambda execution role
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            # Restrict to Lambda functions in this account only
            "aws:SourceAccount"   = data.aws_caller_identity.current.account_id
            "aws:RequestedRegion" = var.region
          }
          # Only allow access from Aurora Lambda functions
          StringLike = {
            "aws:SourceArn" = "arn:aws:lambda:${var.region}:${data.aws_caller_identity.current.account_id}:function:aurora-*"
          }
        }
      },

      # ===================================================================
      # LAMBDA EXECUTION ROLE PERMISSIONS
      # ===================================================================
      # Allow the Lambda execution role to use the key
      {
        Sid    = "Allow Lambda execution role to use the key"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.lambda_role.arn
        }
        Action = [
          "kms:Decrypt",         # Decrypt environment variables
          "kms:GenerateDataKey", # Generate data keys for encryption
          "kms:CreateGrant"      # Create grants for key usage
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
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
    Name        = "Aurora AutoScaler Lambda Environment Encryption Key"
    Environment = var.environment
    Project     = "Aurora-AutoScaler"
    Purpose     = "Lambda Environment Variable Encryption"
    KeyType     = "Customer-Managed"
    Rotation    = "Enabled"
  }
}

# ===================================================================
# 🏷️ KMS KEY ALIAS FOR EASY REFERENCE
# ===================================================================
# Creates a human-readable alias for the KMS key, making it easier
# to reference in other resources and for operational purposes

resource "aws_kms_alias" "lambda_env_key_alias" {
  name          = "alias/aurora-lambda-env-encryption"
  target_key_id = aws_kms_key.lambda_env_key.key_id
}

# ===================================================================
# 🔐 IAM POLICY FOR LAMBDA KMS ACCESS
# ===================================================================
# This policy grants the Lambda execution role permission to use
# the KMS key for decrypting environment variables

resource "aws_iam_role_policy" "lambda_kms_policy" {
  name = "aurora-lambda-kms-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowKMSDecryption"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",         # Decrypt environment variables
          "kms:GenerateDataKey", # Generate data keys for encryption operations
          "kms:CreateGrant"      # Create grants for key usage
        ]
        Resource = aws_kms_key.lambda_env_key.arn
        Condition = {
          StringEquals = {
            # Restrict operations to the deployment region
            "aws:RequestedRegion" = var.region
            # Ensure operations are from our account only
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

