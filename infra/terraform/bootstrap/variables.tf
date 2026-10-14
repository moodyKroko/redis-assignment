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

