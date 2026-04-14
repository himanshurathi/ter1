# ============================================================
# Cloud-Based SAM Training: Cloudaware CMDB Demo
# Terraform Script - AWS Resource Provisioning
# Purpose: Provisions low-cost AWS resources tracked via Cloudaware
# Author: SAM Training Lab
# ============================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ----- VARIABLES -----
variable "aws_region" {
  description = "AWS Region to deploy resources"
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for tagging and naming"
  default     = "sam-training-lab"
}

variable "environment" {
  description = "Environment label for SAM classification"
  default     = "training"
}

variable "owner" {
  description = "Owner tag for SAM license tracking"
  default     = "sam-instructor"
}

variable "cost_center" {
  description = "Cost center for FinOps visibility in Cloudaware"
  default     = "IT-Training-001"
}

variable "application" {
  description = "Application name for CMDB classification"
  default     = "CloudSAM-Demo"
}

# ----- PROVIDER -----
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      Owner       = var.owner
      CostCenter  = var.cost_center
      Application = var.application
      ManagedBy   = "Terraform"
      SAMTracked  = "true"
      CreatedDate = "2026-04-14"
    }
  }
}

# ----- DATA SOURCES -----
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ============================================================
# NETWORKING LAYER
# Cloudaware tracks: VPCs, Subnets, Internet Gateways, Route Tables
# SAM Value: Asset classification, network topology in CMDB
# ============================================================

resource "aws_vpc" "sam_lab_vpc" {
  cidr_block           = "10.10.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.project_name}-vpc"
    AssetType   = "Network-Infrastructure"
    SAMCategory = "Core-Network"
  }
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.sam_lab_vpc.id
  cidr_block              = "10.10.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.project_name}-public-subnet"
    Tier        = "public"
    SAMCategory = "Network-Subnet"
  }
}

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.sam_lab_vpc.id
  cidr_block        = "10.10.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name        = "${var.project_name}-private-subnet"
    Tier        = "private"
    SAMCategory = "Network-Subnet"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.sam_lab_vpc.id

  tags = {
    Name        = "${var.project_name}-igw"
    SAMCategory = "Network-Gateway"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.sam_lab_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name        = "${var.project_name}-public-rt"
    SAMCategory = "Network-RouteTable"
  }
}

resource "aws_route_table_association" "public_rt_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# ============================================================
# SECURITY LAYER
# Cloudaware tracks: Security Groups, IAM Roles, Policies
# SAM Value: Compliance posture, access governance
# ============================================================

resource "aws_security_group" "web_sg" {
  name        = "${var.project_name}-web-sg"
  description = "Security group for SAM training web server"
  vpc_id      = aws_vpc.sam_lab_vpc.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-web-sg"
    SAMCategory = "Security-Group"
    Compliance  = "PCI-Reviewed"
  }
}

# IAM Role for EC2 (SSM access - no SSH keys needed)
resource "aws_iam_role" "ec2_ssm_role" {
  name = "${var.project_name}-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = {
    Name        = "${var.project_name}-ec2-role"
    SAMCategory = "IAM-Role"
    LicenseType = "AWS-Managed"
  }
}

resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_policy" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2_ssm_role.name
}

# ============================================================
# COMPUTE LAYER - EC2 Instances
# Cloudaware tracks: Instance type, state, AMI, region, tags
# SAM Value: Software inventory on compute assets, license per instance
# Cost: t2.micro/t3.micro = ~$8-10/month (or free tier eligible)
# ============================================================

resource "aws_instance" "web_server" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t2.micro"  # Free tier eligible
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y httpd
    systemctl start httpd
    systemctl enable httpd
    echo "<h1>SAM Training Lab - Web Server</h1><p>Instance: $(hostname)</p><p>Tracked by Cloudaware CMDB</p>" > /var/www/html/index.html
  EOF
  )

  tags = {
    Name           = "${var.project_name}-web-server"
    AssetType      = "Compute-EC2"
    SAMCategory    = "Licensed-Software-Host"
    SoftwareStack  = "Apache-HTTPD-AmazonLinux2023"
    LicenseModel   = "BYOL-OpenSource"
    ComplianceZone = "PCI-Scope"
    BusinessUnit   = "Training"
    Backup         = "false"
    Monitoring     = "true"
  }
}

resource "aws_instance" "app_server" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t2.micro"  # Free tier eligible
  subnet_id              = aws_subnet.private_subnet.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y java-17-amazon-corretto
    echo "App Server ready for SAM tracking" > /tmp/status.txt
  EOF
  )

  tags = {
    Name           = "${var.project_name}-app-server"
    AssetType      = "Compute-EC2"
    SAMCategory    = "Licensed-Software-Host"
    SoftwareStack  = "Java17-AmazonCorretto"
    LicenseModel   = "OpenSource-OpenJDK"
    ComplianceZone = "Internal"
    BusinessUnit   = "Training"
    Backup         = "false"
    Monitoring     = "true"
  }
}

# ============================================================
# STORAGE LAYER - S3 Buckets
# Cloudaware tracks: Bucket name, region, encryption, public access
# SAM Value: Data asset classification, compliance posture
# Cost: S3 storage = $0.023/GB/month (near $0 for demo)
# ============================================================

resource "aws_s3_bucket" "software_assets" {
  bucket = "${var.project_name}-software-assets-${random_id.suffix.hex}"

  tags = {
    Name        = "${var.project_name}-software-assets"
    AssetType   = "Storage-S3"
    SAMCategory = "Software-Repository"
    DataClass   = "Internal"
    Compliance  = "Encrypted"
  }
}

resource "aws_s3_bucket" "audit_logs" {
  bucket = "${var.project_name}-audit-logs-${random_id.suffix.hex}"

  tags = {
    Name        = "${var.project_name}-audit-logs"
    AssetType   = "Storage-S3"
    SAMCategory = "Compliance-Audit"
    DataClass   = "Restricted"
    Retention   = "90-days"
  }
}

resource "aws_s3_bucket_versioning" "software_versioning" {
  bucket = aws_s3_bucket.software_assets.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "software_encryption" {
  bucket = aws_s3_bucket.software_assets.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "software_block_public" {
  bucket                  = aws_s3_bucket.software_assets.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "audit_block_public" {
  bucket                  = aws_s3_bucket.audit_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ============================================================
# DATABASE LAYER - RDS (Optional - higher cost)
# Cloudaware tracks: DB engine, version, multi-AZ, tags
# SAM Value: Database license compliance (Oracle/SQL Server critical)
# Cost: db.t3.micro MySQL = ~$15/month
# NOTE: Commented out to keep lab costs minimal.
#       Uncomment to demonstrate DB license tracking.
# ============================================================

# resource "aws_db_subnet_group" "rds_subnet_group" {
#   name       = "${var.project_name}-rds-subnet"
#   subnet_ids = [aws_subnet.public_subnet.id, aws_subnet.private_subnet.id]
#   tags = {
#     Name        = "${var.project_name}-rds-subnet-group"
#     SAMCategory = "Database-SubnetGroup"
#   }
# }
#
# resource "aws_db_instance" "demo_db" {
#   identifier             = "${var.project_name}-mysql"
#   engine                 = "mysql"
#   engine_version         = "8.0"
#   instance_class         = "db.t3.micro"
#   allocated_storage      = 20
#   db_name                = "samtraining"
#   username               = "admin"
#   password               = "TrainingLab123!"  # Change in production!
#   db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
#   vpc_security_group_ids = [aws_security_group.web_sg.id]
#   skip_final_snapshot    = true
#   publicly_accessible    = false
#   tags = {
#     Name        = "${var.project_name}-mysql-db"
#     AssetType   = "Database-RDS"
#     SAMCategory = "Licensed-Database"
#     LicenseType = "MySQL-Community-GPL"
#     Compliance  = "Encrypted"
#   }
# }

# ============================================================
# MONITORING LAYER - CloudWatch
# Cloudaware integrates with CloudWatch for utilization signals
# SAM Value: Usage metering for license optimization
# Cost: Basic metrics FREE; custom metrics $0.30/metric/month
# ============================================================

resource "aws_cloudwatch_log_group" "app_logs" {
  name              = "/sam-training/${var.project_name}/application"
  retention_in_days = 7  # Minimize cost

  tags = {
    Name        = "${var.project_name}-app-logs"
    AssetType   = "Monitoring-LogGroup"
    SAMCategory = "Audit-Trail"
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.project_name}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "SAM Lab: CPU usage exceeds 80% - potential license metric signal"

  dimensions = {
    InstanceId = aws_instance.web_server.id
  }

  tags = {
    Name        = "${var.project_name}-cpu-alarm"
    SAMCategory = "Usage-Metering-Signal"
  }
}

# ============================================================
# PARAMETER STORE - License Metadata Storage
# SAM Value: Centralized license key/metadata tracking
# Cost: Standard parameters FREE
# ============================================================

resource "aws_ssm_parameter" "license_metadata" {
  name  = "/${var.project_name}/licensing/metadata"
  type  = "String"
  value = jsonencode({
    project      = var.project_name
    environment  = var.environment
    license_model = "Mixed-OpenSource-BYOL"
    sam_tool     = "Cloudaware-CMDB"
    audit_date   = "2026-04-14"
    software_inventory = [
      { name = "Apache HTTPD", version = "2.4.x", type = "OpenSource", license = "Apache-2.0" },
      { name = "Amazon Linux 2023", version = "2023", type = "OS", license = "GPL-Various" },
      { name = "Amazon Corretto 17", version = "17.x", type = "JDK", license = "GPL-2.0-CE" }
    ]
  })

  tags = {
    Name        = "license-metadata"
    SAMCategory = "License-Registry"
    AssetType   = "Config-SSMParameter"
  }
}

# ============================================================
# LAMBDA FUNCTION - Serverless Asset
# Cloudaware tracks: Function name, runtime, memory, tags
# SAM Value: Serverless license model (consumption-based)
# Cost: 1M requests/month FREE
# ============================================================

resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = {
    SAMCategory = "IAM-Role-Lambda"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "sam_report_generator" {
  function_name = "${var.project_name}-sam-reporter"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  timeout       = 30

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      PROJECT_NAME = var.project_name
      ENVIRONMENT  = var.environment
      SAM_TOOL     = "Cloudaware"
    }
  }

  tags = {
    Name           = "${var.project_name}-sam-reporter"
    AssetType      = "Compute-Lambda"
    SAMCategory    = "Serverless-Function"
    LicenseModel   = "Consumption-Based"
    SoftwareStack  = "NodeJS-20-Runtime"
  }
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "/tmp/lambda_function.zip"

  source {
    content  = <<-EOF
      exports.handler = async (event) => {
        const report = {
          timestamp: new Date().toISOString(),
          project: process.env.PROJECT_NAME,
          environment: process.env.ENVIRONMENT,
          sam_tool: process.env.SAM_TOOL,
          message: "SAM License Report Generated",
          assets_tracked: ["EC2-WebServer", "EC2-AppServer", "S3-Buckets", "Lambda-Functions"]
        };
        console.log("SAM Report:", JSON.stringify(report, null, 2));
        return { statusCode: 200, body: JSON.stringify(report) };
      };
    EOF
    filename = "index.js"
  }
}

# ============================================================
# RANDOM SUFFIX for unique bucket names
# ============================================================
resource "random_id" "suffix" {
  byte_length = 4
}

# ============================================================
# OUTPUTS - Used in Cloudaware verification steps
# ============================================================

output "vpc_id" {
  description = "VPC ID - search this in Cloudaware CMDB Navigator"
  value       = aws_vpc.sam_lab_vpc.id
}

output "web_server_instance_id" {
  description = "Web Server EC2 Instance ID - track in Cloudaware"
  value       = aws_instance.web_server.id
}

output "app_server_instance_id" {
  description = "App Server EC2 Instance ID - track in Cloudaware"
  value       = aws_instance.app_server.id
}

output "web_server_public_ip" {
  description = "Public IP of web server"
  value       = aws_instance.web_server.public_ip
}

output "s3_software_bucket" {
  description = "S3 bucket for software assets - searchable in Cloudaware"
  value       = aws_s3_bucket.software_assets.bucket
}

output "s3_audit_bucket" {
  description = "S3 audit log bucket"
  value       = aws_s3_bucket.audit_logs.bucket
}

output "lambda_function_name" {
  description = "Lambda function name - appears in Cloudaware serverless inventory"
  value       = aws_lambda_function.sam_report_generator.function_name
}

output "ssm_parameter_path" {
  description = "SSM Parameter path for license metadata"
  value       = aws_ssm_parameter.license_metadata.name
}

output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown"
  value = {
    ec2_t2_micro_x2     = "~$16-18 (or $0 if free tier)"
    s3_storage          = "~$0.01 (demo data only)"
    cloudwatch_logs     = "~$0.50"
    lambda              = "$0 (within free tier)"
    ssm_parameters      = "$0 (standard tier)"
    total_estimate      = "~$17-19/month (or near $0 with free tier)"
  }
}
