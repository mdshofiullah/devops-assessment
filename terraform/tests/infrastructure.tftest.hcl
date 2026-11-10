
mock_provider "aws" {}

run "infrastructure_configuration" {
  command = plan

  variables {
    aws_region   = "ap-south-1"
    project_name = "devops-assessment"
    environment  = "staging"

    vpc_id    = "vpc-0123456789abcdef0"
    subnet_id = "subnet-0123456789abcdef0"
    ami_id    = "ami-0123456789abcdef0"

    instance_type = "t3.micro"

    app_ingress_cidr_blocks = [
      "203.0.113.10/32"
    ]

    enable_ec2_instance = true
    log_retention_days  = 14
    root_volume_size_gb = 16
  }

  # Check that only one application ingress rule exists.
  assert {
    condition = (
      length(aws_security_group.app.ingress) == 1 &&
      one(aws_security_group.app.ingress).from_port == 8080 &&
      one(aws_security_group.app.ingress).to_port == 8080 &&
      one(aws_security_group.app.ingress).protocol == "tcp"
    )

    error_message = "Security group should expose only application port 8080."
  }

  # Check that inbound access is restricted to the configured CIDR.
  assert {
    condition = (
      length(one(aws_security_group.app.ingress).cidr_blocks) == 1 &&
      contains(
        one(aws_security_group.app.ingress).cidr_blocks,
        "203.0.113.10/32"
      )
    )

    error_message = "Application ingress CIDR is not correctly configured."
  }

  # Check that EC2 uses the application IAM instance profile.
  assert {
    condition = (
      aws_instance.app[0].iam_instance_profile ==
      aws_iam_instance_profile.app.name
    )

    error_message = "EC2 must use the application IAM instance profile."
  }

  # Require IMDSv2.
  assert {
    condition = (
      aws_instance.app[0].metadata_options[0].http_tokens == "required"
    )

    error_message = "EC2 must require IMDSv2."
  }

  # Check ECR image scanning and encryption.
  assert {
    condition = (
      aws_ecr_repository.app.image_scanning_configuration[0].scan_on_push == true &&
      aws_ecr_repository.app.encryption_configuration[0].encryption_type == "AES256"
    )

    error_message = "ECR must enable image scanning and encryption."
  }

  # Check CloudWatch log retention.
  assert {
    condition = (
      aws_cloudwatch_log_group.app.retention_in_days == 14
    )

    error_message = "CloudWatch log retention must be 14 days for staging."
  }

  # Check required ECR and CloudWatch IAM permissions.
  assert {
    condition = (
      contains(local.ecr_pull_actions, "ecr:BatchGetImage") &&
      contains(local.ecr_pull_actions, "ecr:GetDownloadUrlForLayer") &&
      contains(local.log_write_actions, "logs:PutLogEvents")
    )

    error_message = "Required ECR or CloudWatch permissions are missing."
  }
}
