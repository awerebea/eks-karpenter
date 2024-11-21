locals {
  bucket   = "terraform-states-opsfleet-assignment-495599757520-us-east-2"
  dynamodb = "terraform-state-lock"
  profile  = "my-profile"
  region   = "us-east-2"
  project  = "opsfleet-assignment"
}

provider "aws" {
  profile = local.profile
  region  = local.region
  default_tags {
    tags = {
      project = local.project
      purpose = "Terraform backend"
    }
  }
}

resource "aws_s3_bucket" "tf_state" {
  bucket = local.bucket

  tags = {
    Name = "Terraform State Bucket"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_dynamodb_table" "tf_state_lock" {
  name         = local.dynamodb
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name = "Terraform State Lock Table"
  }
}

output "s3_bucket_name" {
  value = aws_s3_bucket.tf_state.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.tf_state_lock.id
}
