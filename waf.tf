# --------------------------------------------------------------------------------
# WAF Configuration (Reference Only)
# ※コスト最適化のため、本環境では適用していません。（設計リファレンスとして保存）
# --------------------------------------------------------------------------------

/*
# 1. Web ACL (Regional for API Gateway)
resource "aws_wafv2_web_acl" "api_waf" {
  name        = "${var.project_name}-api-waf"
  description = "Basic WAF for API Gateway"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-api-waf"
    sampled_requests_enabled   = true
  }

  # AWS Managed Rules Common Rule Set
  rule {
    name     = "AWS-AWSManagedRulesCommonRuleSet"
    priority = 10

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWS-AWSManagedRulesCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  tags = {
    project = var.project_name
  }
}

# 2. Association (API Gatewayへの紐付け)
resource "aws_wafv2_web_acl_association" "main" {
  resource_arn = aws_apigatewayv2_stage.default.arn
  web_acl_arn  = aws_wafv2_web_acl.api_waf.arn
}
*/