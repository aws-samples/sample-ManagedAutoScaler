# Aurora AutoScaler - Quick Deployment Guide

This guide provides step-by-step instructions for deploying the Aurora PostgreSQL Auto-Scaling System.

## 🚀 Quick Start

### 1. Prerequisites Check

Ensure you have the following installed:
- AWS CLI (configured with appropriate permissions)
- Terraform ≥ 1.0
- Python ≥ 3.13
- Git

### 2. Clone Repository

```bash
git clone <your-repository-url>
cd aurora-autoscaler-clean
```

### 3. Configure Variables

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your specific values:

```hcl
# Required Variables
region = "us-east-1"                    # Your AWS region
db_cluster_id = "my-aurora-cluster"     # Your Aurora cluster ID
notification_email = "admin@company.com" # Email for notifications

# Optional Customizations
cpu_threshold = 15.0                    # CPU threshold for scale-down
cpu_lookback_minutes = 10               # Evaluation period
preferred_instance_type = "db.r6g.large"
instance_types_priority = ["db.r6g.large", "db.r6g.xlarge", "db.r5.large"]
availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
fallback_strategy = "az-priority"

# Security Features
enable_sns = true
enable_security_hardening = true
enable_cloudtrail = true
enable_access_analyzer = true
```

### 4. Deploy Using Script

```bash
cd ..  # Back to root directory
./deploy.sh
```

The script will:
- Check prerequisites
- Build Lambda packages
- Initialize Terraform
- Create deployment plan
- Deploy infrastructure (with confirmation)

### 5. Manual Deployment (Alternative)

If you prefer manual deployment:

```bash
# Build Lambda packages
cd lambda_builds
pip install -r requirements.txt -t .
zip -r autoscale_up.zip autoscale_up.py boto3/ botocore/ urllib3/ s3transfer/ jmespath/ dateutil/ six.py
zip -r downscale.zip downscale.py boto3/ botocore/ urllib3/ s3transfer/ jmespath/ dateutil/ six.py

# Deploy with Terraform
cd ../terraform
terraform init
terraform plan
terraform apply
```

## 🔧 Post-Deployment

### Verify Deployment

1. **Check Lambda Functions**
   ```bash
   aws lambda list-functions --query 'Functions[?contains(FunctionName, `aurora`)]'
   ```

2. **Verify EventBridge Rules**
   ```bash
   aws events list-rules --query 'Rules[?contains(Name, `rds`)]'
   ```

3. **Check SNS Topic**
   ```bash
   aws sns list-topics --query 'Topics[?contains(TopicArn, `aurora`)]'
   ```

### Monitor Logs

```bash
# Scale-up Lambda logs
aws logs tail /aws/lambda/aurora-autoscale-up --follow

# Scale-down Lambda logs
aws logs tail /aws/lambda/aurora-downscale --follow
```

## 🧪 Testing

### Test Scale-Up (Simulate RDS Event)

```bash
aws events put-events --entries '[{
  "Source": "aws.rds",
  "DetailType": "RDS DB Instance Event",
  "Detail": "{\"EventCategories\":[\"availability\"],\"SourceId\":\"your-cluster-id\",\"EventID\":\"RDS-EVENT-0031\",\"Message\":\"Insufficient capacity\"}"
}]'
```

### Monitor Scale-Down

The system automatically monitors CPU utilization every minute and scales down when thresholds are met.

## 🔒 Security Verification

### Check IAM Policies

```bash
# List created roles
aws iam list-roles --query 'Roles[?contains(RoleName, `aurora`)]'

# Check policy attachments
aws iam list-attached-role-policies --role-name aurora-autoscale-up-role
```

### Verify Encryption

```bash
# Check KMS keys
aws kms list-keys --query 'Keys[*].KeyId'

# Verify Lambda encryption
aws lambda get-function --function-name aurora-autoscale-up --query 'Configuration.KMSKeyArn'
```

## 🧹 Cleanup

To remove all resources:

```bash
cd terraform
terraform destroy
```

**Warning**: This will delete all created resources. Aurora reader instances will remain but won't be automatically managed.

## 📊 Monitoring

### CloudWatch Dashboards

The system creates CloudWatch logs for monitoring:
- `/aws/lambda/aurora-autoscale-up`
- `/aws/lambda/aurora-downscale`

### SNS Notifications

If enabled, you'll receive email notifications for:
- Successful scaling events
- Failures and errors
- Capacity issues

### Key Metrics to Monitor

- Lambda execution duration
- RDS instance creation success rate
- CPU utilization patterns
- Scaling event frequency

## 🔧 Troubleshooting

### Common Issues

1. **Permission Errors**
   - Verify AWS CLI credentials
   - Check IAM permissions for deployment user
   - Ensure Aurora cluster exists

2. **Terraform Errors**
   - Run `terraform validate`
   - Check variable values in `terraform.tfvars`
   - Verify AWS provider configuration

3. **Lambda Build Errors**
   - Ensure Python 3.13+ is installed
   - Check pip dependencies
   - Verify zip utility is available

4. **Deployment Failures**
   - Check AWS service limits
   - Verify region availability
   - Review CloudTrail logs

### Getting Help

- Check CloudWatch logs for detailed error messages
- Review Terraform plan output
- Consult AWS documentation for service-specific issues
- Open GitHub issues for bugs or feature requests

## 📈 Performance Tuning

### Optimize for Your Workload

1. **Adjust CPU Thresholds**
   - Lower thresholds for aggressive scaling
   - Higher thresholds for cost optimization

2. **Modify Lookback Periods**
   - Shorter periods for faster response
   - Longer periods for stability

3. **Instance Type Selection**
   - Prioritize cost-effective instances
   - Consider performance requirements

4. **Availability Zone Strategy**
   - Use `az-priority` for geographic distribution
   - Use `instance-priority` for specific instance types

## 🔄 Updates and Maintenance

### Updating the System

```bash
git pull
./deploy.sh
```

### Regular Maintenance

- Monitor CloudWatch logs weekly
- Review scaling patterns monthly
- Update instance types as needed
- Rotate KMS keys annually (if manual rotation)

---

For detailed information, see the main [README.md](README.md) file.
