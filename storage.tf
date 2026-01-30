# --------------------------------------------------------------------------------
# Frontend Hosting (S3 + CloudFront)
# --------------------------------------------------------------------------------

# 1. S3 Bucket (FrontendのHTML/JSを置く場所)
resource "aws_s3_bucket" "frontend_bucket" {
  # バケット名が被らないようにランダムIDを振る
  bucket              = "${var.project_name}-frontend-hosting-${random_id.suffix.hex}"
  object_lock_enabled = false

  tags = {
    project = var.project_name
  }
}

# 2. S3 Bucket Policy (CloudFrontからのアクセス許可)
resource "aws_s3_bucket_policy" "frontend_policy" {
  bucket = aws_s3_bucket.frontend_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontServicePrincipal"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.frontend_bucket.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.frontend_cdn.arn
          }
        }
      }
    ]
  })
}

# 3. Origin Access Control (OAC)
resource "aws_cloudfront_origin_access_control" "frontend_oac" {
  name                              = "${var.project_name}-frontend-oac-${random_id.suffix.hex}"
  description                       = "OAC for Skill Link Frontend"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# 4. CloudFront Distribution
resource "aws_cloudfront_distribution" "frontend_cdn" {
  enabled             = true
  comment             = "${var.project_name}-frontend"
  default_root_object = "index.html"
  price_class         = "PriceClass_All"
  http_version        = "http2"
  is_ipv6_enabled     = true
  wait_for_deployment = true

  # 変数が未定義のため一旦コメントアウト（WAF作成時に有効化してください）
  # web_acl_id = var.cloudfront_web_acl_arn

  aliases = []

  origin {
    domain_name              = aws_s3_bucket.frontend_bucket.bucket_regional_domain_name
    origin_id                = aws_s3_bucket.frontend_bucket.id
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend_oac.id
    connection_attempts      = 3
    connection_timeout       = 10
  }

  default_cache_behavior {
    target_origin_id       = aws_s3_bucket.frontend_bucket.id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    # Managed-CachingOptimized (AWS推奨のキャッシュポリシーID)
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
    Name    = "${var.project_name}-web-prd"
    project = var.project_name
  }
}

# --------------------------------------------------------------------------------
# React Config & Deployment
# --------------------------------------------------------------------------------

# 5. React用の環境変数ファイル (.env) を自動生成
resource "local_file" "frontend_env" {
  filename = "${path.module}/frontend/.env"
  content  = <<EOF
VITE_API_URL=${aws_apigatewayv2_stage.default.invoke_url}
VITE_COGNITO_USER_POOL_ID=${aws_cognito_user_pool.main_pool.id}
VITE_COGNITO_CLIENT_ID=${aws_cognito_user_pool_client.client.id}
EOF
}

# 6. ビルド成果物 (distフォルダ) のS3アップロード
resource "aws_s3_object" "frontend_assets" {
  # frontend/dist フォルダが存在する場合のみ実行
  for_each = fileset("${path.module}/frontend/dist", "**/*")

  bucket = aws_s3_bucket.frontend_bucket.id
  key    = each.value
  source = "${path.module}/frontend/dist/${each.value}"

  # ファイルタイプごとのContent-Type設定（これがないとダウンロードされてしまう）
  content_type = lookup({
    "html" = "text/html"
    "css"  = "text/css"
    "js"   = "application/javascript"
    "json" = "application/json"
    "png"  = "image/png"
    "jpg"  = "image/jpeg"
    "svg"  = "image/svg+xml"
    "txt"  = "text/plain"
  }, split(".", each.value)[length(split(".", each.value)) - 1], "application/octet-stream")

  etag = filemd5("${path.module}/frontend/dist/${each.value}")
}