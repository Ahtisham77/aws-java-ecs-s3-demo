terraform {
  backend "s3" {
    bucket  = "ahti-demo-tf-state" 
    key     = "env/dev/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
    profile = "dev"
  }

  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.100"
    }
  }
}