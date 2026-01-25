# ---------------------------------------------------------
# Frontend Hosting (S3 + CloudFront)
# ---------------------------------------------------------

# 1. S3 Bucket
resource "aws_s3_bucket" "frontend_bucket" {
  bucket              = "skill-link-frontend"
  object_lock_enabled = false

  tags = {
    project = "skill-link"
  }
}

# 2. Origin Access Control (OAC)
resource "aws_cloudfront_origin_access_control" "frontend_oac" {
  name                              = "skill-link-frontend-oac"
  description                       = "OAC for Skill Link Frontend"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# 3. CloudFront Distribution
resource "aws_cloudfront_distribution" "frontend_cdn" {
  enabled             = true
  comment             = "skill-link-frontend"
  default_root_object = "index.html"
  price_class         = "PriceClass_All"
  http_version        = "http2"
  is_ipv6_enabled     = true
  wait_for_deployment = true

  web_acl_id = "arn:aws:wafv2:us-east-1:<YOUR_ACCOUNT_ID>:global/webacl/CreatedByCloudFront-xxxxxx/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

  aliases = []

  origin {
    domain_name              = "skill-link-engineer-skill-sheet.s3.us-east-1.amazonaws.com"
    origin_id                = "skill-link-engineer-skill-sheet"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend_oac.id
    connection_attempts      = 3
    connection_timeout       = 10
  }

  default_cache_behavior {
    target_origin_id       = "skill-link-engineer-skill-sheet"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
    minimum_protocol_version       = "TLSv1"
  }

  tags = {
    Name    = "skill-link-web-prd-static01"
    project = "skill-link"
  }
}

# ---------------------------------------------------------
# Skill Sheet Storage (Virginia)
# ---------------------------------------------------------
resource "aws_s3_bucket" "skill_sheet_bucket" {
  provider = aws.virginia
  bucket   = "skill-link-engineer-skill-sheet"

  tags = {
    project = "skill-link"
  }
}