# ===================================================================
# FIXED IAM CONFIGURATION FOR AURORA AUTOSCALER WITH SECURE TAGGING
# ===================================================================
# This fixes the permission issues and implements secure tagging-based
# deletion restrictions while keeping existing capacity logic unchanged

resource "aws_iam_role" "lambda_role" {
  name = "aurora-autoscale-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = [
            "lambda.amazonaws.com",
            "scheduler.amazonaws.com"
          ]
        },
        Action = "sts:AssumeRole"
      }
    ]
  })

  max_session_duration = var.max_session_duration

  tags = {
    Name        = "Aurora AutoScaler Lambda Role"
    Environment = var.environment
    Project     = "Aurora-AutoScaler"
  }
}

# Basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Data sources
data "aws_caller_identity" "current" {}

# Main Lambda policy with fixed permissions and secure tagging
resource "aws_iam_role_policy" "lambda_policy" {
  name = "aurora-scaler-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # ===================================================================
      # FIX 1: RDS READ PERMISSIONS - Allow describe operations
      # ===================================================================
      {
        Sid    = "RDSDescribeOperations"
        Effect = "Allow"
        Action = [
          "rds:DescribeDBInstances",
          "rds:DescribeDBClusters",
          "rds:ListTagsForResource"
        ]
        Resource = "*" # These actions require wildcard access
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region
          }
        }
      },

      # ===================================================================
      # FIX 2: RDS INSTANCE CREATION - Allow creating instances with tags
      # ===================================================================
      {
        Sid    = "RDSCreateInstance"
        Effect = "Allow"
        Action = [
          "rds:CreateDBInstance"
        ]
        Resource = [
          # Allow operations on the specific cluster
          "arn:aws:rds:${var.region}:${data.aws_caller_identity.current.account_id}:cluster:${var.db_cluster_id}",
          # Allow creating instances with lambda-managed naming pattern only
          "arn:aws:rds:${var.region}:${data.aws_caller_identity.current.account_id}:db:lambda-aurora-reader-*",
          # Allow access to parameter groups and option groups
          "arn:aws:rds:${var.region}:${data.aws_caller_identity.current.account_id}:pg:*",
          "arn:aws:rds:${var.region}:${data.aws_caller_identity.current.account_id}:og:*",
          # Allow access to subnet groups
          "arn:aws:rds:${var.region}:${data.aws_caller_identity.current.account_id}:subgrp:*"
        ]
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region
          }
        }
      },

      # ===================================================================
      # FIX 3: RDS TAGGING - Allow tagging instances during creation
      # ===================================================================
      {
        Sid    = "RDSTagging"
        Effect = "Allow"
        Action = [
          "rds:AddTagsToResource"
        ]
        Resource = [
          "arn:aws:rds:${var.region}:${data.aws_caller_identity.current.account_id}:db:lambda-aurora-reader-*"
        ]
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region
          }
        }
      },

      # ===================================================================
      # ENHANCED SECURITY: RDS INSTANCE DELETION - Tag-based conditions
      # ===================================================================
      {
        Sid    = "RDSDeleteLambdaManagedOnlyWithTags"
        Effect = "Allow"
        Action = [
          "rds:DeleteDBInstance"
        ]
        Resource = [
          "arn:aws:rds:${var.region}:${data.aws_caller_identity.current.account_id}:db:lambda-aurora-reader-*"
        ]
        Condition = {
          StringEquals = {
            "aws:RequestedRegion"   = var.region,
            "rds:db-tag/ManagedBy"  = "aurora-autoscaler",
            "rds:db-tag/AutoScaler" = "lambda-managed"
          }
        }
      },


      # ===================================================================
      # EXISTING: EC2 PERMISSIONS - Keep existing capacity logic unchanged
      # ===================================================================
      {
        Sid    = "EC2CapacityOperations"
        Effect = "Allow"
        Action = [
          "ec2:CreateCapacityReservation",
          "ec2:CancelCapacityReservation",
          "ec2:DescribeCapacityReservations",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypes"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region
          }
        }
      },

      # ===================================================================
      # EXISTING: EC2 TAGGING - For capacity reservations
      # ===================================================================
      {
        Sid    = "EC2TaggingCapacityReservations"
        Effect = "Allow"
        Action = [
          "ec2:CreateTags"
        ]
        Resource = "arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:capacity-reservation/*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region
            "ec2:CreateAction"    = "CreateCapacityReservation"
          }
        }
      },

      # ===================================================================
      # FIXED: CLOUDWATCH METRICS - For CPU monitoring (both functions)
      # ===================================================================
      {
        Sid    = "CloudWatchMetrics"
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region
          }
          StringLike = {
            "cloudwatch:namespace" = "AWS/RDS"
          }
        }
      },

      # ===================================================================
      # EXISTING: EVENTBRIDGE SCHEDULER - For downscale scheduling
      # ===================================================================
      {
        Sid    = "SchedulerOperations"
        Effect = "Allow"
        Action = [
          "scheduler:GetSchedule",
          "scheduler:UpdateSchedule"
        ]
        Resource = "arn:aws:scheduler:${var.region}:${data.aws_caller_identity.current.account_id}:schedule/default/aurora-*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region
          }
        }
      },

      # ===================================================================
      # EXISTING: LAMBDA INVOKE - For cross-function invocation
      # ===================================================================
      {
        Sid    = "LambdaInvoke"
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = "arn:aws:lambda:${var.region}:${data.aws_caller_identity.current.account_id}:function:aurora-*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region
          }
        }
      },

      # ===================================================================
      # EXISTING: VPC NETWORKING - For Lambda in VPC (if applicable)
      # ===================================================================
      {
        Sid    = "VPCNetworking"
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "ec2:AttachNetworkInterface",
          "ec2:DetachNetworkInterface"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region
          }
        }
      },

      # ===================================================================
      # SNS PERMISSIONS - For notifications when topic ARN is available
      # ===================================================================
      {
        Sid    = "SNSPublishNotifications"
        Effect = "Allow"
        Action = [
          "sns:Publish"
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
}

# ===================================================================
# EXISTING: SNS POLICY - For notifications (if enabled)
# ===================================================================
resource "aws_iam_role_policy" "lambda_sns_policy" {
  count = var.enable_sns && var.sns_topic_arn != "" ? 1 : 0
  name  = "aurora-scaler-lambda-sns-policy"
  role  = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SNSPublishNotifications"
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = var.sns_topic_arn
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region
          }
        }
      }
    ]
  })
}

# ===================================================================
# EXISTING: DLQ POLICY - For Dead Letter Queue access
# ===================================================================
resource "aws_iam_role_policy" "lambda_dlq_policy" {
  name = "aurora-autoscaler-dlq-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DLQAccess"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.lambda_dlq.arn
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region
          }
        }
      },
      {
        Sid    = "DLQKMSAccess"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.lambda_dlq_key.arn
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region
          }
        }
      }
    ]
  })
}

# ===================================================================
# SEPARATED ROLES FOR IMPROVED SECURITY
# ===================================================================

# 1. AUTOSCALE-UP LAMBDA ROLE
resource "aws_iam_role" "lambda_autoscale_up_role" {
  name = "aurora-autoscale-up-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })

  max_session_duration = var.max_session_duration

  tags = {
    Name        = "Aurora AutoScaler Up Lambda Role"
    Environment = var.environment
    Project     = "Aurora-AutoScaler"
  }
}

# Basic execution policy
resource "aws_iam_role_policy_attachment" "lambda_autoscale_up_basic_execution" {
  role       = aws_iam_role.lambda_autoscale_up_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Enhanced permissions with comprehensive RDS and EC2 access
resource "aws_iam_role_policy" "lambda_autoscale_up_policy" {
  name = "aurora-autoscale-up-policy"
  role = aws_iam_role.lambda_autoscale_up_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # FIXED: RDS read operations require wildcard access
      {
        Sid    = "RDSReadOperations"
        Effect = "Allow"
        Action = [
          "rds:DescribeDBClusters",
          "rds:DescribeDBInstances",
          "rds:ListTagsForResource",
          "rds:DescribeDBSubnetGroups",
          "rds:DescribeDBParameterGroups"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region
          }
        }
      },
      # RDS write operations with specific resource restrictions
      {
        Sid    = "RDSCreateAndTag"
        Effect = "Allow"
        Action = [
          "rds:CreateDBInstance",
          "rds:AddTagsToResource"
        ]
        Resource = [
          "arn:aws:rds:${var.region}:${data.aws_caller_identity.current.account_id}:cluster:${var.db_cluster_id}",
          "arn:aws:rds:${var.region}:${data.aws_caller_identity.current.account_id}:db:${var.db_cluster_id}-reader-*",
          "arn:aws:rds:${var.region}:${data.aws_caller_identity.current.account_id}:db:lambda-aurora-reader-*",
          "arn:aws:rds:${var.region}:${data.aws_caller_identity.current.account_id}:subnet-group:*",
          "arn:aws:rds:${var.region}:${data.aws_caller_identity.current.account_id}:pg:*"
        ]
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region
          }
        }
      },
      # FIXED: Enhanced EC2 permissions for better capacity checking and operations
      {
        Sid    = "EC2CapacityOperations"
        Effect = "Allow"
        Action = [
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeCapacityReservations",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:CreateCapacityReservation",
          "ec2:CancelCapacityReservation",
          "ec2:CreateTags"
        ]
        Resource = "*"
      },
      # FIXED: Enhanced EventBridge Scheduler permissions with correct resource names
      {
        Sid    = "EventBridgeSchedulerManagement"
        Effect = "Allow"
        Action = [
          "scheduler:CreateSchedule",
          "scheduler:GetSchedule",
          "scheduler:UpdateSchedule",
          "scheduler:DeleteSchedule",
          "scheduler:ListSchedules"
        ]
        Resource = [
          "arn:aws:scheduler:${var.region}:${data.aws_caller_identity.current.account_id}:schedule/default/aurora-downscale-*",
          "arn:aws:scheduler:${var.region}:${data.aws_caller_identity.current.account_id}:schedule/default/aurora-cpu-monitor-every-minute",
          "arn:aws:scheduler:${var.region}:${data.aws_caller_identity.current.account_id}:schedule-group/default"
        ]
      },
      # PassRole with proper conditions
      {
        Sid    = "PassRoleToScheduler"
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = aws_iam_role.eventbridge_scheduler_role.arn
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "scheduler.amazonaws.com"
            "aws:RequestedRegion" = var.region
          }
        }
      },
      # CloudWatch Logs access for debugging
      {
        Sid    = "CloudWatchLogsAccess"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/aurora-autoscale-up:*",
          "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/aurora-downscale:*"
        ]
      },
      # SNS notifications (if enabled)
      {
        Sid    = "SNSNotifications"
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.aurora_scaling_alerts.arn
      },
      # SQS Dead Letter Queue permissions
      {
        Sid    = "DLQAccess"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.lambda_dlq.arn
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region
          }
        }
      },
      # DLQ KMS permissions
      {
        Sid    = "DLQKMSAccess"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.lambda_dlq_key.arn
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region
          }
        }
      },
      # KMS permissions for EventBridge Scheduler management
      {
        Sid    = "KMSSchedulerAccess"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.scheduler_key.arn
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region
          }
        }
      },
      # VPC networking permissions for Lambda in VPC
      {
        Sid    = "VPCNetworking"
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "ec2:AttachNetworkInterface",
          "ec2:DetachNetworkInterface"
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
}

# 2. DOWNSCALE LAMBDA ROLE
resource "aws_iam_role" "lambda_downscale_role" {
  name = "aurora-downscale-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })

  max_session_duration = var.max_session_duration

  tags = {
    Name        = "Aurora AutoScaler Down Lambda Role"
    Environment = var.environment
    Project     = "Aurora-AutoScaler"
  }
}

# Basic execution policy
resource "aws_iam_role_policy_attachment" "lambda_downscale_basic_execution" {
  role       = aws_iam_role.lambda_downscale_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# FIXED: Enhanced downscale permissions with all troubleshooting fixes applied
resource "aws_iam_role_policy" "lambda_downscale_policy" {
  name = "aurora-downscale-policy"
  role = aws_iam_role.lambda_downscale_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # RDS permissions for describe operations with region condition
      {
        Sid    = "RDSDescribeOperations"
        Effect = "Allow"
        Action = [
          "rds:DescribeDBClusters",
          "rds:DescribeDBInstances",
          "rds:ListTagsForResource"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region
          }
        }
      },
      # RDS delete permissions with specific resource restrictions and region condition
      {
        Sid    = "RDSDeleteInstance"
        Effect = "Allow"
        Action = [
          "rds:DeleteDBInstance"
        ]
        Resource = [
          "arn:aws:rds:${var.region}:${data.aws_caller_identity.current.account_id}:db:${var.db_cluster_id}-reader-*",
          "arn:aws:rds:${var.region}:${data.aws_caller_identity.current.account_id}:db:lambda-aurora-reader-*"
        ]
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region
          }
        }
      },
      # FIXED: CloudWatch permissions with region condition for security
      {
        Sid    = "CloudWatchMetrics"
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:GetMetricData",
          "cloudwatch:ListMetrics"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region
          }
        }
      },
      # FIXED: EventBridge Scheduler permissions with region condition
      {
        Sid    = "EventBridgeSchedulerRead"
        Effect = "Allow"
        Action = [
          "scheduler:GetSchedule",
          "scheduler:UpdateSchedule",
          "scheduler:DeleteSchedule"
        ]
        Resource = [
          "arn:aws:scheduler:${var.region}:${data.aws_caller_identity.current.account_id}:schedule/default/aurora-downscale-*",
          "arn:aws:scheduler:${var.region}:${data.aws_caller_identity.current.account_id}:schedule/default/aurora-cpu-monitor-every-minute"
        ]
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region
          }
        }
      },
      # CloudWatch Logs access for debugging
      {
        Sid    = "CloudWatchLogsAccess"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/aurora-downscale:*"
        ]
      },
      # FIXED: IAM PassRole permission for EventBridge Scheduler management
      {
        Sid    = "IAMPassRole"
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aurora-eventbridge-scheduler-role"
        ]
      },
      # FIXED: KMS permissions for EventBridge Scheduler
      {
        Sid    = "KMSSchedulerAccess"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = [
          "arn:aws:kms:${var.region}:${data.aws_caller_identity.current.account_id}:key/0469bfb8-dc38-4ed5-962f-2b440aa903c9"
        ]
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region
          }
        }
      },
      # SNS notifications (if enabled)
      {
        Sid    = "SNSNotifications"
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.aurora_scaling_alerts.arn
      },
      # SQS Dead Letter Queue permissions
      {
        Sid    = "DLQAccess"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.lambda_dlq.arn
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region
          }
        }
      },
      # DLQ KMS permissions
      {
        Sid    = "DLQKMSAccess"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.lambda_dlq_key.arn
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region
          }
        }
      },
      # VPC networking permissions for Lambda in VPC
      {
        Sid    = "VPCNetworking"
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "ec2:AttachNetworkInterface",
          "ec2:DetachNetworkInterface"
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
}

# 3. EVENTBRIDGE SCHEDULER ROLE
resource "aws_iam_role" "eventbridge_scheduler_role" {
  name = "aurora-eventbridge-scheduler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "scheduler.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })

  max_session_duration = var.max_session_duration

  tags = {
    Name        = "Aurora AutoScaler EventBridge Scheduler Role"
    Environment = var.environment
    Project     = "Aurora-AutoScaler"
  }
}

# Scheduler permissions (Lambda invoke + KMS access)
resource "aws_iam_role_policy" "eventbridge_scheduler_policy" {
  name = "aurora-eventbridge-scheduler-policy"
  role = aws_iam_role.eventbridge_scheduler_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "InvokeLambdaFunction"
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          "arn:aws:lambda:${var.region}:${data.aws_caller_identity.current.account_id}:function:aurora-downscale"
        ]
      },
      {
        Sid    = "KMSSchedulerAccess"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey"
        ]
        Resource = [
          aws_kms_key.scheduler_key.arn
        ]
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region
          }
        }
      }
    ]
  })
}
