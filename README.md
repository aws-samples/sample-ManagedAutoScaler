# Aurora PostgreSQL Auto-Scaling System Overview

This automated scaling solution for Amazon Aurora PostgreSQL reader instances extends Aurora's built-in auto-scaling capabilities to handle capacity constraints by automatically provisioning reader instances across multiple availability zones (AZs) and instance types. Built using AWS Lambda and EventBridge, the solution features an event-driven architecture with two primary components: a scale-up Lambda function triggered by RDS insufficient capacity events (RDS-EVENT-0031), and a scale-down function that monitors CPU utilization to remove underutilized readers. This provides enhanced availability during capacity constraints and zero manual intervention.

## Why This Solution?

Aurora's built-in auto-scaling may fail when your preferred instance type has insufficient capacity in a specific availability zone. This can leave your database unable to scale during critical demand periods.

**The Solution:**
This event-driven architecture automatically:
- Detects when Aurora auto-scaling fails due to capacity constraints (RDS-EVENT-0031)
- Intelligently provisions reader instances using alternative instance types and/or availability zones
- Scales down automatically when demand decreases
- Maintains optimal performance while avoiding over-provisioning costs

**Key Benefits:**
- **Enhanced Availability**: Automatically finds available capacity across multiple AZs and instance types
- **Cost Efficiency**: Scales down underutilized readers automatically based on CPU thresholds
- **Zero Manual Intervention**: Fully automated response to scaling events
- **Flexible Strategies**: Choose between instance-priority or AZ-priority scaling approaches

## 🚀 Features

* **Intelligent Scale-Up**: Triggered by RDS insufficient capacity events (RDS-EVENT-0031) with smart instance type and AZ selection
* **Automatic Scale-Down**: CPU utilization-based scaling with configurable thresholds and lookback periods
* **Multi-AZ Resilience**: Smart placement across availability zones for optimal distribution
* **Comprehensive Monitoring**: CloudWatch integration with detailed timing and performance metrics
* **Security-First Architecture**: Least privilege IAM policies, KMS encryption, and DLQ implementation
* **Flexible Notification System**: Optional SNS alerts with customizable email notifications
* **Dynamic State Management**: EventBridge Scheduler for continuous monitoring and management
* **Capacity Intelligence**: EC2 capacity checking before instance creation attempts

## 🔍 Architecture Diagram

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   RDS Aurora    │───▶│   EventBridge    │───▶│  Lambda Scale   │
│   Cluster       │    │   (RDS Events)   │    │      Up         │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                                         │
                                                         ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   CloudWatch    │◀───│   EventBridge    │◀───│  New Reader     │
│   Metrics       │    │   Scheduler      │    │   Instance      │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                       │
         ▼                       ▼
┌─────────────────┐    ┌─────────────────┐
│  Lambda Scale   │    │   SNS Topic     │
│     Down        │    │ (Notifications) │
└─────────────────┘    └─────────────────┘
```
<img width="438" height="385" alt="image" src="https://github.com/user-attachments/assets/e1dc60ed-fd2e-4924-93fe-05da7ac56afb" />


## 💡 Solution Value

This solution enhances Aurora's auto-scaling capabilities to deliver additional operational flexibility and resilience:

| Capability | Native Aurora Auto Scaling | Enhanced with This Solution |
|----------|---------------------------|-------------------|
| Instance type flexibility | Single type |  Automatically leverages alternative instance types |
| Multi-AZ adaptation | Single AZ attempt | Seamlessly provisions across multiple AZs |
| Scale-down automation | Manual monitoring and intervention | Automatic optimization based on CPU metrics |
| Capacity planning | Static provisioning approach | Dynamic adaptation to real-time capacity availability |
| Cost management | Periodic manual reviews | Continuous automated optimization |

- **Scale-up response**: 3-8 minutes (automated vs. manual intervention)
- **Scale-down**: Continuous monitoring vs. periodic manual review

## 📁 Project Structure

```
.
├── lambda_builds/
│   ├── autoscale_up.py          # Main scale-up Lambda function
│   ├── downscale.py             # Scale-down Lambda function
│   ├── requirements.txt         # Python dependencies
│   ├── autoscale_up.zip         # Deployment package (generated)
│   └── downscale.zip            # Deployment package (generated)
├── terraform/
│   ├── lambda.tf                # Lambda function definitions
│   ├── eventbridge.tf           # EventBridge rules for RDS events
│   ├── scheduler.tf             # EventBridge Scheduler for monitoring
│   ├── scheduler_kms.tf         # KMS encryption for EventBridge Scheduler
│   ├── sns.tf                   # SNS topic and subscriptions
│   ├── iam.tf                   # IAM roles and policies
│   ├── lambda_kms.tf            # KMS keys for Lambda encryption
│   ├── lambda_code_signing.tf   # Lambda code signing configuration
│   ├── dlq.tf                   # Dead Letter Queue configuration
│   ├── vpc.tf                   # VPC and networking configuration
│   ├── security_hardening.tf    # Additional security configurations
│   ├── validation.tf            # Resource validation rules
│   ├── variables.tf             # Input variables
│   ├── outputs.tf               # Output values
│   ├── locals.tf                # Local values
│   ├── versions.tf              # Provider versions
│   ├── provider.tf              # Provider configuration
│   └── terraform.tfvars.example # Example configuration
├── .gitignore                   # Git ignore patterns
└── LICENSE                      # MIT License
```

## ⚙️ Configuration

### Core Variables

| Variable | Description | Type | Default | Required |
|----------|-------------|------|---------|----------|
| `region` | AWS region for deployment | string | `eu-central-1` | No |
| `db_cluster_id` | Aurora DB cluster identifier | string | `database-11` | Yes |
| `db_engine` | Aurora database engine type | string | `aurora-postgresql` | No |
| `aurora_reader_tier` | Aurora reader tier (0-15, higher = lower priority) | number | `15` | No |
| `cpu_threshold` | CPU threshold for scale-down (%) | number | `10.0` | No |
| `cpu_lookback_minutes` | CPU metric evaluation period | number | `5` | No |
| `cloudwatch_period` | Metric aggregation period (seconds) | number | `60` | No |

### Database Engine Configuration

The `db_engine` variable determines the Aurora database engine type used when creating new reader instances:

| Engine Type | Description | Use Case |
|-------------|-------------|----------|
| `aurora-postgresql` | Aurora PostgreSQL-Compatible Edition | PostgreSQL workloads, advanced features |
| `aurora-mysql` | Aurora MySQL-Compatible Edition | MySQL workloads, MySQL compatibility |

**Important**: The `db_engine` value must match your existing Aurora cluster's engine type.

### Instance Configuration

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| `preferred_instance_type` | Primary instance type | string | `db.r5.large` |
| `instance_types_priority` | Fallback instance types | list(string) | `["db.r5.large", "db.r5.xlarge", "db.r6g.large", "db.r6g.xlarge"]` |
| `availability_zones` | Preferred AZs for deployment | list(string) | `["eu-central-1a", "eu-central-1b", "eu-central-1c"]` |
| `fallback_strategy` | Instance selection strategy | string | `instance-priority` |

### Notification Settings

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| `enable_sns` | Enable SNS notifications | bool | `true` |
| `sns_topic_arn` | Existing SNS topic ARN (optional) | string | `""` |
| `notification_email` | Email for notifications | string | `your-email@example.com` |

### Security Hardening

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| `enable_security_hardening` | Enable security features | bool | `true` |
| `enable_cloudtrail` | Enable CloudTrail logging | bool | `true` |
| `enable_access_analyzer` | Enable IAM Access Analyzer | bool | `true` |
| `max_session_duration` | Max IAM session duration (seconds) | number | `3600` |
| `dlq_message_retention_seconds` | DLQ message retention | number | `1209600` |

### Fallback Strategies

| Strategy | Description | Use Case |
|----------|-------------|----------|
| `instance-priority` | Prioritizes instance type over AZ | When specific instance types are critical |
| `az-priority` | Prioritizes AZ distribution over instance type | When geographic distribution is critical |

## 🛠️ Deployment

### Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform ≥ 1.0
- Python ≥ 3.13
- Aurora PostgreSQL cluster already deployed

### Required AWS Permissions

The deployment requires permissions for:
- Lambda (create, update, invoke)
- EventBridge (rules, targets, schedules)
- RDS (describe clusters/instances, create instances)
- EC2 (describe capacity reservations, availability zones)
- CloudWatch (metrics, logs)
- SNS (topics, subscriptions)
- IAM (roles, policies)
- KMS (keys, encryption)
- SQS (DLQ management)

### Step-by-Step Deployment

1. **Clone and Configure**
   ```bash
   git clone <repository-url>
   cd aurora-autoscaler-clean
   ```

2. **Create Configuration**
   ```bash
   cd terraform
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your specific values
   ```

3. **Build Lambda Packages**
   ```bash
   cd ../lambda_builds/
   pip install -r requirements.txt -t .
   zip -r autoscale_up.zip autoscale_up.py boto3/ botocore/ urllib3/ s3transfer/ jmespath/ python_dateutil/ six.py
   zip -r downscale.zip downscale.py boto3/ botocore/ urllib3/ s3transfer/ jmespath/ python_dateutil/ six.py
   cd ../terraform
   ```

4. **Initialize and Deploy**
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

### Example terraform.tfvars

```hcl
region = "us-east-1"
db_cluster_id = "my-aurora-cluster"
db_engine = "aurora-postgresql"
aurora_reader_tier = 15
cpu_threshold = 15.0
cpu_lookback_minutes = 10
notification_email = "admin@company.com"
preferred_instance_type = "db.r6g.large"
instance_types_priority = ["db.r6g.large", "db.r6g.xlarge", "db.r5.large"]
availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
fallback_strategy = "az-priority"
enable_sns = true
enable_security_hardening = true
enable_cloudtrail = true
enable_access_analyzer = true
```

## 🔄 How It Works

### Scale-Up Process (3-8 minutes total)

1. **Event Detection** (< 1 second)
   - RDS generates RDS-EVENT-0031 insufficient capacity event
   - EventBridge rule captures event with pattern matching

2. **Lambda Execution** (25-35 seconds)
   - Analyzes current reader distribution across AZs
   - Checks EC2 capacity availability
   - Attempts preferred instance type first
   - Falls back to alternative types/AZs based on strategy
   - Initiates RDS reader instance creation

3. **RDS Provisioning** (3-8 minutes)
   - AWS provisions the new reader instance
   - Instance becomes available for connections

### Scale-Down Process (continuous)

1. **Scheduled Monitoring** (every minute)
   - EventBridge Scheduler triggers downscale Lambda
   - Evaluates CPU utilization for all readers
   - Identifies instances below threshold for specified duration

2. **Intelligent Removal**
   - Maintains minimum reader count
   - Preserves AZ distribution
   - Gracefully terminates low-utilization instances

## 📊 Monitoring and Observability

### CloudWatch Logs

- **Autoscale-up**: `/aws/lambda/aurora-autoscale-up`
- **Downscale**: `/aws/lambda/aurora-downscale`

### Key Metrics Tracked

- Lambda execution duration and memory usage
- RDS instance creation success/failure rates
- CPU utilization patterns
- Capacity availability across AZs
- Scaling event frequency

### SNS Notifications

Receive alerts for:
- Successful reader instance creation
- Scaling failures and capacity issues
- Configuration changes
- Error conditions

## ⚠️ Production Deployment Considerations

### Critical Production Guidelines

Before deploying this auto-scaling solution in production, carefully consider these important factors:

#### Writer Failover Impact
- **Cost Implications**: If the writer fails over to a larger reader instance created by the Lambda function, you'll incur additional costs. When reverting to the original smaller instance size, expect performance differences as you return to the baseline configuration.
- **Performance Risk**: Never allow failover to smaller instance sizes than the original writer - this can severely impact database performance and application stability.
- **Sizing Strategy**: Always ensure reader instances are equal to or larger than the writer instance to maintain performance consistency during failover scenarios.

#### Availability Zone Distribution
- **Single AZ Risk**: Having all readers and/or the writer in a single AZ creates significant production downtime risk during AZ failures.
- **Minimum AZ Coverage**: Always maintain at least one reader per availability zone to ensure high availability and disaster recovery capabilities.
- **Distribution Monitoring**: Regularly verify that your auto-scaling configuration maintains proper AZ distribution as instances are added and removed.

#### Instance Type Selection and Compatibility
- **Minimum Size Requirements**: Define instance pools with minimum size requirements based on your writer instance specifications.
- **Compatible Instance Pools**: Create pools of compatible instance types that have been thoroughly tested for your workload.
- **Performance Validation**: Validate performance across different instance types and sizes before adding them to your production pool.
- **Testing Protocol**: Establish a testing protocol to verify that each instance type in your pool can handle your production workload without degradation.

#### Aurora Priority Tier Configuration
- **Writer Failover Priority**: Set instances of the same type and size as the writer to the highest priority tier (tier 0-1) to ensure optimal failover targets.
- **Reader Tier Strategy**: Configure reader instances with appropriate priority tiers (typically 2-15) based on their capacity and role in your architecture.
- **Tier Planning**: Plan your tier structure to ensure the most capable instances are prioritized for writer failover scenarios.

#### Monitoring and Alerting Recommendations
- Monitor AZ distribution of instances continuously
- Set up cost alerts for unexpected scaling to larger instances
- Track failover events and their impact on performance
- Monitor CPU and memory utilization across different instance types
- Alert on single AZ concentration of critical instances

## 🔧 Maintenance

### Updating the System

```bash
git pull
cd terraform
terraform plan
terraform apply
```

### Monitoring Health

```bash
# Check recent Lambda executions
aws logs filter-log-events \
  --log-group-name /aws/lambda/aurora-autoscale-up \
  --start-time $(date -d '1 hour ago' +%s)000

# Verify EventBridge rule status
aws events describe-rule --name rds-insufficient-capacity
```



## 🧹 Cleanup

To remove all resources:

```bash
cd terraform
terraform destroy
```

**Warning**: This will delete all Lambda functions, EventBridge rules, and associated resources. Reader instances will remain but won't be automatically managed.

## 🔒 Security Features

- **Least Privilege IAM**: Minimal required permissions for each component
- **Encryption at Rest**: KMS encryption for Lambda environment variables and DLQ
- **Encryption in Transit**: All AWS API calls use TLS
- **Dead Letter Queue**: Failed Lambda executions captured for analysis
- **CloudTrail Integration**: Optional audit logging for compliance
- **Access Analyzer**: Identifies overly permissive policies
- **Lambda Code Signing**: Ensures code integrity and authenticity
- **VPC Integration**: Network isolation and security groups
- **KMS Key Rotation**: Automatic key rotation for enhanced security

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
