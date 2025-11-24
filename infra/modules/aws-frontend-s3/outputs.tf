output "bucket_name" {
  value       = aws_s3_bucket.this.bucket
  description = "Name of the S3 bucket hosting the frontend"
}

output "website_endpoint" {
  value       = aws_s3_bucket_website_configuration.this.website_endpoint
  description = "Public website endpoint for the frontend"
}