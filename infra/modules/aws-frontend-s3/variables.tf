variable "bucket_name" {
  type        = string
  description = "S3 bucket name for the frontend website"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags to apply to all frontend resources"
}