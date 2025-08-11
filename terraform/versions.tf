# ===================================================================
# Aurora PostgreSQL Auto-Scaling System - Provider Versions
# ===================================================================
# This file defines the required Terraform and provider versions
# for the Aurora auto-scaling infrastructure. Version constraints
# ensure compatibility and prevent breaking changes from affecting
# the deployment.
#
# Version Management Benefits:
# - Ensures consistent deployments across environments
# - Prevents breaking changes from newer provider versions
# - Enables reproducible infrastructure deployments
# - Supports compliance and change management requirements
# ===================================================================

# ===================================================================
# 🔧 TERRAFORM VERSION REQUIREMENTS
# ===================================================================
# Specifies the minimum Terraform version and required providers
# with their version constraints and source locations

terraform {
  # ===================================================================
  # TERRAFORM CORE VERSION
  # ===================================================================
  # Minimum Terraform version required for this configuration
  # Version 1.0+ provides stable APIs and improved state management
  required_version = ">= 1.0"

  # ===================================================================
  # REQUIRED PROVIDERS CONFIGURATION
  # ===================================================================
  # Defines the AWS provider with version constraints and source

  required_providers {
    aws = {
      # Provider source from the Terraform Registry
      source = "hashicorp/aws"

      # Version constraint - allows patch updates but prevents
      # potentially breaking minor version changes
      # ~> 5.0 means >= 5.0.0 and < 6.0.0
      version = "~> 5.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }

    null = {
      source  = "hashicorp/null"
      version = "~> 3.1"
    }
  }
}


