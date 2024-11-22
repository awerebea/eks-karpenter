terraform {
  backend "s3" {
    bucket         = "terraform-states-opsfleet-assignment-495599757520-us-east-2"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
    key            = "eks/terraform.tfstate"
  }
}
