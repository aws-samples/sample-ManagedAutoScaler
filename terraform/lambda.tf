# ===================================================================
# Aurora PostgreSQL Auto-Scaling System - Lambda Functions
# ===================================================================
# This file defines the two core Lambda functions that power the
# Aurora auto-scaling system:
# 1. autoscale_up: Creates new reader instances when capacity is insufficient
# 2. downscale: Removes reader instances when CPU utilization is low
#
# Both functions are configured with security hardening, monitoring,
# and error handling capabilities.
# ===================================================================

# ===================================================================
# 🚀 AUTOSCALE UP LAMBDA FUNCTION
# ===================================================================
# This function is triggered by EventBridge when RDS insufficient
# capacity events (RDS-EVENT-0031) occur. It creates new Aurora
# reader instances to handle increased load.

resource "aws_lambda_function" "autoscale_up" {
  # Basic function configuration
  function_name = "aurora-autoscale-up"
  role          = aws_iam_role.lambda_autoscale_up_role.arn
  handler       = "autoscale_up.lambda_handler"
  runtime       = "python3.13"

  # Timeout configuration - allows sufficient time for:
  # - Capacity checking via ODCR (On-Demand Capacity Reservations)
  # - RDS instance creation API calls
  # - EventBridge scheduler management
  timeout = 120

  # Source code configuration
  filename         = "${path.module}/../lambda_builds/autoscale_up.zip"
  source_code_hash = filebase64sha256("${path.module}/../lambda_builds/autoscale_up.zip")

  # ===================================================================
  # 🔒 SECURITY CONFIGURATION
  # ===================================================================

  # Concurrency limit prevents resource exhaustion and controls costs
  # Limit of 10 allows multiple simultaneous scaling events while
  # preventing runaway executions
  reserved_concurrent_executions = 10

  # KMS encryption for environment variables containing sensitive data
  # Uses dedicated KMS key for Lambda environment variable encryption
  kms_key_arn = aws_kms_key.lambda_env_key.arn

  # Dead Letter Queue for failed executions
  # Failed invocations are sent here for debugging and analysis
  dead_letter_config {
    target_arn = aws_sqs_queue.lambda_dlq.arn
  }

  # ===================================================================
  # 🔐 CODE SIGNING CONFIGURATION
  # ===================================================================
  # Enforces code signing validation to ensure only trusted code is deployed
  # This significantly enhances security by preventing unauthorized code deployment

  code_signing_config_arn = aws_lambda_code_signing_config.aurora_code_signing.arn

  # ===================================================================
  # 🌐 VPC CONFIGURATION
  # ===================================================================
  # Configure Lambda to run inside VPC for enhanced security

  dynamic "vpc_config" {
    for_each = var.enable_vpc ? [1] : []
    content {
      subnet_ids         = local.lambda_subnet_ids
      security_group_ids = [local.lambda_security_group_id]
    }
  }

  # ===================================================================
  # 🌍 ENVIRONMENT VARIABLES
  # ===================================================================
  # These variables control the function's behavior and are encrypted
  # at rest using the KMS key specified above

  environment {
    variables = {
      # Target Aurora cluster to scale
      DB_CLUSTER_ID = var.db_cluster_id

      # SNS topic for notifications (use created topic)
      SNS_TOPIC_ARN = aws_sns_topic.aurora_scaling_alerts.arn

      # Enable/disable SNS notifications
      ENABLE_SNS = tostring(var.enable_sns)

      # AWS region for API calls
      REGION = var.region

      # Instance type configuration (remove "db." prefix for Lambda)
      PREFERRED_INSTANCE_TYPE = replace(var.preferred_instance_type, "db.", "")
      INSTANCE_TYPES_PRIORITY = join(",", [for type in var.instance_types_priority : replace(type, "db.", "")])

      # Availability zones configuration
      AVAILABILITY_ZONES = join(",", var.availability_zones)

      # Fallback strategy
      FALLBACK_STRATEGY = var.fallback_strategy

      # Database engine type
      DB_ENGINE = var.db_engine

      # Aurora reader tier for failover priority
      AURORA_READER_TIER = tostring(var.aurora_reader_tier)
    }
  }

  # ===================================================================
  # 🔍 X-RAY TRACING CONFIGURATION
  # ===================================================================
  # Enable AWS X-Ray tracing for enhanced observability and security monitoring
  # This provides detailed execution traces for debugging and performance analysis

  tracing_config {
    mode = "Active" # Active tracing captures detailed execution traces
  }

  # ===================================================================
  # 🏷️ RESOURCE TAGGING
  # ===================================================================
  # Tags for resource management, cost allocation, and compliance

  tags = {
    Name        = "Aurora AutoScaler Up Function"
    Environment = var.environment
    Project     = "Aurora-AutoScaler"
    Security    = "KMS-Encrypted"
    Purpose     = "Scale-Up-Handler"
    Trigger     = "EventBridge-RDS-Events"
    Tracing     = "X-Ray-Enabled"
  }
}

# ===================================================================
# 📉 DOWNSCALE LAMBDA FUNCTION
# ===================================================================
# This function is triggered by EventBridge Scheduler every minute
# to monitor CPU utilization and remove reader instances when they
# are no longer needed for cost optimization.

resource "aws_lambda_function" "downscale" {
  # Basic function configuration
  function_name = "aurora-downscale"
  role          = aws_iam_role.lambda_downscale_role.arn
  handler       = "downscale.lambda_handler"
  runtime       = "python3.13"

  # Timeout configuration - allows sufficient time for:
  # - CloudWatch metrics batch retrieval
  # - CPU utilization analysis across all readers
  # - RDS instance deletion operations
  # - EventBridge scheduler state management
  timeout = 120

  # Source code configuration
  filename         = "${path.module}/../lambda_builds/downscale.zip"
  source_code_hash = filebase64sha256("${path.module}/../lambda_builds/downscale.zip")

  # ===================================================================
  # 🔒 SECURITY CONFIGURATION
  # ===================================================================

  # Lower concurrency limit for downscale function since it runs
  # on a schedule and doesn't need to handle burst events
  reserved_concurrent_executions = 5

  # KMS encryption for environment variables
  kms_key_arn = aws_kms_key.lambda_env_key.arn

  # Dead Letter Queue for failed executions
  dead_letter_config {
    target_arn = aws_sqs_queue.lambda_dlq.arn
  }

  # ===================================================================
  # 🔐 CODE SIGNING CONFIGURATION
  # ===================================================================
  # Enforces code signing validation to ensure only trusted code is deployed
  # This significantly enhances security by preventing unauthorized code deployment

  code_signing_config_arn = aws_lambda_code_signing_config.aurora_code_signing.arn

  # ===================================================================
  # 🌐 VPC CONFIGURATION
  # ===================================================================
  # Configure Lambda to run inside VPC for enhanced security

  dynamic "vpc_config" {
    for_each = var.enable_vpc ? [1] : []
    content {
      subnet_ids         = local.lambda_subnet_ids
      security_group_ids = [local.lambda_security_group_id]
    }
  }

  # ===================================================================
  # 🌍 ENVIRONMENT VARIABLES
  # ===================================================================
  # Configuration variables for CPU monitoring and scaling decisions

  environment {
    variables = {
      # Target Aurora cluster to monitor
      DB_CLUSTER_ID = var.db_cluster_id

      # SNS topic for notifications (use created topic)
      SNS_TOPIC_ARN = aws_sns_topic.aurora_scaling_alerts.arn

      # Enable/disable SNS notifications
      ENABLE_SNS = tostring(var.enable_sns)

      # AWS region for API calls
      REGION = var.region

      # CPU threshold for scaling decisions (percentage)
      CPU_THRESHOLD = tostring(var.cpu_threshold)

      # Time window for CPU analysis (minutes)
      CPU_LOOKBACK_MINUTES = tostring(var.cpu_lookback_minutes)

      # CloudWatch metrics aggregation period (seconds)
      CLOUDWATCH_PERIOD = tostring(var.cloudwatch_period)

      # Database engine type
      DB_ENGINE = var.db_engine
    }
  }

  # ===================================================================
  # 🔍 X-RAY TRACING CONFIGURATION
  # ===================================================================
  # Enable AWS X-Ray tracing for enhanced observability and security monitoring
  # This provides detailed execution traces for debugging and performance analysis

  tracing_config {
    mode = "Active" # Active tracing captures detailed execution traces
  }

  # ===================================================================
  # 🏷️ RESOURCE TAGGING
  # ===================================================================

  tags = {
    Name        = "Aurora AutoScaler Down Function"
    Environment = var.environment
    Project     = "Aurora-AutoScaler"
    Security    = "KMS-Encrypted"
    Purpose     = "Scale-Down-Handler"
    Trigger     = "EventBridge-Scheduler"
    Schedule    = "Every-Minute"
    Tracing     = "X-Ray-Enabled"
  }
}
