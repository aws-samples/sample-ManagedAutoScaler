# ===================================================================
# Aurora PostgreSQL Auto-Scaling System - Terraform Outputs
# ===================================================================
# This file defines output values that provide important information
# about the deployed infrastructure. These outputs are useful for:
# - Integration with other Terraform modules or systems
# - Operational monitoring and troubleshooting
# - Documentation and reference purposes
# - CI/CD pipeline integration
# ===================================================================

# ===================================================================
# 🚀 LAMBDA FUNCTION OUTPUTS
# ===================================================================
# ARNs and identifiers for the core Lambda functions

output "autoscale_lambda_arn" {
  description = <<-EOT
    ARN of the autoscale_up Lambda function.
    This function is triggered by EventBridge when RDS insufficient
    capacity events occur and creates new Aurora reader instances.
    
    Use cases:
    - Reference in other Terraform modules
    - CloudWatch alarm targets
    - Manual Lambda invocation for testing
    - IAM policy resource specifications
  EOT
  value       = aws_lambda_function.autoscale_up.arn
}

output "downscale_lambda_arn" {
  description = <<-EOT
    ARN of the downscale Lambda function.
    This function is triggered by EventBridge Scheduler every minute
    to monitor CPU utilization and remove readers when not needed.
    
    Use cases:
    - Reference in monitoring systems
    - Manual invocation for testing
    - Integration with external scheduling systems
    - Troubleshooting and operational procedures
  EOT
  value       = aws_lambda_function.downscale.arn
}

# ===================================================================
# 📅 EVENT-DRIVEN SYSTEM OUTPUTS
# ===================================================================
# Information about EventBridge rules and schedules

output "eventbridge_rule_name" {
  description = <<-EOT
    Name of the EventBridge rule that captures RDS insufficient capacity events.
    This rule monitors for RDS-EVENT-0031 events and triggers the autoscale_up function.
    
    Operational uses:
    - Monitoring rule metrics in CloudWatch
    - Troubleshooting event pattern matching
    - Manual rule enable/disable operations
    - Integration with monitoring dashboards
  EOT
  value       = aws_cloudwatch_event_rule.insufficient_capacity.name
}

output "downscale_scheduler_name" {
  description = <<-EOT
    Name of the EventBridge Scheduler that triggers CPU monitoring.
    This scheduler runs every minute to evaluate CPU utilization
    and remove readers when utilization is consistently low.
    
    Operational uses:
    - Monitoring scheduler execution metrics
    - Manual schedule enable/disable operations
    - Troubleshooting scaling behavior
    - Cost optimization analysis
  EOT
  value       = aws_scheduler_schedule.downscale_schedule.name
}

# ===================================================================
# 📧 NOTIFICATION SYSTEM OUTPUTS
# ===================================================================
# SNS topic information for alerts and notifications

output "sns_topic_arn" {
  description = <<-EOT
    ARN of the SNS topic used for Aurora scaling notifications.
    This topic receives alerts about scaling events, errors, and
    system status changes from both Lambda functions.
    
    Integration uses:
    - Subscribe additional endpoints (email, SMS, webhooks)
    - Reference in other notification systems
    - CloudWatch alarm targets
    - Manual message publishing for testing
  EOT
  value       = aws_sns_topic.aurora_scaling_alerts.arn
}

# ===================================================================
# 💀 ERROR HANDLING OUTPUTS
# ===================================================================
# Dead Letter Queue information for failed executions

output "dlq_queue_arn" {
  description = <<-EOT
    ARN of the Dead Letter Queue (DLQ) for failed Lambda executions.
    This SQS queue captures failed Lambda invocations for debugging
    and analysis purposes.
    
    Operational uses:
    - Monitoring failed execution metrics
    - Processing failed messages for analysis
    - Setting up DLQ processing workflows
    - Troubleshooting system failures
  EOT
  value       = aws_sqs_queue.lambda_dlq.arn
}

output "dlq_queue_url" {
  description = <<-EOT
    URL of the Dead Letter Queue for direct SQS operations.
    Use this URL for receiving, processing, or purging DLQ messages.
    
    Common operations:
    - aws sqs receive-message --queue-url <this-url>
    - aws sqs purge-queue --queue-url <this-url>
    - Integration with message processing systems
    - Automated DLQ monitoring scripts
  EOT
  value       = aws_sqs_queue.lambda_dlq.url
}

# ===================================================================
# 🔐 SECURITY AND ENCRYPTION OUTPUTS
# ===================================================================
# KMS key information for encryption and security operations

output "dlq_kms_key_id" {
  description = <<-EOT
    ID of the KMS key used for Dead Letter Queue message encryption.
    This customer-managed key encrypts DLQ messages at rest.
    
    Security uses:
    - Key rotation monitoring
    - Access policy management
    - Compliance reporting
    - Encryption operation troubleshooting
  EOT
  value       = aws_kms_key.lambda_dlq_key.key_id
}

output "dlq_kms_key_arn" {
  description = <<-EOT
    ARN of the KMS key used for DLQ encryption.
    Full ARN for use in IAM policies and cross-service references.
    
    Policy uses:
    - IAM policy resource specifications
    - Cross-account key sharing (if needed)
    - CloudTrail log analysis
    - Key usage monitoring
  EOT
  value       = aws_kms_key.lambda_dlq_key.arn
}

output "lambda_env_kms_key_id" {
  description = <<-EOT
    ID of the KMS key used for Lambda environment variable encryption.
    This key encrypts sensitive configuration data in Lambda functions.
    
    Security operations:
    - Environment variable encryption monitoring
    - Key rotation tracking
    - Compliance auditing
    - Security policy enforcement
  EOT
  value       = aws_kms_key.lambda_env_key.key_id
}

output "lambda_env_kms_key_arn" {
  description = <<-EOT
    ARN of the Lambda environment variable encryption KMS key.
    Full ARN for comprehensive security and policy management.
    
    Integration uses:
    - IAM policy resource definitions
    - Security monitoring systems
    - Compliance reporting tools
    - Key management workflows
  EOT
  value       = aws_kms_key.lambda_env_key.arn
}

output "lambda_env_kms_alias" {
  description = <<-EOT
    Human-readable alias for the Lambda environment encryption KMS key.
    Easier to reference in scripts and operational procedures.
    
    Operational uses:
    - CLI commands and scripts
    - Documentation and runbooks
    - Key identification in logs
    - Simplified key management
  EOT
  value       = aws_kms_alias.lambda_env_key_alias.name
}

output "scheduler_kms_key_id" {
  description = <<-EOT
    ID of the KMS key used for EventBridge Scheduler encryption.
    This key encrypts schedule data and payloads at rest for enhanced security.
    
    Security operations:
    - Schedule data encryption monitoring
    - Key rotation tracking
    - Compliance auditing for scheduler security
    - Security policy enforcement
  EOT
  value       = aws_kms_key.scheduler_key.key_id
}

output "scheduler_kms_key_arn" {
  description = <<-EOT
    ARN of the EventBridge Scheduler encryption KMS key.
    Full ARN for comprehensive security and policy management.
    
    Integration uses:
    - IAM policy resource definitions
    - Security monitoring systems
    - Compliance reporting tools
    - Cross-service encryption references
  EOT
  value       = aws_kms_key.scheduler_key.arn
}

output "scheduler_kms_alias" {
  description = <<-EOT
    Human-readable alias for the EventBridge Scheduler encryption KMS key.
    Easier to reference in operational procedures and scripts.
    
    Operational uses:
    - CLI commands for scheduler management
    - Documentation and security runbooks
    - Key identification in audit logs
    - Simplified scheduler key management
  EOT
  value       = aws_kms_alias.scheduler_key_alias.name
}

output "lambda_tracing_config" {
  description = <<-EOT
    X-Ray tracing configuration for Lambda functions.
    Shows the tracing mode enabled for enhanced observability.
    
    Security benefits:
    - Detailed execution traces for security analysis
    - Performance monitoring and optimization
    - Request flow visualization across AWS services
    - Enhanced debugging capabilities for security incidents
  EOT
  value = {
    autoscale_up_tracing = aws_lambda_function.autoscale_up.tracing_config[0].mode
    downscale_tracing    = aws_lambda_function.downscale.tracing_config[0].mode
  }
}

output "lambda_code_signing_config" {
  description = <<-EOT
    Code signing configuration for Lambda functions.
    Shows the code signing enforcement policy and signing profile details.
    
    Security benefits:
    - Code integrity verification through digital signatures
    - Prevention of unauthorized code deployment
    - Compliance with enterprise security requirements
    - Audit trail for code deployment activities
  EOT
  value = {
    code_signing_config_arn = aws_lambda_code_signing_config.aurora_code_signing.arn
    signing_profile_arn     = aws_signer_signing_profile.lambda_signing_profile.arn
    signing_profile_name    = aws_signer_signing_profile.lambda_signing_profile.name
    enforcement_policy      = aws_lambda_code_signing_config.aurora_code_signing.policies[0].untrusted_artifact_on_deployment
    platform_id             = aws_signer_signing_profile.lambda_signing_profile.platform_id
  }
}

# ===================================================================
# ⚡ PERFORMANCE AND SCALING OUTPUTS
# ===================================================================
# Lambda concurrency and performance configuration

output "lambda_concurrency_limits" {
  description = <<-EOT
    Reserved concurrency limits for Lambda functions.
    These limits control how many instances of each function
    can run simultaneously, preventing resource exhaustion.
    
    Configuration details:
    - autoscale_up: Higher limit for burst scaling events
    - downscale: Lower limit for scheduled monitoring
    
    Monitoring uses:
    - Performance optimization analysis
    - Cost management and planning
    - Capacity planning for scaling events
    - Troubleshooting concurrency issues
  EOT
  value = {
    autoscale_up = aws_lambda_function.autoscale_up.reserved_concurrent_executions
    downscale    = aws_lambda_function.downscale.reserved_concurrent_executions
  }
}

# ===================================================================
# VPC OUTPUTS
# ===================================================================

output "vpc_id" {
  description = "ID of the VPC (if VPC is enabled)"
  value       = local.vpc_id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC (if VPC is enabled and new VPC created)"
  value       = local.create_new_vpc ? aws_vpc.lambda_vpc[0].cidr_block : null
}

output "private_subnet_ids" {
  description = "IDs of the private subnets used by Lambda functions"
  value       = var.enable_vpc ? local.lambda_subnet_ids : null
}

output "public_subnet_ids" {
  description = "IDs of the public subnets (if new VPC created)"
  value       = local.create_new_vpc ? [aws_subnet.lambda_public_subnet_1[0].id] : null
}

output "nat_gateway_id" {
  description = "ID of the NAT Gateway (if new VPC created)"
  value       = local.create_new_vpc ? aws_nat_gateway.lambda_nat_gateway[0].id : null
}

output "lambda_security_group_id" {
  description = "ID of the Lambda security group"
  value       = local.lambda_security_group_id
}

output "vpc_endpoints" {
  description = "VPC endpoint information (if VPC endpoints created)"
  value = local.create_vpc_endpoints ? {
    rds        = aws_vpc_endpoint.rds[0].id
    ec2        = aws_vpc_endpoint.ec2[0].id
    sns        = aws_vpc_endpoint.sns[0].id
    scheduler  = aws_vpc_endpoint.scheduler[0].id
    cloudwatch = aws_vpc_endpoint.cloudwatch[0].id
    logs       = aws_vpc_endpoint.logs[0].id
    sqs        = aws_vpc_endpoint.sqs[0].id
    kms        = aws_vpc_endpoint.kms[0].id
    xray       = aws_vpc_endpoint.xray[0].id
  } : null
}

output "vpc_configuration_summary" {
  description = "Summary of VPC configuration choices"
  value = var.enable_vpc ? {
    vpc_enabled          = var.enable_vpc
    using_existing_vpc   = var.use_existing_vpc
    vpc_id               = local.vpc_id
    create_new_vpc       = local.create_new_vpc
    create_vpc_endpoints = local.create_vpc_endpoints
    lambda_subnet_count  = length(local.lambda_subnet_ids)
  } : null
}


