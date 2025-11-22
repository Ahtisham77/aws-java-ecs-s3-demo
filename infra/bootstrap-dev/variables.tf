variable "region" {
  type        = string
  description = "AWS region for Terraform state bucket"
  default     = "us-east-1"
}

variable "state_bucket_name" {
  type        = string
  description = "Name for S3 bucket used for Terraform state"
  default     = "ahti-demo-tf-state"
}
