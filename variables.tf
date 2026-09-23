variable "bucket_name" {
  description = "Name of the S3 bucket to host the website."
  type        = string
}

variable "website_index_document" {
  description = "This is the website index document"
  type        = string
  default     = "index.html"
}

variable "aws_region" {
  description = "AWS region to deploy the S3 bucket into"
  type        = string
}
