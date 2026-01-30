# --------------------------------------------------------------------------------
# DNS & SSL Configuration (Reference Only)
# ※ドメイン未取得のため、本環境では適用していません。（設計リファレンスとして保存）
# --------------------------------------------------------------------------------

/*
locals {
  domain_name = "skill-link.io"
  sub_domain  = "www.skill-link.io"
}

# 1. Route53 Hosted Zone
resource "aws_route53_zone" "main" {
  name = local.domain_name
  
  tags = {
    project = var.project_name
  }
}

# 2. ACM Certificate
resource "aws_acm_certificate" "cert" {
  provider          = aws.virginia
  domain_name       = local.sub_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    project = var.project_name
  }
}

# 3. DNS Record for CloudFront
resource "aws_route53_record" "cdn_alias" {
  zone_id = aws_route53_zone.main.zone_id
  name    = local.sub_domain
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.frontend_cdn.domain_name
    zone_id                = aws_cloudfront_distribution.frontend_cdn.hosted_zone_id
    evaluate_target_health = false
  }
}
*/