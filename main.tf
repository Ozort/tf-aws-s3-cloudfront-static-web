resource "aws_s3_bucket" "website_bucket" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_public_access_block" "website_bucket" {
  bucket = aws_s3_bucket.website_bucket.id

  block_public_acls   = true
  ignore_public_acls  = true
  # These two stay false: the bucket policy below grants access to
  # CloudFront's service principal, and a fully restrictive setting
  # here would block that policy too.
  block_public_policy     = false
  restrict_public_buckets = false
}

# Uploads every file under website/ — add, rename, or remove a file there
# and `terraform apply` picks it up automatically. No per-file resource
# blocks to maintain.
resource "aws_s3_object" "website_files" {
  for_each = fileset("website/", "**")

  bucket = aws_s3_bucket.website_bucket.id
  key    = each.value
  source = "website/${each.value}"
  etag   = filemd5("website/${each.value}")

  content_type = lookup(
    {
      html = "text/html"
      htm  = "text/html"
      css  = "text/css"
      js   = "application/javascript"
      json = "application/json"
      png  = "image/png"
      jpg  = "image/jpeg"
      jpeg = "image/jpeg"
      svg  = "image/svg+xml"
      ico  = "image/x-icon"
      txt  = "text/plain"
    },
    lower(element(split(".", each.value), length(split(".", each.value)) - 1)),
    "application/octet-stream"
  )
}

resource "aws_cloudfront_origin_access_control" "website_oac" {
  name                              = "${var.bucket_name}-oac"
  description                       = "OAC for ${var.bucket_name} static website"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "cloudfront_distribution" {
  origin {
    domain_name              = aws_s3_bucket.website_bucket.bucket_regional_domain_name
    origin_id                = var.bucket_name
    origin_access_control_id = aws_cloudfront_origin_access_control.website_oac.id
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = var.website_index_document

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = var.bucket_name

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                 = 86400
    compress                = true
    viewer_protocol_policy = "redirect-to-https"
  }

  custom_error_response {
    error_code         = 404
    response_code      = 404
    response_page_path = "/error.html"
  }

  # S3 returns 403 (not 404) for a missing object when the bucket policy
  # doesn't grant s3:ListBucket — which is the case here. Without this,
  # most "page not found" cases would bypass the 404 rule above.
  custom_error_response {
    error_code         = 403
    response_code      = 404
    response_page_path = "/error.html"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name        = "Cloudfront Distribution"
    Environment = "Dev"
  }
}

resource "aws_s3_bucket_policy" "website_bucket_policy" {
  bucket = aws_s3_bucket.website_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowCloudFrontServicePrincipalReadOnly"
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.website_bucket.arn}/*"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.cloudfront_distribution.arn
          }
        }
      }
    ]
  })
}

