variable "aws_region" {
  default = "us-east-2"
}

variable "aws_profile" {
  default = "my-profile"
}

variable "project_name" {
  default = "opsfleet-assignment"
}

variable "subnet_ids" {
  description = "List of Subnet IDs. If the map contains empty values, the data will be retrieved from the remote state."
  type        = map(string)
  default = {
    private-subnet-az1 = "",
    private-subnet-az2 = "",
    public-subnet-az1  = "",
    public-subnet-az2  = "",
  }
}
