terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }

  # Remote state backend. The S3 bucket and DynamoDB table below must
  # already exist — Terraform can't create its own backend storage.
  # Replace both with resources in your own AWS account before running
  # `terraform init`.
  #backend "s3" {
   # bucket         = "your-terraform-state-bucket"
   # key            = "tf-aws-s3-cloudfront-static-web/terraform.tfstate"
    #region         = "us-east-1"
    #dynamodb_table = "terraform-locks"
    #encrypt        = true
  #}
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region
}
