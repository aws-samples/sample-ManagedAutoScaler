# ===================================================================
# Aurora PostgreSQL Auto-Scaling System - Terraform Variables
# ===================================================================
# This file defines all input variables for the Aurora auto-scaling
# infrastructure. These variables control the behavior, configuration,
# and security settings of the entire system.
#
# Usage: Set values in terraform.tfvars or pass via command line
# Example: terraform apply -var="db_cluster_id=my-cluster"
# ===================================================================

# ===================================================================
# 🌍 REGIONAL CONFIGURATION
# ===================================================================

variable "region" {
  description = "AWS region where all resources will be deployed"
  type        = string
  default     = "eu-central-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "Region must be a valid AWS region format (e.g., us-east-1, eu-central-1)."
  }
}

# ===================================================================
# 🗄️ DATABASE CONFIGURATION
# ===================================================================

variable "db_cluster_id" {
  description = <<-EOT
    Aurora PostgreSQL cluster identifier that will be auto-scaled.
    This is the existing cluster that the system will monitor and scale.
    
    Requirements:
    - Must be an existing Aurora PostgreSQL cluster
    - Cluster must be in the same region as this deployment
    - Must follow AWS naming conventions (alphanumeric and hyphens only)
  EOT
  type        = string
  default     = "database-11"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]*[a-zA-Z0-9]$", var.db_cluster_id))
    error_message = "DB cluster ID must start with a letter, contain only alphanumeric characters and hyphens, and end with alphanumeric character."
  }
}

variable "db_engine" {
  description = <<-EOT
    Aurora database engine type for creating new reader instances.
    This determines the engine used when the auto-scaler creates new readers.
    
    Supported values:
    - aurora-postgresql: For Aurora PostgreSQL clusters
    - aurora-mysql: For Aurora MySQL clusters
    
    Note: Must match the engine type of your existing Aurora cluster
  EOT
  type        = string
  default     = "aurora-postgresql"

  validation {
    condition     = contains(["aurora-postgresql", "aurora-mysql"], var.db_engine)
    error_message = "DB engine must be either 'aurora-postgresql' or 'aurora-mysql'."
  }
}

# ===================================================================
# 📊 CPU MONITORING AND SCALING THRESHOLDS
# ===================================================================

variable "cpu_threshold" {
  description = <<-EOT
    CPU utilization threshold (percentage) for triggering scale-down actions.
    When average CPU across all readers falls below this threshold for the
    specified lookback period, the system will remove a reader instance.
    
    Recommendations:
    - Production: 15-25% (conservative scaling)
    - Development: 5-10% (aggressive cost optimization)
    - High-performance: 30-40% (maintain performance headroom)
  EOT
  type        = number
  default     = 10.0

  validation {
    condition     = var.cpu_threshold >= 1.0 && var.cpu_threshold <= 90.0
    error_message = "CPU threshold must be between 1.0 and 90.0 percent."
  }
}

variable "cpu_lookback_minutes" {
  description = <<-EOT
    Time window (in minutes) to analyze CPU metrics before making scaling decisions.
    The system will evaluate average CPU utilization over this period.
    
    Considerations:
    - Shorter periods (2-5 min): More responsive but may cause flapping
    - Longer periods (10-15 min): More stable but slower to react
    - CloudWatch metrics have 1-minute granularity for detailed monitoring
  EOT
  type        = number
  default     = 5

  validation {
    condition     = var.cpu_lookback_minutes >= 1 && var.cpu_lookback_minutes <= 60
    error_message = "CPU lookback minutes must be between 1 and 60 minutes."
  }
}

variable "cloudwatch_period" {
  description = <<-EOT
    CloudWatch metrics aggregation period in seconds.
    This determines the granularity of CPU data points collected.
    
    Standard periods:
    - 60 seconds: Standard monitoring (included in AWS free tier)
    - 300 seconds: Basic monitoring (5-minute intervals)
    
    Note: Detailed monitoring (1-minute) may incur additional charges
  EOT
  type        = number
  default     = 60

  validation {
    condition     = contains([60, 300], var.cloudwatch_period)
    error_message = "CloudWatch period must be either 60 (detailed) or 300 (basic) seconds."
  }
}

# ===================================================================
# 📧 NOTIFICATION CONFIGURATION
# ===================================================================

variable "enable_sns" {
  description = <<-EOT
    Enable or disable SNS notifications for scaling events.
    When enabled, the system will send email notifications for:
    - Successful reader instance creation
    - Failed scaling attempts
    - EventBridge scheduler state changes
    - Error conditions and recovery actions
  EOT
  type        = bool
  default     = true
}

variable "sns_topic_arn" {
  description = <<-EOT
    ARN of an existing SNS topic for notifications (optional).
    If provided, notifications will be sent to this topic instead of
    creating a new one. Leave empty to create a new topic.
    
    Format: arn:aws:sns:region:account-id:topic-name
    Example: arn:aws:sns:us-east-1:123456789012:aurora-alerts
  EOT
  type        = string
  default     = ""

  validation {
    condition     = var.sns_topic_arn == "" || can(regex("^arn:aws:sns:", var.sns_topic_arn))
    error_message = "The sns_topic_arn value must be a valid SNS topic ARN or an empty string."
  }
}

variable "notification_email" {
  description = <<-EOT
    Email address to subscribe to SNS notifications.
    This email will receive alerts about scaling events, errors, and
    system status changes. Only used if enable_sns is true.
    
    Note: You will receive a confirmation email that must be accepted
    before notifications will be delivered.
  EOT
  type        = string
  default     = "your-email@example.com"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address format."
  }
}

# ===================================================================
# 🔒 SECURITY AND RELIABILITY CONFIGURATION
# ===================================================================

variable "dlq_message_retention_seconds" {
  description = <<-EOT
    Message retention period for the Dead Letter Queue (DLQ) in seconds.
    Failed Lambda executions will be stored in the DLQ for this duration
    for debugging and analysis purposes.
    
    Common values:
    - 1209600 (14 days): Standard retention for troubleshooting
    - 604800 (7 days): Shorter retention for cost optimization
    - 86400 (1 day): Minimal retention for development environments
  EOT
  type        = number
  default     = 1209600 # 14 days

  validation {
    condition     = var.dlq_message_retention_seconds >= 60 && var.dlq_message_retention_seconds <= 1209600
    error_message = "DLQ message retention must be between 60 seconds (1 minute) and 1209600 seconds (14 days)."
  }
}

variable "environment" {
  description = <<-EOT
    Environment name for resource tagging and identification.
    Used to tag all resources for cost allocation, access control,
    and environment management.
    
    Common values: production, staging, development, testing
  EOT
  type        = string
  default     = "production"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.environment))
    error_message = "Environment must start with a letter and contain only alphanumeric characters and hyphens."
  }
}

# ===================================================================
# 🛡️ SECURITY HARDENING VARIABLES
# ===================================================================

variable "enable_security_hardening" {
  description = <<-EOT
    Enable comprehensive security hardening features including:
    - Enhanced IAM policies with least privilege principles
    - KMS encryption for Lambda environment variables and DLQ
    - CloudTrail logging for audit compliance
    - IAM Access Analyzer for policy validation
    
    Recommended: true for production environments
  EOT
  type        = bool
  default     = true
}

variable "enable_cloudtrail" {
  description = <<-EOT
    Enable CloudTrail logging for audit and compliance requirements.
    When enabled, all API calls made by the auto-scaling system
    will be logged for security monitoring and compliance auditing.
    
    Note: CloudTrail may incur additional charges for log storage
  EOT
  type        = bool
  default     = true
}

variable "enable_access_analyzer" {
  description = <<-EOT
    Enable IAM Access Analyzer to identify overly permissive policies.
    This helps ensure that IAM roles and policies follow the principle
    of least privilege and don't grant unnecessary permissions.
    
    Recommended: true for security-conscious environments
  EOT
  type        = bool
  default     = true
}

variable "cloudtrail_retention_days" {
  description = <<-EOT
    CloudTrail log retention period in days.
    Determines how long audit logs are stored in CloudWatch Logs.
    
    Compliance considerations:
    - SOC 2: Minimum 90 days
    - PCI DSS: Minimum 365 days
    - GDPR: Varies by data classification
  EOT
  type        = number
  default     = 90

  validation {
    condition     = var.cloudtrail_retention_days >= 1 && var.cloudtrail_retention_days <= 3653
    error_message = "CloudTrail retention must be between 1 and 3653 days (10 years)."
  }
}

variable "enforce_mfa" {
  description = <<-EOT
    Enforce Multi-Factor Authentication (MFA) for IAM users accessing
    the auto-scaling system resources. This adds an additional layer
    of security for administrative access.
    
    Note: This affects IAM policies but doesn't create MFA devices
  EOT
  type        = bool
  default     = true
}

variable "max_session_duration" {
  description = <<-EOT
    Maximum session duration for IAM roles in seconds.
    This limits how long assumed role sessions can remain active,
    reducing the risk of credential compromise.
    
    AWS limits: 3600 seconds (1 hour) to 43200 seconds (12 hours)
    Security recommendation: 3600-7200 seconds for production
  EOT
  type        = number
  default     = 3600

  validation {
    condition     = var.max_session_duration >= 3600 && var.max_session_duration <= 43200
    error_message = "Max session duration must be between 3600 (1 hour) and 43200 (12 hours) seconds."
  }
}

# ===================================================================
# 🖥️ INSTANCE TYPE AND CAPACITY CONFIGURATION
# ===================================================================

variable "preferred_instance_type" {
  description = <<-EOT
    Preferred RDS instance type for new Aurora reader instances.
    This is the first choice when creating new readers. The system
    will try this type first before falling back to alternatives.
    
    Popular choices:
    - db.r5.large: General purpose, good price/performance
    - db.r6g.large: ARM-based, better price/performance
    - db.r5.xlarge: Higher memory for memory-intensive workloads
    
    Note: Specify without the "db." prefix (it will be added automatically)
  EOT
  type        = string
  default     = "db.r5.large"

  validation {
    condition     = can(regex("^db\\.[a-z0-9]+\\.[a-z0-9]+$", var.preferred_instance_type))
    error_message = "Preferred instance type must be a valid RDS instance type (e.g., db.r5.large)."
  }
}

variable "instance_types_priority" {
  description = <<-EOT
    Priority-ordered list of fallback instance types.
    If the preferred instance type has no capacity, the system will
    try these types in order until it finds available capacity.
    
    Strategy considerations:
    - Similar performance characteristics for consistent behavior
    - Mix of instance families for better availability
    - Consider cost implications of different types
    
    Example: ["db.r5.large", "db.r5.xlarge", "db.r6g.large", "db.r6g.xlarge"]
  EOT
  type        = list(string)
  default     = ["db.r5.large", "db.r5.xlarge", "db.r6g.large", "db.r6g.xlarge"]

  validation {
    condition     = length(var.instance_types_priority) > 0 && length(var.instance_types_priority) <= 10
    error_message = "Instance types priority list must contain 1-10 instance types."
  }

  validation {
    condition = alltrue([
      for instance_type in var.instance_types_priority :
      can(regex("^db\\.[a-z0-9]+\\.[a-z0-9]+$", instance_type))
    ])
    error_message = "All instance types must be valid RDS instance types (e.g., db.r5.large)."
  }
}

variable "availability_zones" {
  description = <<-EOT
    List of availability zones where reader instances can be created.
    The system will distribute readers across these AZs for high
    availability and will prefer AZs with fewer existing readers.
    
    Requirements:
    - Must be valid AZs in the specified region
    - Recommend 2-3 AZs for good distribution
    - Ensure your Aurora cluster spans these AZs
    
    Example for us-east-1: ["us-east-1a", "us-east-1b", "us-east-1c"]
  EOT
  type        = list(string)
  default     = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]

  validation {
    condition     = length(var.availability_zones) >= 1 && length(var.availability_zones) <= 6
    error_message = "Must specify 1-6 availability zones."
  }

  validation {
    condition = alltrue([
      for az in var.availability_zones :
      can(regex("^[a-z]{2}-[a-z]+-[0-9][a-z]$", az))
    ])
    error_message = "All availability zones must be valid AWS AZ format (e.g., us-east-1a)."
  }
}

variable "fallback_strategy" {
  description = <<-EOT
    Strategy for handling capacity shortages when preferred options are unavailable.
    
    Options:
    - "instance-priority": Try all AZs for each instance type before moving to next type
      Best when: Specific instance types are critical for performance consistency
      
    - "az-priority": Try all instance types in each AZ before moving to next AZ
      Best when: Geographic distribution is more important than instance type consistency
    
    The choice affects how the system balances performance consistency vs. availability.
  EOT
  type        = string
  default     = "instance-priority"

  validation {
    condition     = contains(["instance-priority", "az-priority"], var.fallback_strategy)
    error_message = "Fallback strategy must be either 'instance-priority' or 'az-priority'."
  }
}

variable "aurora_reader_tier" {
  description = <<-EOT
    Aurora reader tier for Lambda-created reader instances.
    This determines the failover priority of reader instances created by the auto-scaler.
    
    Tier Values:
    - 0-15: Valid Aurora reader tier values
    - Lower numbers = Higher priority for failover
    - Higher numbers = Lower priority for failover
    
    Recommended Values:
    - 0-5: High priority readers (critical workloads)
    - 6-10: Medium priority readers (standard workloads)  
    - 11-15: Low priority readers (auto-scaled, temporary readers)
    
    Note: Lambda-created readers are typically temporary and should use higher tier numbers
  EOT
  type        = number
  default     = 15

  validation {
    condition     = var.aurora_reader_tier >= 0 && var.aurora_reader_tier <= 15
    error_message = "Aurora reader tier must be between 0 and 15."
  }
}

# ===================================================================
# VPC Configuration Variables
# ===================================================================

variable "enable_vpc" {
  description = "Enable VPC configuration for Lambda functions"
  type        = bool
  default     = true
}

variable "use_existing_vpc" {
  description = "Use existing VPC infrastructure instead of creating new one"
  type        = bool
  default     = false
}

variable "existing_vpc_id" {
  description = "ID of existing VPC to use (required if use_existing_vpc is true)"
  type        = string
  default     = ""
}

variable "existing_private_subnet_ids" {
  description = "List of existing private subnet IDs for Lambda functions (required if use_existing_vpc is true)"
  type        = list(string)
  default     = []
}

variable "existing_security_group_id" {
  description = "ID of existing security group for Lambda functions (optional - will create new one if not provided)"
  type        = string
  default     = ""
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC (only used when creating new VPC)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (only used when creating new VPC)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (only used when creating new VPC)"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "create_vpc_endpoints" {
  description = "Create VPC endpoints for AWS services (recommended for private subnets)"
  type        = bool
  default     = true
}
