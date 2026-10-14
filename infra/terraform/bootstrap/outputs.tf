output "state_bucket_name" {
  description = "S3 bucket used for Terraform remote state."
  value       = aws_s3_bucket.terraform_state.id
}

output "aws_region" {
  description = "Region containing the state bucket."
  value       = var.aws_region
}
