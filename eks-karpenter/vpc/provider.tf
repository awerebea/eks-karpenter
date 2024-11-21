provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      project    = var.project_name
      managed_by = "Terraform"
    }
  }
}

terraform {
  required_version = "~> 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
