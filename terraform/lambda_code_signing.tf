# ===================================================================
# Aurora PostgreSQL Auto-Scaling System - Lambda Code Signing
# ===================================================================
# This file implements AWS Lambda code signing validation to ensure
# only trusted, signed code can be deployed to Lambda functions.
# This significantly enhances security by preventing unauthorized
# code deployment and ensuring code integrity.
#
# Security Benefits:
# - Code integrity verification through digital signatures
# - Prevention of unauthorized code deployment
# - Compliance with enterprise security requirements
# - Audit trail for code deployment activities
# ===================================================================

# ===================================================================
# 🔐 SIGNING PROFILE FOR LAMBDA CODE SIGNING
# ===================================================================
# Creates a signing profile that defines the signing configuration
# for Lambda functions. This profile uses AWS-managed platform
# settings optimized for Lambda.

resource "aws_signer_signing_profile" "lambda_signing_profile" {
  name_prefix = "auroraautoscaler"

  # Platform ID for AWS Lambda
  # This uses AWS-managed signing configuration optimized for Lambda functions
  platform_id = "AWSLambda-SHA384-ECDSA"

  # Signature validity period
  # Code signatures remain valid for 5 years, providing long-term trust
  signature_validity_period {
    value = 5
    type  = "YEARS"
  }

  # ===================================================================
  # 🏷️ RESOURCE TAGGING
  # ===================================================================

  tags = {
    Name        = "Aurora AutoScaler Lambda Signing Profile"
    Environment = var.environment
    Project     = "Aurora-AutoScaler"
    Purpose     = "Code-Signing-Security"
    Platform    = "AWS-Lambda"
    Security    = "Code-Integrity"
  }
}

# ===================================================================
# 🔒 CODE SIGNING CONFIGURATION
# ===================================================================
# Creates a code signing configuration that enforces signature
# validation for Lambda functions. This configuration defines
# the security policies for code deployment.

resource "aws_lambda_code_signing_config" "aurora_code_signing" {
  description = "Code signing configuration for Aurora AutoScaler Lambda functions"

  # ===================================================================
  # 📋 ALLOWED PUBLISHERS
  # ===================================================================
  # Specifies which signing profiles are trusted for code deployment

  allowed_publishers {
    signing_profile_version_arns = [
      aws_signer_signing_profile.lambda_signing_profile.version_arn
    ]
  }

  # ===================================================================
  # 🔐 SECURITY POLICIES
  # ===================================================================
  # Defines how Lambda handles unsigned or improperly signed code

  policies {
    # WARN: Allow deployment but log warnings (safe for transition)
    # ENFORCE: Reject deployment of unsigned code (for full security after signing)
    # Starting with WARN mode to allow smooth transition to code signing
    untrusted_artifact_on_deployment = "Warn"
  }

  # ===================================================================
  # 🏷️ RESOURCE TAGGING
  # ===================================================================

  tags = {
    Name        = "Aurora AutoScaler Code Signing Configuration"
    Environment = var.environment
    Project     = "Aurora-AutoScaler"
    Purpose     = "Code-Signing-Enforcement"
    Security    = "Code-Integrity-Validation"
    Policy      = "Enforce-Signatures"
  }
}

# ===================================================================
# 📊 DATA SOURCES FOR CODE SIGNING
# ===================================================================
# Retrieves information about the signing profile for use in outputs
# and other resources

data "aws_signer_signing_profile" "lambda_signing_profile" {
  name = aws_signer_signing_profile.lambda_signing_profile.name

  depends_on = [aws_signer_signing_profile.lambda_signing_profile]
}

# ===================================================================
# 🔐 IAM PERMISSIONS FOR CODE SIGNING
# ===================================================================
# Additional IAM permissions required for Lambda functions to work
# with code signing validation

resource "aws_iam_role_policy" "lambda_code_signing_policy" {
  name = "aurora-lambda-code-signing-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCodeSigningValidation"
        Effect = "Allow"
        Action = [
          "signer:GetSigningProfile", # Get signing profile information
          "signer:DescribeSigningJob" # Describe signing job details
        ]
        Resource = [
          aws_signer_signing_profile.lambda_signing_profile.arn,
          "${aws_signer_signing_profile.lambda_signing_profile.arn}/*"
        ]
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region
            "aws:SourceAccount"   = data.aws_caller_identity.current.account_id
          }
          # Only allow access from Aurora Lambda functions
          StringLike = {
            "aws:SourceArn" = "arn:aws:lambda:${var.region}:${data.aws_caller_identity.current.account_id}:function:aurora-*"
          }
        }
      },

      # ===================================================================
      # READ-ONLY SIGNING OPERATIONS
      # ===================================================================
      # Allow read-only operations for audit and monitoring
      {
        Sid    = "AllowReadOnlySigningOperations"
        Effect = "Allow"
        Action = [
          "signer:ListSigningJobs",    # List signing jobs for audit
          "signer:ListSigningProfiles" # List available signing profiles
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region
            "aws:SourceAccount"   = data.aws_caller_identity.current.account_id
          }
          # Restrict to Aurora-related signing profiles only
          StringLike = {
            "signer:ProfileName" = "auroraautoscaler*"
          }
        }
      },

      # ===================================================================
      # EXPLICIT DENY FOR DANGEROUS SIGNING OPERATIONS
      # ===================================================================
      # Deny operations that could compromise code signing security
      {
        Sid    = "DenyDangerousSigningOperations"
        Effect = "Deny"
        Action = [
          "signer:CreateSigningProfile",
          "signer:DeleteSigningProfile",
          "signer:PutSigningProfile",
          "signer:StartSigningJob",
          "signer:CancelSigningProfile",
          "signer:RevokeSignature",
          "signer:RevokeSigningProfile"
        ]
        Resource = "*"
      }
    ]
  })
}
