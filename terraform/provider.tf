# ===================================================================
# Aurora PostgreSQL Auto-Scaling System - AWS Provider Configuration
# ===================================================================
# This file configures the AWS provider with the appropriate region
# and default tags for all resources created by this Terraform
# configuration.
# ===================================================================

# ===================================================================
# 🌍 AWS PROVIDER CONFIGURATION
# ===================================================================
# Configure the AWS Provider with region and default tags

provider "aws" {
  # AWS region for resource deployment
  region = var.region

  # Default tags applied to all resources
  default_tags {
    tags = {
      Project     = "Aurora-AutoScaler"
      Environment = "production"
      ManagedBy   = "terraform"
      Purpose     = "aurora-postgresql-autoscaling"
      Owner       = "infrastructure-team"
    }
  }
}
