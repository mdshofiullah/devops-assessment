
terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 6.71.0"
    }
  }

  # Remote state will be configured when an AWS account is available.
  backend "s3" {}
}
