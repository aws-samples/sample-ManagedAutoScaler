#!/bin/bash

# Aurora AutoScaler Deployment Script
# This script builds Lambda packages and deploys the infrastructure

set -e

echo "🚀 Aurora AutoScaler Deployment Script"
echo "======================================"

# Check prerequisites
echo "📋 Checking prerequisites..."

# Check if terraform is installed
if ! command -v terraform &> /dev/null; then
    echo "❌ Terraform is not installed. Please install Terraform >= 1.0"
    exit 1
fi

# Check if python3 is installed
if ! command -v python3 &> /dev/null; then
    echo "❌ Python 3 is not installed. Please install Python >= 3.13"
    exit 1
fi

# Check if pip is installed
if ! command -v pip &> /dev/null; then
    echo "❌ pip is not installed. Please install pip"
    exit 1
fi

# Check if aws cli is installed
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI is not installed. Please install AWS CLI"
    exit 1
fi

# Check if zip is installed
if ! command -v zip &> /dev/null; then
    echo "❌ zip is not installed. Please install zip utility"
    exit 1
fi

echo "✅ All prerequisites met"

# Check if terraform.tfvars exists
if [ ! -f "terraform/terraform.tfvars" ]; then
    echo "⚠️  terraform.tfvars not found. Creating from example..."
    cp terraform/terraform.tfvars.example terraform/terraform.tfvars
    echo "📝 Please edit terraform/terraform.tfvars with your configuration before continuing"
    echo "   Required: db_cluster_id, region, notification_email"
    read -p "Press Enter to continue after editing terraform.tfvars..."
fi

# Build Lambda packages
echo "🔨 Building Lambda packages..."
cd lambda_builds

# Clean previous builds
rm -f *.zip
rm -rf boto3* botocore* urllib3* s3transfer* jmespath* dateutil* six.py *dist-info bin

# Install dependencies
echo "📦 Installing Python dependencies..."
pip install -r requirements.txt -t . --quiet

# Create autoscale_up.zip
echo "📦 Creating autoscale_up.zip..."
zip -r autoscale_up.zip autoscale_up.py boto3/ botocore/ urllib3/ s3transfer/ jmespath/ dateutil/ six.py > /dev/null

# Create downscale.zip
echo "📦 Creating downscale.zip..."
zip -r downscale.zip downscale.py boto3/ botocore/ urllib3/ s3transfer/ jmespath/ dateutil/ six.py > /dev/null

echo "✅ Lambda packages built successfully"

# Move to terraform directory
cd ../terraform

# Initialize Terraform
echo "🔧 Initializing Terraform..."
terraform init

# Validate configuration
echo "🔍 Validating Terraform configuration..."
terraform validate

# Plan deployment
echo "📋 Creating deployment plan..."
terraform plan -out=tfplan

# Ask for confirmation
echo ""
echo "🚨 Ready to deploy Aurora AutoScaler infrastructure"
echo "   This will create AWS resources that may incur costs"
read -p "Do you want to proceed with deployment? (y/N): " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🚀 Deploying infrastructure..."
    terraform apply tfplan
    
    echo ""
    echo "✅ Deployment completed successfully!"
    echo ""
    echo "📊 Next steps:"
    echo "   1. Check CloudWatch logs: /aws/lambda/aurora-autoscale-up"
    echo "   2. Monitor SNS notifications if enabled"
    echo "   3. Test with RDS insufficient capacity events"
    echo ""
    echo "🔧 To update the system:"
    echo "   git pull && ./deploy.sh"
    echo ""
    echo "🧹 To cleanup resources:"
    echo "   cd terraform && terraform destroy"
else
    echo "❌ Deployment cancelled"
    rm -f tfplan
fi
