# ===================================================================
# Aurora PostgreSQL Auto-Scaling System - Input Validation
# ===================================================================
# This file contains validation rules to ensure proper configuration
# and prevent common deployment errors.
# ===================================================================

# ===================================================================
# 🔍 VPC CONFIGURATION VALIDATION
# ===================================================================

# Validate existing VPC configuration
resource "null_resource" "validate_existing_vpc" {
  count = var.enable_vpc && var.use_existing_vpc ? 1 : 0

  # Multiple validation rules in single lifecycle block
  lifecycle {
    # Ensure existing VPC ID is provided
    precondition {
      condition     = var.existing_vpc_id != ""
      error_message = "existing_vpc_id must be provided when use_existing_vpc is true."
    }

    # Ensure existing private subnet IDs are provided
    precondition {
      condition     = length(var.existing_private_subnet_ids) >= 2
      error_message = "At least 2 existing_private_subnet_ids must be provided when use_existing_vpc is true for high availability."
    }
  }
}

# Validate new VPC configuration
resource "null_resource" "validate_new_vpc" {
  count = var.enable_vpc && !var.use_existing_vpc ? 1 : 0

  # Multiple validation rules in single lifecycle block
  lifecycle {
    # Ensure sufficient private subnets are configured
    precondition {
      condition     = length(var.private_subnet_cidrs) >= 2
      error_message = "At least 2 private subnet CIDRs must be provided for high availability."
    }

    # Ensure sufficient public subnets are configured
    precondition {
      condition     = length(var.public_subnet_cidrs) >= 1
      error_message = "At least 1 public subnet CIDR must be provided for NAT Gateway."
    }
  }
}

# ===================================================================
# 📊 DATA VALIDATION
# ===================================================================

# Validate existing VPC exists (if specified)
data "aws_vpc" "existing" {
  count = var.enable_vpc && var.use_existing_vpc ? 1 : 0
  id    = var.existing_vpc_id
}

# Validate existing subnets exist and are in the specified VPC
data "aws_subnet" "existing_private" {
  count = var.enable_vpc && var.use_existing_vpc ? length(var.existing_private_subnet_ids) : 0
  id    = var.existing_private_subnet_ids[count.index]

  lifecycle {
    postcondition {
      condition     = self.vpc_id == var.existing_vpc_id
      error_message = "Subnet ${self.id} is not in the specified VPC ${var.existing_vpc_id}."
    }
  }
}

# Validate existing security group exists and is in the specified VPC (if provided)
data "aws_security_group" "existing" {
  count = var.enable_vpc && var.use_existing_vpc && var.existing_security_group_id != "" ? 1 : 0
  id    = var.existing_security_group_id

  lifecycle {
    postcondition {
      condition     = self.vpc_id == var.existing_vpc_id
      error_message = "Security group ${self.id} is not in the specified VPC ${var.existing_vpc_id}."
    }
  }
}
