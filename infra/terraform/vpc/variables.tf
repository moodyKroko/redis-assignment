variable "aws_region" {
  description = "AWS Region used for the lab."
  type        = string
  default     = "us-east-1"
}

variable "aws_account_id" {
  description = "The AWS account where resources may be created."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must contain exactly 12 digits."
  }
}

variable "project_name" {
  description = "Prefix used for resource names."
  type        = string
  default     = "redis-lab"
}

variable "vpc_cidr" {
  description = "IPv4 CIDR for the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "subnets" {
  description = "Public and private subnet settings for each Availability Zone."

  type = map(object({
    availability_zone = string
    public_cidr       = string
    private_cidr      = string
  }))

  validation {
    condition     = length(var.subnets) == 2
    error_message = "This lab expects two Availability Zone configurations."
  }
}

variable "enable_nat_gateway" {
  description = "Create a paid NAT gateway and private default routes."
  type        = bool
  default     = false
}
