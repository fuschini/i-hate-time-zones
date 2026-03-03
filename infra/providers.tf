terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Uncomment and configure once you've created an S3 bucket for remote state.
  # Each environment should use a different key (or use workspaces).
  #
  # backend "s3" {
  #   bucket         = "ihatetimezones-terraform-state"
  #   key            = "infra/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "terraform-state-lock"
  #   encrypt        = true
  # }
}

# Primary provider — used for S3, CloudFront, Route 53
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      project     = "i_hate_time_zones"
      environment = var.environment
    }
  }
}

# ACM certificates for CloudFront must be in us-east-1
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      project     = "i_hate_time_zones"
      environment = var.environment
    }
  }
}
