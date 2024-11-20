# Use this data resource to retrieve VPC data from the remote state when it is not hardcoded.
data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket  = "terraform-states-opsfleet-assignment-495599757520-us-east-2"
    key     = "vpc/terraform.tfstate"
    region  = var.aws_region
    profile = var.aws_profile
  }
}
