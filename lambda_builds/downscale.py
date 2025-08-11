# -------------------------------------------------------------------
# Aurora PostgreSQL Auto-Scaling Lambda Function - Scale Down Handler
# -------------------------------------------------------------------
# This Lambda function is triggered by EventBridge Scheduler every minute
# to monitor CPU utilization and remove Aurora reader instances when they
# are no longer needed, helping to optimize costs.
#
# ENHANCED SECURITY FEATURES:
# - Tag-based security filtering for instance deletion
# - Only deletes instances with required ManagedBy tags
# - Average CPU calculation across ALL readers for scaling decisions
# - Automatic EventBridge scheduler management
# - Comprehensive error handling and audit logging
#
# Trigger: EventBridge Scheduler (every minute)
# Purpose: Remove Aurora reader instances when CPU utilization is low
# Strategy: Monitor average CPU across all readers, delete most recent tagged Lambda readers
# -------------------------------------------------------------------

# ========================
# 📦 IMPORTS AND LOGGING SETUP
# ========================
import boto3          # AWS SDK for Python - interact with AWS services
import os             # Operating system interface - access environment variables
from datetime import datetime, timedelta  # Date and time operations for metric queries
import logging        # Python logging framework for CloudWatch logs
import json           # JSON operations for SNS messaging

# Configure logging for CloudWatch - all log messages will appear in 
# /aws/lambda/aurora-downscale log group
logger = logging.getLogger()
logger.setLevel(logging.INFO)  # Log INFO level and above (INFO, WARNING, ERROR)

# ========================
# 🔧 AWS CLIENT SETUP
# ========================
# Initialize AWS service clients for different services
# These clients will be reused throughout the function execution

# Get AWS region from environment variable, default to eu-central-1
region = os.getenv('REGION', 'eu-central-1')

# RDS client - used for Aurora cluster and instance operations
rds = boto3.client('rds', region_name=region)

# CloudWatch client - used for retrieving CPU utilization metrics
cloudwatch = boto3.client('cloudwatch', region_name=region)

# EventBridge Scheduler client - used to disable the schedule when no readers remain
scheduler = boto3.client('scheduler', region_name=region)

# ========================
# ⚙️ ENVIRONMENT VARIABLES CONFIGURATION (ORIGINAL - UNCHANGED)
# ========================
# These variables are set by Terraform and control the function behavior

# REQUIRED: Aurora cluster identifier that this function will monitor
DB_CLUSTER_ID = os.getenv('DB_CLUSTER_ID')

# OPTIONAL: SNS topic ARN for notifications (can be empty to disable notifications)
SNS_TOPIC_ARN = os.getenv('SNS_TOPIC_ARN')

# EventBridge Scheduler name - this is the schedule that triggers this function
EVENTBRIDGE_SCHEDULE_NAME = 'aurora-cpu-monitor-every-minute'

# CPU utilization threshold (percentage) - readers below this will be candidates for removal
# Default: 10.0% - if average CPU across all readers is below this, remove a reader
CPU_THRESHOLD = float(os.getenv('CPU_THRESHOLD', '10.0'))

# Time window (minutes) to look back for CPU metrics
# Default: 5 minutes - analyze CPU data from the last 5 minutes
CPU_LOOKBACK_MINUTES = int(os.getenv('CPU_LOOKBACK_MINUTES', '5'))

# CloudWatch metrics period (seconds) - granularity of CPU data points
# Default: 60 seconds - get CPU averages for each minute
CLOUDWATCH_PERIOD = int(os.getenv('CLOUDWATCH_PERIOD', '60'))

# Boolean flag to enable/disable SNS notifications
# Converts string environment variable to boolean
ENABLE_SNS = os.getenv('ENABLE_SNS', 'false').lower() == 'true'

# ========================
# 🏷️ SECURE TAGGING CONFIGURATION (NEW ADDITION)
# ========================
# These tags must be present on instances for them to be eligible for deletion
# This protects manually created instances from accidental deletion
REQUIRED_TAGS_FOR_DELETION = {
    'ManagedBy': 'aurora-autoscaler',
    'AutoScaler': 'lambda-managed'
}

# ========================
# 🔒 SECURE TAG CHECKING FUNCTION (ENHANCED)
# ========================
def is_lambda_managed_instance(instance_identifier):
    """
    Check if an instance has the required tags for safe deletion.
    
    Args:
        instance_identifier (str): RDS instance identifier
    
    Returns:
        bool: True if instance is lambda-managed and safe to delete, False otherwise
    
    Security:
        - Only instances with required tags can be deleted
        - Protects manually created instances from accidental deletion
        - Comprehensive error handling and audit logging
        - Fails safely (no deletion) if tag verification fails
    """
    try:
        logger.info(f"Verifying tags for instance: {instance_identifier}")
        
        # Get the instance ARN for tag lookup
        instance_response = rds.describe_db_instances(DBInstanceIdentifier=instance_identifier)
        
        if not instance_response.get('DBInstances'):
            logger.warning(f"No instance found with identifier: {instance_identifier}")
            return False
            
        instance_arn = instance_response['DBInstances'][0]['DBInstanceArn']
        logger.info(f"Instance ARN: {instance_arn}")
        
        # Get tags for the instance
        tags_response = rds.list_tags_for_resource(ResourceName=instance_arn)
        instance_tags = {tag['Key']: tag['Value'] for tag in tags_response.get('TagList', [])}
        
        logger.info(f"Instance tags: {instance_tags}")
        
        # Check if instance has required tags for deletion
        missing_tags = []
        for key, expected_value in REQUIRED_TAGS_FOR_DELETION.items():
            actual_value = instance_tags.get(key)
            if actual_value != expected_value:
                missing_tags.append(f"{key}={expected_value} (found: {actual_value})")
        
        if missing_tags:
            logger.info(f"PROTECTED: Instance {instance_identifier} missing required tags: {', '.join(missing_tags)}")
            return False
        
        logger.info(f"VERIFIED: Instance {instance_identifier} has all required tags and is eligible for deletion")
        return True
        
    except Exception as e:
        logger.error(f"Error checking tags for {instance_identifier}: {str(e)}")
        # If we can't verify tags, err on the side of caution and don't delete
        logger.warning(f"SECURITY: Tag verification failed for {instance_identifier}, deletion blocked for safety")
        return False

# ========================
# 📧 SNS NOTIFICATION HELPER FUNCTION (ENHANCED)
# ========================
def notify(subject, message):
    """
    Send SNS notification if enabled and configured.
    
    Args:
        subject (str): Email subject line
        message (str): Email message body
    
    Returns:
        None
    
    Features:
        - Only sends if ENABLE_SNS is True and SNS_TOPIC_ARN is configured
        - Enhanced error handling and logging
        - Non-blocking - failures don't crash the function
        - Includes timestamp in notifications
    """
    # Skip notification if SNS is disabled or topic ARN is not configured
    if not ENABLE_SNS or not SNS_TOPIC_ARN:
        logger.debug("SNS notifications disabled or topic ARN not configured")
        return
    
    try:
        # Create SNS client
        sns = boto3.client("sns", region_name=region)
        
        # Add timestamp to message
        timestamp = datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')
        enhanced_message = f"[{timestamp}] {message}"
        
        # Publish message to SNS topic
        response = sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=subject,
            Message=enhanced_message
        )
        
        logger.info(f"SNS notification sent successfully. MessageId: {response.get('MessageId', 'Unknown')}")
        
    except Exception as e:
        # Log failure but don't crash the Lambda - notifications are not critical
        logger.error(f"Failed to send SNS notification: {str(e)}")
        logger.debug(f"SNS notification details - Subject: {subject}, Topic: {SNS_TOPIC_ARN}")

# ========================
# 🧠 MAIN LAMBDA HANDLER FUNCTION (ENHANCED LOGIC + SECURE TAG CHECK)
# ========================
def lambda_handler(event, context):
    """
    Main Lambda function handler - orchestrates the auto-scaling down logic.
    
    Args:
        event (dict): EventBridge Scheduler event (triggered every minute)
        context (object): Lambda runtime context (timeout, memory, etc.)
    
    Returns:
        dict: Success/failure status with details
    
    Enhanced Downscale Strategy:
        1. Get all reader instances from the Aurora cluster
        2. Fetch CPU utilization metrics for all readers using batch queries
        3. Calculate average CPU utilization across ALL readers
        4. If average CPU is below threshold, identify Lambda-created readers
        5. SECURITY: Verify lambda reader has required tags before deletion
        6. Delete the most recently created tagged Lambda reader
        7. Disable scheduler if no tagged Lambda readers remain
        8. Comprehensive error handling and audit logging
    """
    
    # Initialize instances list to avoid UnboundLocalError in finally block
    instances = []
    
    try:
        logger.info("=== Aurora Auto-Scaler Downscale Function Started ===")
        logger.info(f"Configuration - CPU Threshold: {CPU_THRESHOLD}%, Lookback: {CPU_LOOKBACK_MINUTES}min, Period: {CLOUDWATCH_PERIOD}s")
        
        # ========================
        # STEP 1: IDENTIFY READER INSTANCES
        # ========================
        logger.info(f"Step 1: Fetching reader instances for cluster {DB_CLUSTER_ID}...")
        
        try:
            # Get Aurora cluster information including all member instances
            cluster_response = rds.describe_db_clusters(DBClusterIdentifier=DB_CLUSTER_ID)
            
            if not cluster_response.get('DBClusters'):
                raise Exception(f"Cluster {DB_CLUSTER_ID} not found")
                
            cluster = cluster_response['DBClusters'][0]
            
            # Filter for reader instances only (exclude the writer instance)
            readers = [m['DBInstanceIdentifier'] for m in cluster['DBClusterMembers'] if not m['IsClusterWriter']]
            
        except Exception as e:
            error_msg = f"Failed to fetch cluster information: {str(e)}"
            logger.error(error_msg)
            notify("Aurora Auto-Scaler: Cluster Error", error_msg)
            return {'statusCode': 500, 'body': error_msg}

        # If no readers exist, nothing to scale down
        if not readers:
            msg = f"No reader instances found in cluster {DB_CLUSTER_ID}."
            logger.info(msg)
            notify("Aurora Auto-Scaler: Skipped", msg)
            check_and_disable_eventbridge([])
            return {'statusCode': 200, 'body': 'No readers to evaluate'}

        logger.info(f"Found {len(readers)} reader(s): {readers}")

        # ========================
        # STEP 2: FETCH CPU METRICS IN BATCH (ENHANCED)
        # ========================
        # Calculate time window for CPU metric analysis
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(minutes=CPU_LOOKBACK_MINUTES)

        logger.info(f"Step 2: Fetching CPU metrics for readers from {start_time} to {end_time}...")

        try:
            # Build metric queries for all readers in a single API call
            metric_queries = []
            for i, reader_id in enumerate(readers):
                metric_queries.append({
                    'Id': f'm{i}',
                    'MetricStat': {
                        'Metric': {
                            'Namespace': 'AWS/RDS',
                            'MetricName': 'CPUUtilization',
                            'Dimensions': [{'Name': 'DBInstanceIdentifier', 'Value': reader_id}]
                        },
                        'Period': CLOUDWATCH_PERIOD,
                        'Stat': 'Average'
                    },
                    'ReturnData': True
                })

            # Execute batch metric query
            response = cloudwatch.get_metric_data(
                MetricDataQueries=metric_queries,
                StartTime=start_time,
                EndTime=end_time
            )
            
        except Exception as e:
            error_msg = f"Failed to fetch CPU metrics: {str(e)}"
            logger.error(error_msg)
            notify("Aurora Auto-Scaler: Metrics Error", error_msg)
            return {'statusCode': 500, 'body': error_msg}

        # ========================
        # STEP 3: PROCESS CPU METRICS (ENHANCED)
        # ========================
        reader_cpu_values = []
        reader_metrics_summary = {}
        
        for result in response['MetricDataResults']:
            if result['Values']:
                reader_id = readers[int(result['Id'][1:])]  # Extract reader ID from metric ID
                reader_metrics_summary[reader_id] = {
                    'datapoints': len(result['Values']),
                    'avg_cpu': sum(result['Values']) / len(result['Values']),
                    'min_cpu': min(result['Values']),
                    'max_cpu': max(result['Values'])
                }
                
                # Collect all CPU values for overall average calculation
                reader_cpu_values.extend(result['Values'])
                
                # Log detailed metrics for debugging
                logger.info(f"Reader {reader_id}: {len(result['Values'])} datapoints, "
                          f"avg={reader_metrics_summary[reader_id]['avg_cpu']:.2f}%, "
                          f"range={reader_metrics_summary[reader_id]['min_cpu']:.2f}%-{reader_metrics_summary[reader_id]['max_cpu']:.2f}%")

        # If no CPU data is available, skip scaling decision
        if not reader_cpu_values:
            msg = f"No valid CPU datapoints found for reader instances in cluster {DB_CLUSTER_ID} over the last {CPU_LOOKBACK_MINUTES} minutes."
            logger.warning(msg)
            notify("Aurora Auto-Scaler: No Data", msg)
            check_and_disable_eventbridge([])
            return {'statusCode': 200, 'body': 'No CPU data available'}

        # ========================
        # STEP 4: EVALUATE SCALING DECISION (ENHANCED)
        # ========================
        # Calculate average CPU utilization across all readers and time periods
        avg_cpu = sum(reader_cpu_values) / len(reader_cpu_values)
        total_datapoints = len(reader_cpu_values)
        
        logger.info(f"=== CPU ANALYSIS SUMMARY ===")
        logger.info(f"Total datapoints analyzed: {total_datapoints}")
        logger.info(f"Average CPU across all readers: {avg_cpu:.2f}%")
        logger.info(f"CPU threshold for scaling: {CPU_THRESHOLD}%")
        
        # If CPU is above threshold, no scaling action needed
        if avg_cpu >= CPU_THRESHOLD:
            msg = (f"Average CPU ({avg_cpu:.2f}%) is above threshold ({CPU_THRESHOLD}%). "
                  f"No scaling action required. Analyzed {total_datapoints} datapoints across {len(readers)} readers.")
            logger.info(msg)
            notify("Aurora Auto-Scaler: No Action", msg)
            check_and_disable_eventbridge([])
            return {'statusCode': 200, 'body': 'CPU above threshold, no action needed'}

        logger.info(f"Average CPU ({avg_cpu:.2f}%) is below threshold ({CPU_THRESHOLD}%) — eligible for scale-in action.")

        # ========================
        # STEP 5: IDENTIFY LAMBDA-CREATED READERS FOR REMOVAL (ENHANCED)
        # ========================
        logger.info("Step 5: Identifying Lambda-created readers eligible for removal...")
        
        try:
            # Get all RDS instances to find Lambda-created readers
            instances = rds.describe_db_instances()['DBInstances']
            
            # Filter for Lambda-created readers that are eligible for deletion
            lambda_readers = [
                inst for inst in instances 
                if inst['DBInstanceIdentifier'].startswith('lambda-aurora-reader') 
                and inst['DBInstanceStatus'] == 'available' 
                and 'InstanceCreateTime' in inst
            ]
            
        except Exception as e:
            error_msg = f"Failed to fetch RDS instances: {str(e)}"
            logger.error(error_msg)
            notify("Aurora Auto-Scaler: Instance Fetch Error", error_msg)
            return {'statusCode': 500, 'body': error_msg}

        # If no Lambda readers exist, nothing to delete
        if not lambda_readers:
            msg = "No eligible 'lambda' readers found in 'available' state with creation time."
            logger.info(msg)
            notify("Aurora Auto-Scaler: No Lambda Readers", msg)
            check_and_disable_eventbridge(instances)
            return {'statusCode': 200, 'body': 'No lambda readers to remove'}

        logger.info(f"Found {len(lambda_readers)} lambda reader(s) eligible for evaluation")

        # ========================
        # STEP 6: DELETE MOST RECENT TAGGED LAMBDA READER (ENHANCED SECURITY)
        # ========================
        # Sort Lambda readers by creation time and select the most recent one
        latest_reader = sorted(lambda_readers, key=lambda x: x['InstanceCreateTime'])[-1]
        latest_id = latest_reader['DBInstanceIdentifier']
        created_time = latest_reader['InstanceCreateTime']

        logger.info(f"Most recent lambda reader: {latest_id} (created at {created_time})")

        # SECURITY: Verify the instance has required tags before deletion
        if not is_lambda_managed_instance(latest_id):
            msg = (f"SECURITY PROTECTION: Instance {latest_id} does not have required tags for deletion. "
                  f"Required tags: {REQUIRED_TAGS_FOR_DELETION}. Deletion blocked for safety.")
            logger.warning(msg)
            notify("Aurora Auto-Scaler: Security Protection", msg)
            check_and_disable_eventbridge(instances)
            return {'statusCode': 403, 'body': 'Instance deletion blocked - missing required tags'}

        logger.info(f"SECURITY VERIFIED: Instance {latest_id} has required tags. Proceeding with deletion.")

        try:
            # Delete the selected reader instance
            logger.info(f"Deleting reader instance: {latest_id}")
            rds.delete_db_instance(
                DBInstanceIdentifier=latest_id,
                SkipFinalSnapshot=True,
                DeleteAutomatedBackups=True
            )
            
        except Exception as e:
            error_msg = f"Failed to delete instance {latest_id}: {str(e)}"
            logger.error(error_msg)
            notify("Aurora Auto-Scaler: Deletion Error", error_msg)
            return {'statusCode': 500, 'body': error_msg}

        # Send success notification with comprehensive details
        msg = (
            f"Successfully deleted tagged lambda reader '{latest_id}' (created {created_time}). "
            f"Reason: Average CPU usage across {len(readers)} readers was {avg_cpu:.2f}% "
            f"(below threshold of {CPU_THRESHOLD}%). "
            f"Analyzed {total_datapoints} datapoints over {CPU_LOOKBACK_MINUTES} minutes. "
            f"Instance was verified with required tags before deletion."
        )
        logger.info(msg)
        notify("Aurora Auto-Scaler: Successful Deletion", msg)
        
        return {'statusCode': 200, 'body': f'Successfully deleted {latest_id}'}

    except Exception as e:
        # Handle any unexpected errors
        error_msg = f"Unexpected error in lambda_handler: {str(e)}"
        logger.error(error_msg, exc_info=True)
        notify("Aurora Auto-Scaler: Critical Error", error_msg)
        return {'statusCode': 500, 'body': error_msg}

    finally:
        # Always check if scheduler should be disabled (even if errors occurred)
        logger.info("Checking EventBridge scheduler status...")
        check_and_disable_eventbridge(instances)

# ========================
# ⏹️ EVENTBRIDGE SCHEDULER MANAGEMENT (ENHANCED)
# ========================
def check_and_disable_eventbridge(instances):
    """
    Check if any tagged Lambda-created readers remain and disable scheduler if none exist.
    
    Args:
        instances (list): List of all RDS instances from describe_db_instances()
    
    Purpose:
        - When all tagged Lambda-created readers are deleted, disable the scheduler
        - This prevents unnecessary Lambda executions and reduces costs
        - Only considers Lambda-created readers with proper tags
        - Enhanced error handling and comprehensive logging
    
    Logic:
        1. Count remaining Lambda readers (excluding those being deleted)
        2. Verify remaining readers have required tags
        3. If tagged Lambda readers exist, keep scheduler enabled
        4. If no tagged Lambda readers remain, disable the scheduler
        5. Send notification when scheduler is disabled
    """
    logger.info("=== EventBridge Scheduler Management ===")
    logger.info("Checking if any tagged 'lambda' reader instances remain...")
    
    try:
        # Filter for Lambda instances that are not being deleted
        lambda_instances = [
            inst for inst in instances 
            if inst['DBInstanceIdentifier'].startswith('lambda-aurora-reader') 
            and inst['DBInstanceStatus'] != 'deleting'
        ]
        
        if not lambda_instances:
            logger.info("No lambda instances found (excluding those being deleted)")
        else:
            logger.info(f"Found {len(lambda_instances)} lambda instance(s) to evaluate: "
                       f"{[inst['DBInstanceIdentifier'] for inst in lambda_instances]}")
        
        # Check which lambda instances have the required tags
        tagged_lambda_instances = []
        for inst in lambda_instances:
            instance_id = inst['DBInstanceIdentifier']
            if is_lambda_managed_instance(instance_id):
                tagged_lambda_instances.append(inst)
                logger.info(f"Instance {instance_id} has required tags - keeping scheduler enabled")
            else:
                logger.info(f"Instance {instance_id} lacks required tags - not considered for scheduler management")
        
        # If tagged Lambda instances still exist, keep scheduler running
        if tagged_lambda_instances:
            logger.info(f"Found {len(tagged_lambda_instances)} properly tagged lambda instance(s). "
                       f"EventBridge schedule will remain enabled.")
            return

        # No tagged Lambda instances remain - disable the scheduler
        schedule_name = EVENTBRIDGE_SCHEDULE_NAME
        logger.info(f"No properly tagged lambda instances remain. Attempting to disable EventBridge schedule: {schedule_name}")

        try:
            # Get current schedule configuration
            schedule = scheduler.get_schedule(Name=schedule_name, GroupName="default")
            current_state = schedule.get('State', 'UNKNOWN')
            
            logger.info(f"Current schedule state: {current_state}")
            
            if current_state == 'DISABLED':
                logger.info("Schedule is already disabled. No action needed.")
                return

            # Update schedule to disabled state while preserving configuration
            scheduler.update_schedule(
                Name=schedule_name,
                GroupName="default",
                ScheduleExpression=schedule['ScheduleExpression'],
                FlexibleTimeWindow=schedule['FlexibleTimeWindow'],
                Target=schedule['Target'],
                State="DISABLED"
            )

            # Send notification about scheduler being disabled
            msg = (f"EventBridge schedule '{schedule_name}' was disabled because no properly tagged "
                  f"lambda Aurora instances remain. Required tags: {REQUIRED_TAGS_FOR_DELETION}")
            logger.info(msg)
            notify("Aurora Auto-Scaler: Schedule Disabled", msg)
            
        except scheduler.exceptions.ResourceNotFoundException:
            logger.warning(f"EventBridge schedule '{schedule_name}' not found. It may have been deleted manually.")
        except Exception as schedule_error:
            logger.error(f"Failed to disable EventBridge schedule '{schedule_name}': {str(schedule_error)}")
            notify("Aurora Auto-Scaler: Schedule Management Error", 
                  f"Failed to disable schedule {schedule_name}: {str(schedule_error)}")

    except Exception as e:
        # Log warning but don't fail the function - scheduler management is not critical
        logger.warning(f"Error in EventBridge scheduler management: {str(e)}")
        logger.debug("Scheduler management error details:", exc_info=True)
