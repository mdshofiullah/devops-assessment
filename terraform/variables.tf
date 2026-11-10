
variable "aws_region" {
  description = "AWS region for infrastructure."
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Project name used for AWS resources."
  type        = string
  default     = "devops-assessment"
}

variable "environment" {
  description = "Deployment environment."
  type        = string

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "Environment must be staging or production."
  }
}

variable "vpc_id" {
  description = "Existing AWS VPC ID."
  type        = string

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "A valid VPC ID is required."
  }
}

variable "subnet_id" {
  description = "Existing public subnet ID."
  type        = string

  validation {
    condition     = can(regex("^subnet-[0-9a-f]+$", var.subnet_id))
    error_message = "A valid subnet ID is required."
  }
}

variable "ami_id" {
  description = "Amazon Linux 2023 AMI ID."
  type        = string

  validation {
    condition     = can(regex("^ami-[0-9a-f]+$", var.ami_id))
    error_message = "A valid AMI ID is required."
  }
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.micro"
}

variable "app_port" {
  description = "Application listening port."
  type        = number
  default     = 8080
}

variable "app_ingress_cidr_blocks" {
  description = "CIDR ranges allowed to access the application."
  type        = list(string)

  validation {
    condition = length(var.app_ingress_cidr_blocks) > 0 && alltrue([
      for cidr in var.app_ingress_cidr_blocks : can(cidrhost(cidr, 0))
    ])
    error_message = "Provide at least one valid CIDR block."
  }
}

variable "enable_ec2_instance" {
  description = "Enable EC2 only after the application image exists in ECR."
  type        = bool
  default     = false
}

variable "ecr_repository_name" {
  description = "ECR repository name."
  type        = string
  default     = "devops-assessment"
}

variable "image_tag" {
  description = "Application image tag."
  type        = string
  default     = "latest"
}

variable "app_version" {
  description = "Application version."
  type        = string
  default     = "1.0.0"
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days."
  type        = number
  default     = 14

  validation {
    condition = contains(
      [1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365],
      var.log_retention_days
    )
    error_message = "Choose a supported CloudWatch retention period."
  }
}

variable "root_volume_size_gb" {
  description = "EC2 root volume size."
  type        = number
  default     = 16

  validation {
    condition     = var.root_volume_size_gb >= 8 && var.root_volume_size_gb <= 100
    error_message = "Root volume must be between 8 and 100 GB."
  }
}
