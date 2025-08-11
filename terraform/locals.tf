# ===================================================================
# Aurora PostgreSQL Auto-Scaling System - Local Values
# ===================================================================
# This file defines local values that are computed from input variables
# and used throughout the Terraform configuration. Local values help
# reduce repetition, improve maintainability, and provide computed
# values that can be referenced by multiple resources.
#
# Local Values Benefits:
# - Centralized computation of derived values
# - Reduced code duplication across resources
# - Improved maintainability and consistency
# - Complex logic encapsulation
# ===================================================================

# ===================================================================
# 🧮 LOCAL VALUE DEFINITIONS
# ===================================================================
# Currently, this configuration uses direct variable references
# in most resources. Local values can be added here as the
# configuration grows in complexity.

locals {
  # ===================================================================
  # 🏷️ COMMON RESOURCE TAGS
  # ===================================================================
  # Standardized tags applied to all resources for governance,
  # cost allocation, and operational management

  common_tags = {
    Project     = "Aurora-AutoScaler"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = "Infrastructure-Team"
    CostCenter  = "Database-Operations"
    Compliance  = "SOC2-PCI"
  }

  # ===================================================================
  # 📍 RESOURCE NAMING CONVENTIONS
  # ===================================================================
  # Standardized naming patterns for consistent resource identification

  resource_prefix = "aurora-autoscaler"

  # Lambda function names
  lambda_names = {
    autoscale_up = "${local.resource_prefix}-up"
    downscale    = "${local.resource_prefix}-down"
  }

  # EventBridge resource names
  eventbridge_names = {
    rule     = "rds-insufficient-capacity"
    schedule = "aurora-cpu-monitor-every-minute"
  }

  # KMS key aliases
  kms_aliases = {
    lambda_env = "alias/${local.resource_prefix}-lambda-env"
    dlq        = "alias/${local.resource_prefix}-dlq"
  }

  # ===================================================================
  # 🔐 SECURITY CONFIGURATION
  # ===================================================================
  # Security-related computed values and configurations

  # Account and region information for ARN construction
  account_id = data.aws_caller_identity.current.account_id
  region     = var.region

  # KMS key rotation schedule (computed from security requirements)
  kms_rotation_enabled = var.enable_security_hardening

  # ===================================================================
  # 📊 COMPUTED SCALING PARAMETERS
  # ===================================================================
  # Derived values for scaling behavior and thresholds

  # Convert CPU threshold to decimal for calculations
  cpu_threshold_decimal = var.cpu_threshold / 100

  # Calculate CloudWatch evaluation periods based on lookback time
  cloudwatch_evaluation_periods = max(1, var.cpu_lookback_minutes * 60 / var.cloudwatch_period)

  # ===================================================================
  # 🌐 NETWORK AND AVAILABILITY CONFIGURATION
  # ===================================================================
  # Computed values for multi-AZ deployment and networking

  # Validate and process availability zones
  validated_azs = [
    for az in var.availability_zones :
    az if can(regex("^${var.region}[a-z]$", az))
  ]

  # AZ distribution strategy
  az_count = length(local.validated_azs)

  # ===================================================================
  # 📧 NOTIFICATION CONFIGURATION
  # ===================================================================
  # Computed values for SNS and notification setup

  # Determine if SNS should be configured
  sns_enabled = var.enable_sns && var.notification_email != "" && var.notification_email != "your-email@example.com"

  # SNS topic name
  sns_topic_name = "${local.resource_prefix}-alerts"

  # ===================================================================
  # 🌐 VPC CONFIGURATION LOGIC
  # ===================================================================
  # Computed values for VPC setup based on user preferences

  # Determine VPC configuration based on user preferences
  vpc_id = var.enable_vpc ? (
    var.use_existing_vpc ? var.existing_vpc_id : (
      length(aws_vpc.lambda_vpc) > 0 ? aws_vpc.lambda_vpc[0].id : null
    )
  ) : null

  # Determine subnet IDs for Lambda functions
  lambda_subnet_ids = var.enable_vpc ? (
    var.use_existing_vpc ? var.existing_private_subnet_ids : [
      aws_subnet.lambda_private_subnet_1[0].id,
      aws_subnet.lambda_private_subnet_2[0].id
    ]
  ) : []

  # Determine security group ID for Lambda functions
  lambda_security_group_id = var.enable_vpc ? (
    var.existing_security_group_id != "" ? var.existing_security_group_id : (
      length(aws_security_group.lambda_sg) > 0 ? aws_security_group.lambda_sg[0].id : null
    )
  ) : null

  # Control flags for resource creation
  create_new_vpc               = var.enable_vpc && !var.use_existing_vpc
  create_vpc_endpoints         = var.enable_vpc && var.create_vpc_endpoints
  create_lambda_security_group = var.enable_vpc && var.existing_security_group_id == ""

  # VPC endpoint services for security group rules
  vpc_endpoint_services = ["rds", "ec2", "sns", "logs", "kms", "sqs"]
}


