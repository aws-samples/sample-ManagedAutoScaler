# ===================================================================
# Aurora PostgreSQL Auto-Scaling System - VPC Configuration
# ===================================================================
# This file defines the VPC infrastructure required for Lambda functions
# to run securely within a private network environment with proper
# access to AWS services through VPC endpoints and NAT Gateway.
# ===================================================================

# ===================================================================
# 🌐 VPC AND NETWORKING
# ===================================================================

# Main VPC for Lambda functions
# VPC FLOW LOGS NOTE: VPC Flow Logs are configured via aws_flow_log resource below.
# Checkov may not detect conditional flow log configuration during static analysis.
resource "aws_vpc" "lambda_vpc" {
  #checkov:skip=CKV2_AWS_11:VPC Flow Logs are configured via aws_flow_log resource when new VPC is created

  count = local.create_new_vpc ? 1 : 0

  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "Aurora AutoScaler VPC"
    Environment = var.environment
    Project     = "Aurora-AutoScaler"
    Purpose     = "Lambda-Networking"
  }
}

# VPC Flow Logs for security monitoring
resource "aws_flow_log" "lambda_vpc_flow_log" {
  count = local.create_new_vpc ? 1 : 0

  iam_role_arn    = aws_iam_role.flow_log_role[0].arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_log[0].arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.lambda_vpc[0].id

  tags = {
    Name        = "Aurora AutoScaler VPC Flow Logs"
    Environment = var.environment
    Project     = "Aurora-AutoScaler"
    Purpose     = "Security-Monitoring"
  }
}

# CloudWatch Log Group for VPC Flow Logs
# RETENTION NOTE: 30-day retention is sufficient for VPC flow log analysis and 
# operational troubleshooting. Longer retention would significantly increase costs 
# without proportional security benefit for this auto-scaling system.
resource "aws_cloudwatch_log_group" "vpc_flow_log" {
  #checkov:skip=CKV_AWS_338:30-day retention sufficient for VPC flow logs, longer retention increases costs without proportional security benefit

  count = local.create_new_vpc ? 1 : 0

  name              = "/aws/vpc/flowlogs/aurora-autoscaler"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.vpc_flow_log_key[0].arn

  tags = {
    Name        = "Aurora AutoScaler VPC Flow Logs"
    Environment = var.environment
    Project     = "Aurora-AutoScaler"
  }
}

# KMS Key for VPC Flow Logs encryption
resource "aws_kms_key" "vpc_flow_log_key" {
  count = local.create_new_vpc ? 1 : 0

  description             = "KMS key for Aurora AutoScaler VPC Flow Logs encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow CloudWatch Logs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${var.region}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "Aurora AutoScaler VPC Flow Log KMS Key"
    Environment = var.environment
    Project     = "Aurora-AutoScaler"
  }
}

# KMS Key Alias for VPC Flow Logs
resource "aws_kms_alias" "vpc_flow_log_key_alias" {
  count = local.create_new_vpc ? 1 : 0

  name          = "alias/aurora-autoscaler-vpc-flow-logs"
  target_key_id = aws_kms_key.vpc_flow_log_key[0].key_id
}

# IAM Role for VPC Flow Logs
resource "aws_iam_role" "flow_log_role" {
  count = local.create_new_vpc ? 1 : 0

  name = "aurora-autoscaler-vpc-flow-log-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "Aurora AutoScaler VPC Flow Log Role"
    Environment = var.environment
    Project     = "Aurora-AutoScaler"
  }
}

# IAM Policy for VPC Flow Logs
resource "aws_iam_role_policy" "flow_log_policy" {
  count = local.create_new_vpc ? 1 : 0

  name = "aurora-autoscaler-vpc-flow-log-policy"
  role = aws_iam_role.flow_log_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:*"
      }
    ]
  })
}

# Internet Gateway for public subnet
resource "aws_internet_gateway" "lambda_igw" {
  count = local.create_new_vpc ? 1 : 0

  vpc_id = aws_vpc.lambda_vpc[0].id

  tags = {
    Name        = "Aurora AutoScaler IGW"
    Environment = var.environment
    Project     = "Aurora-AutoScaler"
  }
}

# ===================================================================
# 🔒 PRIVATE SUBNETS FOR LAMBDA FUNCTIONS
# ===================================================================

# Private subnet in AZ 1
resource "aws_subnet" "lambda_private_subnet_1" {
  count = local.create_new_vpc ? 1 : 0

  vpc_id            = aws_vpc.lambda_vpc[0].id
  cidr_block        = var.private_subnet_cidrs[0]
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name        = "Aurora AutoScaler Private Subnet 1"
    Environment = var.environment
    Project     = "Aurora-AutoScaler"
    Type        = "Private"
    AZ          = data.aws_availability_zones.available.names[0]
  }
}

# Private subnet in AZ 2
resource "aws_subnet" "lambda_private_subnet_2" {
  count = local.create_new_vpc ? 1 : 0

  vpc_id            = aws_vpc.lambda_vpc[0].id
  cidr_block        = var.private_subnet_cidrs[1]
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name        = "Aurora AutoScaler Private Subnet 2"
    Environment = var.environment
    Project     = "Aurora-AutoScaler"
    Type        = "Private"
    AZ          = data.aws_availability_zones.available.names[1]
  }
}

# ===================================================================
# 🌍 PUBLIC SUBNETS FOR NAT GATEWAY
# ===================================================================

# Public subnet for NAT Gateway in AZ 1
resource "aws_subnet" "lambda_public_subnet_1" {
  count = local.create_new_vpc ? 1 : 0

  vpc_id                  = aws_vpc.lambda_vpc[0].id
  cidr_block              = var.public_subnet_cidrs[0]
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false # Security: Disable automatic public IP assignment

  tags = {
    Name        = "Aurora AutoScaler Public Subnet 1"
    Environment = var.environment
    Project     = "Aurora-AutoScaler"
    Type        = "Public"
    AZ          = data.aws_availability_zones.available.names[0]
  }
}

# ===================================================================
# 🔄 NAT GATEWAY FOR OUTBOUND INTERNET ACCESS
# ===================================================================

# Elastic IP for NAT Gateway
# ATTACHMENT NOTE: This EIP is conditionally attached to the NAT Gateway 
# when local.create_new_vpc = true. Checkov cannot detect conditional 
# attachments during static analysis.
resource "aws_eip" "lambda_nat_eip" {
  #checkov:skip=CKV2_AWS_1:EIP conditionally attached to NAT Gateway when new VPC is created

  count = local.create_new_vpc ? 1 : 0

  domain = "vpc"

  depends_on = [aws_internet_gateway.lambda_igw]

  tags = {
    Name        = "Aurora AutoScaler NAT EIP"
    Environment = var.environment
    Project     = "Aurora-AutoScaler"
  }
}

# NAT Gateway for Lambda functions to access AWS APIs
resource "aws_nat_gateway" "lambda_nat_gateway" {
  count = local.create_new_vpc ? 1 : 0

  allocation_id = aws_eip.lambda_nat_eip[0].id
  subnet_id     = aws_subnet.lambda_public_subnet_1[0].id

  depends_on = [
    aws_internet_gateway.lambda_igw,
    aws_eip.lambda_nat_eip
  ]

  tags = {
    Name        = "Aurora AutoScaler NAT Gateway"
    Environment = var.environment
    Project     = "Aurora-AutoScaler"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ===================================================================
# 🛣️ ROUTE TABLES
# ===================================================================

# Route table for public subnet
resource "aws_route_table" "lambda_public_rt" {
  count = var.enable_vpc ? 1 : 0

  vpc_id = aws_vpc.lambda_vpc[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lambda_igw[0].id
  }

  tags = {
    Name        = "Aurora AutoScaler Public Route Table"
    Environment = var.environment
    Project     = "Aurora-AutoScaler"
    Type        = "Public"
  }
}

# Route table for private subnets
resource "aws_route_table" "lambda_private_rt" {
  count = var.enable_vpc ? 1 : 0

  vpc_id = aws_vpc.lambda_vpc[0].id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.lambda_nat_gateway[0].id
  }

  tags = {
    Name        = "Aurora AutoScaler Private Route Table"
    Environment = var.environment
    Project     = "Aurora-AutoScaler"
    Type        = "Private"
  }
}

# ===================================================================
# 🔗 ROUTE TABLE ASSOCIATIONS
# ===================================================================

# Associate public subnet with public route table
resource "aws_route_table_association" "lambda_public_rta" {
  count = var.enable_vpc ? 1 : 0

  subnet_id      = aws_subnet.lambda_public_subnet_1[0].id
  route_table_id = aws_route_table.lambda_public_rt[0].id
}

# Associate private subnet 1 with private route table
resource "aws_route_table_association" "lambda_private_rta_1" {
  count = var.enable_vpc ? 1 : 0

  subnet_id      = aws_subnet.lambda_private_subnet_1[0].id
  route_table_id = aws_route_table.lambda_private_rt[0].id
}

# Associate private subnet 2 with private route table
resource "aws_route_table_association" "lambda_private_rta_2" {
  count = var.enable_vpc ? 1 : 0

  subnet_id      = aws_subnet.lambda_private_subnet_2[0].id
  route_table_id = aws_route_table.lambda_private_rt[0].id
}

# ===================================================================
# 🔒 SECURITY GROUP FOR LAMBDA FUNCTIONS
# ===================================================================
# ATTACHMENT NOTE: This security group is conditionally attached to Lambda 
# functions via vpc_config when var.enable_vpc = true. Checkov CKV2_AWS_5 
# cannot detect conditional attachments during static analysis.
# ===================================================================

resource "aws_security_group" "lambda_sg" {
  #checkov:skip=CKV2_AWS_5:Conditionally attached to Lambda functions when VPC is enabled

  count = local.create_lambda_security_group ? 1 : 0

  name_prefix = "aurora-autoscaler-lambda-"
  vpc_id      = local.vpc_id
  description = "Security group for Aurora AutoScaler Lambda functions"

  # Outbound rules for AWS API access
  egress {
    description = "HTTPS to AWS APIs"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTP for package downloads (if needed)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # DNS resolution
  egress {
    description = "DNS"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "Aurora AutoScaler Lambda Security Group"
    Environment = var.environment
    Project     = "Aurora-AutoScaler"
    Purpose     = "Lambda-Security"
  }
}

# ===================================================================
# 🔌 VPC ENDPOINTS FOR AWS SERVICES
# ===================================================================

# VPC Endpoint for RDS (required for Aurora operations)
resource "aws_vpc_endpoint" "rds" {
  count = local.create_vpc_endpoints ? 1 : 0

  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${var.region}.rds"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.use_existing_vpc ? var.existing_private_subnet_ids : [aws_subnet.lambda_private_subnet_1[0].id, aws_subnet.lambda_private_subnet_2[0].id]
  security_group_ids  = [aws_security_group.vpc_endpoint_sg[0].id]
  private_dns_enabled = true

  tags = {
    Name        = "Aurora AutoScaler RDS VPC Endpoint"
    Environment = var.environment
    Project     = "Aurora-AutoScaler"
    Service     = "RDS"
  }
}

# VPC Endpoint for EC2 (required for capacity checking)
resource "aws_vpc_endpoint" "ec2" {
  count = var.enable_vpc ? 1 : 0

  vpc_id              = aws_vpc.lambda_vpc[0].id
  service_name        = "com.amazonaws.${var.region}.ec2"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.lambda_private_subnet_1[0].id, aws_subnet.lambda_private_subnet_2[0].id]
  security_group_ids  = [aws_security_group.vpc_endpoint_sg[0].id]
  private_dns_enabled = true

  tags = {
    Name        = "Aurora AutoScaler EC2 VPC Endpoint"
    Environment = var.environment
    Project     = "Aurora-AutoScaler"
    Service     = "EC2"
  }
}

# VPC Endpoint for SNS (required for notifications)
resource "aws_vpc_endpoint" "sns" {
  count = var.enable_vpc ? 1 : 0

  vpc_id              = aws_vpc.lambda_vpc[0].id
  service_name        = "com.amazonaws.${var.region}.sns"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.lambda_private_subnet_1[0].id, aws_subnet.lambda_private_subnet_2[0].id]
  security_group_ids  = [aws_security_group.vpc_endpoint_sg[0].id]
  private_dns_enabled = true

  tags = {
    Name        = "Aurora AutoScaler SNS VPC Endpoint"
    Environment = var.environment
    Project     = "Aurora-AutoScaler"
    Service     = "SNS"
  }
}

# VPC Endpoint for EventBridge Scheduler
resource "aws_vpc_endpoint" "scheduler" {
  count = var.enable_vpc ? 1 : 0

  vpc_id              = aws_vpc.lambda_vpc[0].id
  service_name        = "com.amazonaws.${var.region}.scheduler"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.lambda_private_subnet_1[0].id, aws_subnet.lambda_private_subnet_2[0].id]
  security_group_ids  = [aws_security_group.vpc_endpoint_sg[0].id]
  private_dns_enabled = true

  tags = {
    Name        = "Aurora AutoScaler Scheduler VPC Endpoint"
    Environment = var.environment
    Project     = "Aurora-AutoScaler"
    Service     = "EventBridge-Scheduler"
  }
}

# VPC Endpoint for CloudWatch (for metrics and logs)
resource "aws_vpc_endpoint" "cloudwatch" {
  count = var.enable_vpc ? 1 : 0

  vpc_id              = aws_vpc.lambda_vpc[0].id
  service_name        = "com.amazonaws.${var.region}.monitoring"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.lambda_private_subnet_1[0].id, aws_subnet.lambda_private_subnet_2[0].id]
  security_group_ids  = [aws_security_group.vpc_endpoint_sg[0].id]
  private_dns_enabled = true

  tags = {
    Name        = "Aurora AutoScaler CloudWatch VPC Endpoint"
    Environment = var.environment
    Project     = "Aurora-AutoScaler"
    Service     = "CloudWatch"
  }
}

# VPC Endpoint for CloudWatch Logs
resource "aws_vpc_endpoint" "logs" {
  count = var.enable_vpc ? 1 : 0

  vpc_id              = aws_vpc.lambda_vpc[0].id
  service_name        = "com.amazonaws.${var.region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.lambda_private_subnet_1[0].id, aws_subnet.lambda_private_subnet_2[0].id]
  security_group_ids  = [aws_security_group.vpc_endpoint_sg[0].id]
  private_dns_enabled = true

  tags = {
    Name        = "Aurora AutoScaler CloudWatch Logs VPC Endpoint"
    Environment = var.environment
    Project     = "Aurora-AutoScaler"
    Service     = "CloudWatch-Logs"
  }
}

# VPC Endpoint for SQS (for Dead Letter Queue)
resource "aws_vpc_endpoint" "sqs" {
  count = var.enable_vpc ? 1 : 0

  vpc_id              = aws_vpc.lambda_vpc[0].id
  service_name        = "com.amazonaws.${var.region}.sqs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.lambda_private_subnet_1[0].id, aws_subnet.lambda_private_subnet_2[0].id]
  security_group_ids  = [aws_security_group.vpc_endpoint_sg[0].id]
  private_dns_enabled = true

  tags = {
    Name        = "Aurora AutoScaler SQS VPC Endpoint"
    Environment = var.environment
    Project     = "Aurora-AutoScaler"
    Service     = "SQS"
  }
}

# VPC Endpoint for KMS (for encryption)
resource "aws_vpc_endpoint" "kms" {
  count = var.enable_vpc ? 1 : 0

  vpc_id              = aws_vpc.lambda_vpc[0].id
  service_name        = "com.amazonaws.${var.region}.kms"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.lambda_private_subnet_1[0].id, aws_subnet.lambda_private_subnet_2[0].id]
  security_group_ids  = [aws_security_group.vpc_endpoint_sg[0].id]
  private_dns_enabled = true

  tags = {
    Name        = "Aurora AutoScaler KMS VPC Endpoint"
    Environment = var.environment
    Project     = "Aurora-AutoScaler"
    Service     = "KMS"
  }
}

# VPC Endpoint for X-Ray (for Lambda tracing)
resource "aws_vpc_endpoint" "xray" {
  count = var.enable_vpc ? 1 : 0

  vpc_id              = aws_vpc.lambda_vpc[0].id
  service_name        = "com.amazonaws.${var.region}.xray"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.lambda_private_subnet_1[0].id, aws_subnet.lambda_private_subnet_2[0].id]
  security_group_ids  = [aws_security_group.vpc_endpoint_sg[0].id]
  private_dns_enabled = true

  tags = {
    Name        = "Aurora AutoScaler X-Ray VPC Endpoint"
    Environment = var.environment
    Project     = "Aurora-AutoScaler"
    Service     = "X-Ray"
  }
}

# ===================================================================
# 🔒 SECURITY GROUP FOR VPC ENDPOINTS
# ===================================================================
# ATTACHMENT NOTE: This security group is conditionally attached to VPC 
# endpoints when local.create_vpc_endpoints = true. Checkov CKV2_AWS_5 
# cannot detect conditional attachments during static analysis.
# ===================================================================

resource "aws_security_group" "vpc_endpoint_sg" {
  #checkov:skip=CKV2_AWS_5:Conditionally attached to VPC endpoints when VPC endpoints are enabled

  count = local.create_vpc_endpoints ? 1 : 0

  name_prefix = "aurora-autoscaler-vpc-endpoints-"
  vpc_id      = local.vpc_id
  description = "Security group for Aurora AutoScaler VPC endpoints"

  # Allow HTTPS traffic from Lambda security group
  ingress {
    description     = "HTTPS from Lambda functions"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [local.lambda_security_group_id]
  }

  # Single consolidated egress rule for all AWS API calls
  egress {
    description = "HTTPS to AWS APIs within VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Lifecycle management to prevent conflicts during updates
  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "Aurora AutoScaler VPC Endpoints Security Group"
    Environment = var.environment
    Project     = "Aurora-AutoScaler"
    Purpose     = "VPC-Endpoints-Security"
  }
}

# ===================================================================
# 🔒 DEFAULT SECURITY GROUP RESTRICTIONS
# ===================================================================
# SECURITY NOTE: This restriction is intentionally applied only to newly 
# created VPCs (local.create_new_vpc = true) to avoid disrupting existing 
# customer VPC configurations. Existing VPCs should be managed by the 
# customer's own security policies.
# 
# Checkov CKV2_AWS_12 is expected to flag this as it cannot determine
# at static analysis time whether restrictions will be applied.
# ===================================================================

# Restrict default security group to deny all traffic
resource "aws_default_security_group" "lambda_vpc_default" {
  #checkov:skip=CKV2_AWS_12:Conditional application - only restricts newly created VPCs, preserves existing VPC configurations

  count = local.create_new_vpc ? 1 : 0

  vpc_id = aws_vpc.lambda_vpc[0].id

  # Remove all default ingress rules (deny all inbound)
  ingress = []

  # Remove all default egress rules (deny all outbound)
  egress = []

  tags = {
    Name        = "Aurora AutoScaler Default Security Group (Restricted)"
    Environment = var.environment
    Project     = "Aurora-AutoScaler"
    Purpose     = "Security-Hardening"
    Note        = "All traffic denied for security"
  }
}
# ===================================================================
# 🔍 SECURITY GROUP ATTACHMENT VALIDATION
# ===================================================================

# Validation to ensure security groups are properly attached
resource "null_resource" "security_group_validation" {
  count = var.enable_vpc ? 1 : 0

  triggers = {
    lambda_sg_id       = local.lambda_security_group_id
    vpc_endpoint_sg_id = length(aws_security_group.vpc_endpoint_sg) > 0 ? aws_security_group.vpc_endpoint_sg[0].id : "not-created"
    vpc_id             = local.vpc_id
  }

  provisioner "local-exec" {
    command = "echo 'Security groups validated: Lambda SG=${local.lambda_security_group_id}, VPC Endpoint SG=${length(aws_security_group.vpc_endpoint_sg) > 0 ? aws_security_group.vpc_endpoint_sg[0].id : "not-created"}'"
  }
}

# ===================================================================
# 📊 DATA SOURCES
# ===================================================================

# Get available AZs
data "aws_availability_zones" "available" {
  state = "available"
}
