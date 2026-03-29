variable "aws_region" {
  type        = string
  description = "AWS region to build the AMI in."
  default     = "eu-west-2"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type used during the build."
  default     = "t3.medium"
}

variable "ami_name_prefix" {
  type        = string
  description = "Prefix for the resulting AMI name."
  default     = "rhel9-cis-l2"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID for the build instance. Leave empty to use the default VPC."
  default     = ""
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID for the build instance."
  default     = ""
}

variable "associate_public_ip" {
  type        = bool
  description = "Whether to assign a public IP to the build instance."
  default     = true
}

variable "kms_key_id" {
  type        = string
  description = "KMS key ARN/alias for EBS encryption. Leave empty for AWS-managed key."
  default     = ""
}

variable "ami_regions" {
  type        = list(string)
  description = "Additional regions to copy the AMI to after build."
  default     = []
}

variable "tags" {
  type        = map(string)
  description = "Extra tags to apply to the AMI and build resources."
  default     = {}
}
