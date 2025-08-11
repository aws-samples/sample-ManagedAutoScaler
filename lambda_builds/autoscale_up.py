# -------------------------------------------------------------------
# Aurora PostgreSQL Auto-Scaling Lambda Function - Scale Up Handler (MINIMAL FIX)
# -------------------------------------------------------------------
# This Lambda function is triggered by EventBridge when RDS insufficient 
# capacity events (RDS-EVENT-0031) occur. It automatically creates new 
# Aurora reader instances to handle increased load.
#
# CHANGES IN THIS VERSION:
# 1. Added secure tagging for lambda-managed instances
# 2. Enhanced error handling and logging
# 3. Preserved ALL original logic and configuration
#
# Trigger: EventBridge rule matching RDS insufficient capacity events
# Purpose: Create new Aurora reader instances when capacity is insufficient
# Strategy: Try preferred instance types first, then fallback options
# -------------------------------------------------------------------

# ========================
# 📦 IMPORTS AND LOGGING SETUP
# ========================
import boto3          # AWS SDK for Python - interact with AWS services
import os             # Operating system interface - access environment variables
import time           # Time-related functions - generate timestamps
import uuid           # Generate unique identifiers for DB instances
import logging        # Python logging framework for CloudWatch logs
import botocore.exceptions  # Handle AWS API exceptions gracefully

# Configure logging for CloudWatch - all log messages will appear in 
# /aws/lambda/aurora-autoscale-up log group
logger = logging.getLogger()
logger.setLevel(logging.INFO)  # Log INFO level and above (INFO, WARNING, ERROR)

# ========================
# 🔧 AWS CLIENT SETUP
# ========================
# Initialize AWS service clients for different services
# These clients will be reused throughout the function execution

# Get AWS region from environment variable, default to eu-central-1
region = os.getenv('REGION', 'eu-central-1')

# EC2 client - used for capacity checking via On-Demand Capacity Reservations (ODCR)
ec2_client = boto3.client("ec2", region_name=region)

# RDS client - used for Aurora cluster and instance operations
rds_client = boto3.client("rds", region_name=region)

# SNS client - used for sending notifications (optional)
sns = boto3.client("sns")

# EventBridge Scheduler client - used to enable/disable the downscale schedule
scheduler_client = boto3.client("scheduler", region_name=region)

# ========================
# ⚙️ ENVIRONMENT VARIABLES CONFIGURATION (ORIGINAL - UNCHANGED)
# ========================
# These variables are set by Terraform and control the function behavior

# REQUIRED: Aurora cluster identifier that this function will scale
DB_CLUSTER_ID = os.getenv('DB_CLUSTER_ID')

# OPTIONAL: SNS topic ARN for notifications (can be empty to disable notifications)
SNS_TOPIC_ARN = os.getenv('SNS_TOPIC_ARN')  # Optional: remove if not using SNS

# EventBridge Scheduler name for the downscale function
# This schedule monitors CPU and removes readers when utilization is low
EVENTBRIDGE_SCHEDULE_NAME = 'aurora-cpu-monitor-every-minute'

# Instance type preferences and fallback options (ORIGINAL - UNCHANGED)
# Note: These are EC2 instance types WITHOUT the "db." prefix
# The "db." prefix will be added when creating RDS instances
PREFERRED_INSTANCE_TYPE = os.getenv('PREFERRED_INSTANCE_TYPE', 'r6i.32xlarge')

# Comma-separated list of fallback instance types in priority order (ORIGINAL - UNCHANGED)
# If preferred type has no capacity, try these in order
INSTANCE_TYPES_PRIORITY = os.getenv('INSTANCE_TYPES_PRIORITY', 'r7i.48xlarge,r6id.32xlarge').split(',')

# Comma-separated list of availability zones to try (ORIGINAL - UNCHANGED)
# Function will prefer AZs with fewer existing readers for better distribution
AVAILABILITY_ZONES = os.getenv('AVAILABILITY_ZONES', 'eu-central-1a,eu-central-1b,eu-central-1c').split(',')

# Database engine type - should always be aurora-postgresql for this use case
DB_ENGINE = os.getenv('DB_ENGINE', 'aurora-postgresql')

# Aurora reader tier for failover priority (0-15, higher = lower priority)
AURORA_READER_TIER = int(os.getenv('AURORA_READER_TIER', '15'))

# Fallback strategy determines how to handle capacity shortages (ORIGINAL - UNCHANGED):
# - "instance-priority": Try all AZs for each instance type before moving to next type
# - "az-priority": Try all instance types in each AZ before moving to next AZ
FALLBACK_STRATEGY = os.getenv('FALLBACK_STRATEGY', 'instance-priority')

# Boolean flag to enable/disable SNS notifications (ORIGINAL - UNCHANGED)
# Converts string environment variable to boolean
ENABLE_SNS = os.getenv('ENABLE_SNS', 'false').lower() == 'true'

# ========================
# 🏷️ SECURE TAGGING CONFIGURATION (NEW ADDITION)
# ========================
# These tags identify instances created by the Lambda function
# Only instances with these tags can be deleted by the downscale function
# This protects manually created instances from accidental deletion
LAMBDA_MANAGED_TAGS = [
    {'Key': 'ManagedBy', 'Value': 'aurora-autoscaler'},
    {'Key': 'AutoScaler', 'Value': 'lambda-managed'},
    {'Key': 'CreatedBy', 'Value': 'aurora-autoscale-up-lambda'},
    {'Key': 'Purpose', 'Value': 'auto-scaling-reader'}
]

# ========================
# 📧 SNS NOTIFICATION HELPER FUNCTION (ORIGINAL - UNCHANGED)
# ========================
def notify(subject, message):
    """
    Send SNS notification if enabled and configured.
    
    Args:
        subject (str): Email subject line
        message (str): Email message body
    
    Returns:
        None
    
    Note:
        - Only sends if ENABLE_SNS is True and SNS_TOPIC_ARN is configured
        - Failures are logged but don't crash the function
    """
    # Skip notification if SNS is disabled or topic ARN is not configured
    if not ENABLE_SNS or not SNS_TOPIC_ARN:
        return
    
    try:
        # Publish message to SNS topic
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=subject,
            Message=message
        )
        logger.info("SNS notification sent successfully")
    except Exception as e:
        # Log failure but don't crash the Lambda - notifications are not critical
        logger.error(f"Failed to send SNS notification: {e}")

# ========================
# 🆔 UNIQUE DB IDENTIFIER GENERATOR (ORIGINAL - UNCHANGED)
# ========================
def generate_unique_db_identifier():
    """
    Generate a unique identifier for new Aurora reader instances.
    
    Returns:
        str: Unique DB instance identifier in format:
             lambda-aurora-reader-YYYYMMDD-HHMMSS-XXXXXX
             
    Example:
        lambda-aurora-reader-20250728-143022-a1b2c3
        
    Note:
        - Timestamp ensures chronological ordering
        - UUID suffix prevents collisions if multiple instances created simultaneously
        - "lambda-" prefix identifies instances created by this function
    """
    # Generate timestamp in YYYYMMDD-HHMMSS format
    timestamp = time.strftime("%Y%m%d-%H%M%S")
    
    # Generate 6-character random suffix from UUID
    unique_id = uuid.uuid4().hex[:6]
    
    # Combine into unique identifier
    return f"lambda-aurora-reader-{timestamp}-{unique_id}"

# ========================
# 📊 AURORA READER DISTRIBUTION ANALYZER (ENHANCED LOGGING)
# ========================
def get_aurora_readers_per_az():
    """
    Analyze current Aurora reader distribution across availability zones.
    
    Returns:
        dict: Mapping of AZ to reader count
              Example: {'eu-central-1a': 2, 'eu-central-1b': 1, 'eu-central-1c': 0}
    
    Logic:
        1. Query all RDS instances in the region
        2. Filter for instances belonging to our Aurora cluster
        3. Count healthy readers per availability zone
        4. Exclude instances that are being deleted or in insufficient capacity state
    """
    try:
        logger.info(f"Fetching Aurora readers for cluster: {DB_CLUSTER_ID}")
        
        # Get all RDS instances in the region
        response = rds_client.describe_db_instances()
        
        # Initialize counter for each configured availability zone
        readers_per_az = {az: 0 for az in AVAILABILITY_ZONES}
        
        # Iterate through all DB instances
        for db in response["DBInstances"]:
            # Only consider instances that belong to our Aurora cluster
            if db.get("DBClusterIdentifier") == DB_CLUSTER_ID:
                az = db.get("AvailabilityZone")
                status = db.get("DBInstanceStatus")
                is_writer = db.get("IsClusterWriter", False)
                
                # Count healthy reader instances (exclude writers and unhealthy states)
                if (not is_writer and 
                    status not in ["deleting", "insufficient activity"] and 
                    az in readers_per_az):
                    readers_per_az[az] += 1
                    logger.info(f"Found reader {db['DBInstanceIdentifier']} in {az} (status: {status})")
        
        logger.info(f"Current reader distribution: {readers_per_az}")
        return readers_per_az
        
    except Exception as e:
        logger.error(f"Error getting Aurora readers: {str(e)}")
        raise

# ========================
# ⏰ EVENTBRIDGE SCHEDULER MANAGEMENT (ENHANCED ERROR HANDLING)
# ========================
def enable_eventbridge_rule():
    """
    Enable the EventBridge Scheduler that monitors CPU and scales down readers.
    
    Purpose:
        - When we create new readers, we need to ensure the downscale function is active
        - The downscale function monitors CPU utilization and removes readers when not needed
        - This prevents cost accumulation from unused reader instances
    
    Logic:
        1. Check current state of the downscale scheduler
        2. If disabled, enable it with existing configuration
        3. Send notification when scheduler is enabled
    """
    try:
        logger.info(f"Checking EventBridge Scheduler: {EVENTBRIDGE_SCHEDULE_NAME}")
        
        # Get current scheduler configuration
        schedule = scheduler_client.get_schedule(Name=EVENTBRIDGE_SCHEDULE_NAME, GroupName="default")
        
        # Check if scheduler is currently disabled
        if schedule['State'] != 'ENABLED':
            logger.info("Enabling downscale scheduler")
            
            # Enable the scheduler while preserving existing configuration
            scheduler_client.update_schedule(
                Name=EVENTBRIDGE_SCHEDULE_NAME,
                GroupName="default",
                ScheduleExpression=schedule['ScheduleExpression'],  # Keep existing schedule (every minute)
                FlexibleTimeWindow=schedule['FlexibleTimeWindow'], # Keep existing time window
                Target=schedule['Target'],                         # Keep existing target (downscale Lambda)
                State="ENABLED"                                    # Change state to enabled
            )
            
            # Notify that scheduler has been enabled
            notify("EventBridge Scheduler Enabled", 
                   f"The EventBridge Scheduler '{EVENTBRIDGE_SCHEDULE_NAME}' has been enabled.")
            logger.info("EventBridge Scheduler enabled successfully")
        else:
            logger.info("EventBridge Scheduler is already enabled")
            
    except Exception as e:
        # Log error but don't fail the function - reader creation is more important
        logger.error(f"Failed to enable EventBridge Scheduler: {e}")

# ========================
# 🧪 CAPACITY AVAILABILITY CHECKER (ORIGINAL LOGIC - UNCHANGED)
# ========================
def check_capacity(instance_type, availability_zone):
    """
    Check if EC2 capacity is available for a specific instance type in an AZ.
    
    Args:
        instance_type (str): EC2 instance type (without "db." prefix)
        availability_zone (str): Target availability zone
    
    Returns:
        bool: True if capacity is available, False otherwise
    
    Method:
        Uses On-Demand Capacity Reservations (ODCR) as a capacity probe:
        1. Create a temporary capacity reservation
        2. If successful, capacity is available - immediately cancel reservation
        3. If fails with InsufficientInstanceCapacity, no capacity available
        4. Other errors are logged and treated as no capacity
    
    Note:
        - This is a "dry run" approach that doesn't actually consume capacity
        - ODCR creation/cancellation is fast and doesn't incur charges
        - More reliable than trying to create instances and handling failures
    """
    start_time = time.time()
    
    try:
        logger.info(f"Checking capacity for {instance_type} in {availability_zone}")
        
        # Attempt to create a temporary On-Demand Capacity Reservation
        response = ec2_client.create_capacity_reservation(
            InstanceType=instance_type,           # EC2 instance type (e.g., "r6i.32xlarge")
            InstancePlatform="Linux/UNIX",        # Platform for Aurora instances
            AvailabilityZone=availability_zone,   # Target AZ
            Tenancy="default",                    # Default tenancy (not dedicated)
            InstanceCount=1,                      # Only need to check for 1 instance
            EbsOptimized=True,                    # Aurora instances are EBS optimized
            EphemeralStorage=False,               # Aurora doesn't use ephemeral storage
            EndDateType="unlimited",              # Unlimited duration (will cancel immediately)
            InstanceMatchCriteria="targeted",     # Must match exact instance type
            TagSpecifications=[{                  # Tag for identification
                "ResourceType": "capacity-reservation", 
                "Tags": [{"Key": "Name", "Value": "temp-capacity-check"}]
            }],
        )
        
        # If we reach here, capacity is available
        # Get the reservation ID and immediately cancel it
        reservation_id = response["CapacityReservation"]["CapacityReservationId"]
        ec2_client.cancel_capacity_reservation(CapacityReservationId=reservation_id)
        
        duration = (time.time() - start_time) * 1000
        logger.info(f"Capacity check successful for {instance_type} in {availability_zone}: AVAILABLE (took {duration:.2f}ms)")
        return True  # Capacity is available
        
    except botocore.exceptions.ClientError as e:
        duration = (time.time() - start_time) * 1000
        
        # Check if the error is specifically about insufficient capacity
        if "InsufficientInstanceCapacity" in str(e):
            logger.info(f"Capacity check failed for {instance_type} in {availability_zone}: NO CAPACITY (took {duration:.2f}ms)")
            return False  # No capacity available
        
        # Other errors (permissions, API limits, etc.) - log and treat as no capacity
        logger.error(f"ODCR error for {instance_type} in {availability_zone}: {e}")
        logger.info(f"Capacity check failed for {instance_type} in {availability_zone}: ERROR (took {duration:.2f}ms)")
        return False

# ========================
# ✨ AURORA READER INSTANCE CREATOR (ENHANCED WITH SECURE TAGGING)
# ========================
def create_reader_instance(instance_type, availability_zone):
    """
    Create a new Aurora reader instance in the specified AZ with secure tagging.
    
    Args:
        instance_type (str): EC2 instance type (without "db." prefix)
        availability_zone (str): Target availability zone
    
    Returns:
        dict: RDS API response if successful, None if failed
    
    Process:
        1. Generate unique DB instance identifier
        2. Create RDS instance with Aurora cluster configuration and secure tags
        3. Send success/failure notifications
        4. Enable downscale scheduler for cost management
    
    SECURE TAGGING ENHANCEMENT:
        - Adds lambda-managed tags to identify instances created by autoscaler
        - Only instances with these tags can be deleted by the downscale function
        - Protects manually created instances from accidental deletion
    """
    # Generate unique identifier for the new reader instance
    db_identifier = generate_unique_db_identifier()
    
    try:
        logger.info(f"Creating reader instance {db_identifier} ({instance_type}) in {availability_zone}")
        logger.info(f"Setting Aurora reader tier: {AURORA_READER_TIER} (lower = higher failover priority)")
        
        # Prepare secure tags with additional metadata
        tags = LAMBDA_MANAGED_TAGS.copy()
        tags.extend([
            {'Key': 'CreatedAt', 'Value': time.strftime("%Y-%m-%d %H:%M:%S UTC")},
            {'Key': 'InstanceType', 'Value': instance_type},
            {'Key': 'AvailabilityZone', 'Value': availability_zone},
            {'Key': 'ClusterIdentifier', 'Value': DB_CLUSTER_ID}
        ])
        
        logger.info(f"Applying secure tags: ManagedBy=aurora-autoscaler, AutoScaler=lambda-managed")
        
        # Create the Aurora reader instance with secure tagging
        response = rds_client.create_db_instance(
            DBInstanceIdentifier=db_identifier,        # Unique instance name
            DBInstanceClass=f"db.{instance_type}",     # Add "db." prefix for RDS (ORIGINAL LOGIC)
            Engine=DB_ENGINE,                          # aurora-postgresql
            DBClusterIdentifier=DB_CLUSTER_ID,         # Join this Aurora cluster
            AvailabilityZone=availability_zone,        # Place in specific AZ
            PromotionTier=AURORA_READER_TIER,          # Set failover priority tier
            Tags=tags,                                 # SECURE TAGGING: Apply lambda-managed tags
            PubliclyAccessible=False,                  # Security: Never make readers public
            CopyTagsToSnapshot=True                    # Propagate tags to snapshots
            # Note: DeletionProtection removed - Aurora only supports this at cluster level
        )
        
        # Send success notification
        notify("Aurora Reader Created with Secure Tagging", 
               f"Created Aurora reader {db_identifier} in {availability_zone} with {instance_type}.\n"
               f"Instance tagged as lambda-managed for secure deletion control.")
        
        # Enable the downscale scheduler to manage costs
        enable_eventbridge_rule()
        
        logger.info(f"Successfully initiated creation of reader instance: {db_identifier}")
        logger.info(f"SECURITY: Instance tagged as lambda-managed and will be available in 3-8 minutes")
        
        return response
        
    except Exception as e:
        logger.error(f"Failed to create reader instance {db_identifier}: {str(e)}")
        
        # Send failure notification
        notify("Aurora Reader Creation Failed", 
               f"Failed to create Aurora reader {db_identifier} in {availability_zone}: {e}")
        return None

# ========================
# 🧠 MAIN LAMBDA HANDLER FUNCTION (ENHANCED LOGGING)
# ========================
def lambda_handler(event, context):
    """
    Main Lambda function handler - orchestrates the auto-scaling logic.
    
    Args:
        event (dict): EventBridge event containing RDS insufficient capacity details
        context (object): Lambda runtime context (timeout, memory, etc.)
    
    Returns:
        dict: Success response with instance details, or failure message
    
    Auto-Scaling Strategy (ORIGINAL LOGIC - UNCHANGED):
        1. Analyze current reader distribution across AZs
        2. Sort AZs by reader count (prefer AZs with fewer readers)
        3. Try preferred instance type in each AZ
        4. If no capacity, use fallback strategy:
           - instance-priority: Try all AZs for each instance type
           - az-priority: Try all instance types in each AZ
        5. Create reader in first available capacity location
        6. If no capacity anywhere, send failure notification
    """
    
    logger.info("=== Aurora AutoScaler Scale-Up Started (Minimal Fix Version) ===")
    logger.info(f"Event: {event}")
    logger.info(f"Cluster: {DB_CLUSTER_ID}, Strategy: {FALLBACK_STRATEGY}")
    
    start_time = time.time()
    
    try:
        # Step 1: Analyze current Aurora reader distribution
        # This helps us place new readers for optimal load distribution
        logger.info("Step 1: Analyzing current reader distribution")
        readers_per_az = get_aurora_readers_per_az()
        
        # Step 2: Sort AZs by current reader count (ascending)
        # This ensures we prefer AZs with fewer readers for better distribution
        sorted_azs = sorted(readers_per_az, key=readers_per_az.get)
        logger.info(f"Step 2: AZ priority order: {sorted_azs}")

        # Step 3: Try preferred instance type first in all AZs
        # Start with AZs that have the fewest readers
        logger.info(f"Step 3: Trying preferred instance type: {PREFERRED_INSTANCE_TYPE}")
        for az in sorted_azs:
            if check_capacity(PREFERRED_INSTANCE_TYPE, az):
                result = create_reader_instance(PREFERRED_INSTANCE_TYPE, az)
                if result:
                    execution_time = (time.time() - start_time) * 1000
                    logger.info(f"=== Aurora AutoScaler Scale-Up Completed Successfully ===")
                    logger.info(f"Total execution time: {execution_time:.2f}ms")
                    return {
                        "statusCode": 200,
                        "body": {
                            "status": "success", 
                            "instance_type": PREFERRED_INSTANCE_TYPE,
                            "availability_zone": az,
                            "db_identifier": result.get('DBInstance', {}).get('DBInstanceIdentifier'),
                            "security": "lambda-managed-tags-applied",
                            "execution_time_ms": execution_time
                        }
                    }

        # Step 4: Preferred instance type has no capacity, use fallback strategy (ORIGINAL LOGIC)
        logger.info(f"Step 4: Using fallback strategy: {FALLBACK_STRATEGY}")
        
        if FALLBACK_STRATEGY == "instance-priority":
            # Instance-priority strategy: Try all AZs for each instance type
            # Good when specific instance types are critical for performance
            logger.info("Using instance-priority strategy")
            for instance_type in INSTANCE_TYPES_PRIORITY:
                logger.info(f"Trying fallback instance type: {instance_type}")
                for az in sorted_azs:
                    if check_capacity(instance_type, az):
                        result = create_reader_instance(instance_type, az)
                        if result:
                            execution_time = (time.time() - start_time) * 1000
                            logger.info(f"=== Aurora AutoScaler Scale-Up Completed Successfully ===")
                            logger.info(f"Total execution time: {execution_time:.2f}ms")
                            return {
                                "statusCode": 200,
                                "body": {
                                    "status": "success", 
                                    "instance_type": instance_type,
                                    "availability_zone": az,
                                    "db_identifier": result.get('DBInstance', {}).get('DBInstanceIdentifier'),
                                    "security": "lambda-managed-tags-applied",
                                    "execution_time_ms": execution_time
                                }
                            }
        else:
            # AZ-priority strategy: Try all instance types in each AZ
            # Good when geographic distribution is more important than instance type
            logger.info("Using az-priority strategy")
            for az in sorted_azs:
                logger.info(f"Trying all instance types in AZ: {az}")
                for instance_type in INSTANCE_TYPES_PRIORITY:
                    if check_capacity(instance_type, az):
                        result = create_reader_instance(instance_type, az)
                        if result:
                            execution_time = (time.time() - start_time) * 1000
                            logger.info(f"=== Aurora AutoScaler Scale-Up Completed Successfully ===")
                            logger.info(f"Total execution time: {execution_time:.2f}ms")
                            return {
                                "statusCode": 200,
                                "body": {
                                    "status": "success", 
                                    "instance_type": instance_type,
                                    "availability_zone": az,
                                    "db_identifier": result.get('DBInstance', {}).get('DBInstanceIdentifier'),
                                    "security": "lambda-managed-tags-applied",
                                    "execution_time_ms": execution_time
                                }
                            }

        # Step 5: No capacity found anywhere - send failure notification
        execution_time = (time.time() - start_time) * 1000
        error_msg = "No capacity found for any instance type in any AZ"
        logger.error(f"=== Aurora AutoScaler Scale-Up Failed ===")
        logger.error(f"Error: {error_msg}")
        logger.error(f"Execution time: {execution_time:.2f}ms")
        
        notify("Aurora Scaling Failed", 
               f"{error_msg}.\n"
               f"Cluster: {DB_CLUSTER_ID}\n"
               f"Attempted types: {[PREFERRED_INSTANCE_TYPE] + INSTANCE_TYPES_PRIORITY}\n"
               f"Attempted AZs: {AVAILABILITY_ZONES}")
        
        # Return failure response
        return {
            "statusCode": 503,
            "body": {
                "status": "failure", 
                "message": error_msg,
                "cluster": DB_CLUSTER_ID,
                "attempted_types": [PREFERRED_INSTANCE_TYPE] + INSTANCE_TYPES_PRIORITY,
                "attempted_azs": AVAILABILITY_ZONES,
                "execution_time_ms": execution_time
            }
        }
        
    except Exception as e:
        execution_time = (time.time() - start_time) * 1000
        error_msg = f"Unexpected error in Aurora AutoScaler: {str(e)}"
        logger.error(f"=== Aurora AutoScaler Scale-Up Error ===")
        logger.error(f"Error: {error_msg}")
        logger.error(f"Execution time before error: {execution_time:.2f}ms")
        
        notify("Aurora AutoScaler Critical Error", 
               f"{error_msg}\n"
               f"Cluster: {DB_CLUSTER_ID}\n"
               f"Execution Time: {execution_time:.2f}ms")
        
        return {
            "statusCode": 500,
            "body": {
                "error": error_msg,
                "cluster": DB_CLUSTER_ID,
                "execution_time_ms": execution_time
            }
        }
