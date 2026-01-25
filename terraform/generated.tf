# __generated__ by Terraform
# Please review these resources and move them into your main configuration files.

# __generated__ by Terraform from "57kg1g3s3c"
resource "aws_apigatewayv2_api" "webhook_api" {
  api_key_selection_expression = "$request.header.x-api-key"
  body                         = null
  credentials_arn              = null
  description                  = null
  disable_execute_api_endpoint = false
  fail_on_warnings             = null
  ip_address_type              = "ipv4"
  name                         = "skilllink-line-webhook-api"
  protocol_type                = "HTTP"
  route_key                    = null
  route_selection_expression   = "$request.method $request.path"
  tags                         = {}
  tags_all                     = {}
  target                       = null
  version                      = null
}

# __generated__ by Terraform from "skill-link-frontend"
resource "aws_s3_bucket" "frontend_bucket" {
  bucket              = "skill-link-frontend"
  bucket_prefix       = null
  force_destroy       = null
  object_lock_enabled = false
  tags                = {}
  tags_all            = {}
}

# __generated__ by Terraform from "E1CSUDH2Y02E8T"
resource "aws_cloudfront_distribution" "frontend_cdn" {
  aliases                         = []
  comment                         = "skill-link-frontend"
  continuous_deployment_policy_id = null
  default_root_object             = "index.html"
  enabled                         = true
  http_version                    = "http2"
  is_ipv6_enabled                 = true
  price_class                     = "PriceClass_All"
  retain_on_delete                = false
  staging                         = false
  tags = {
    Name = "skill-link-web-prd-static01"
  }
  tags_all = {
    Name = "skill-link-web-prd-static01"
  }
  wait_for_deployment = true
  web_acl_id          = "arn:aws:wafv2:us-east-1:864624564932:global/webacl/CreatedByCloudFront-5e8bf3e1/9f78be5c-9bdc-4279-9b67-549961f66b90"
  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD"]
    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    default_ttl                = 0
    field_level_encryption_id  = null
    max_ttl                    = 0
    min_ttl                    = 0
    origin_request_policy_id   = null
    realtime_log_config_arn    = null
    response_headers_policy_id = null
    smooth_streaming           = false
    target_origin_id           = "sl-engineer-skill-sheet.s3.us-east-1.amazonaws.com-mkay0ceq0x5"
    trusted_key_groups         = []
    trusted_signers            = []
    viewer_protocol_policy     = "redirect-to-https"
    grpc_config {
      enabled = false
    }
  }
  origin {
    connection_attempts      = 3
    connection_timeout       = 10
    domain_name              = "skill-link-frontend.s3.ap-northeast-1.amazonaws.com"
    origin_access_control_id = "E2P3ZG5L28FQ6E"
    origin_id                = "sl-engineer-skill-sheet.s3.us-east-1.amazonaws.com-mkay0ceq0x5"
    origin_path              = null
  }
  restrictions {
    geo_restriction {
      locations        = []
      restriction_type = "none"
    }
  }
  viewer_certificate {
    acm_certificate_arn            = null
    cloudfront_default_certificate = true
    iam_certificate_id             = null
    minimum_protocol_version       = "TLSv1"
    ssl_support_method             = null
  }
}

# __generated__ by Terraform from "us-east-1_kwnRvLfPn"
resource "aws_cognito_user_pool" "main_pool" {
  provider                   = aws.virginia
  alias_attributes           = null
  auto_verified_attributes   = ["email"]
  deletion_protection        = "ACTIVE"
  email_verification_message = null
  email_verification_subject = null
  mfa_configuration          = "OFF"
  name                       = "SkillLink-Userpool"
  sms_authentication_message = null
  sms_verification_message   = null
  tags                       = {}
  tags_all                   = {}
  user_pool_tier             = "ESSENTIALS"
  username_attributes        = ["email"]
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
    recovery_mechanism {
      name     = "verified_phone_number"
      priority = 2
    }
  }
  admin_create_user_config {
    allow_admin_create_user_only = false
  }
  email_configuration {
    configuration_set      = null
    email_sending_account  = "COGNITO_DEFAULT"
    from_email_address     = null
    reply_to_email_address = null
    source_arn             = null
  }
  lambda_config {
    create_auth_challenge          = null
    custom_message                 = null
    define_auth_challenge          = null
    kms_key_id                     = null
    post_authentication            = null
    post_confirmation              = null
    pre_authentication             = null
    pre_sign_up                    = "arn:aws:lambda:us-east-1:864624564932:function:SkillLinkDomainGuard"
    pre_token_generation           = null
    user_migration                 = null
    verify_auth_challenge_response = null
  }
  password_policy {
    minimum_length                   = 8
    password_history_size            = 0
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 7
  }
  schema {
    attribute_data_type      = "String"
    developer_only_attribute = false
    mutable                  = true
    name                     = "email"
    required                 = true
    string_attribute_constraints {
      max_length = "2048"
      min_length = "0"
    }
  }
  sign_in_policy {
    allowed_first_auth_factors = ["PASSWORD"]
  }
  username_configuration {
    case_sensitive = false
  }
  verification_message_template {
    default_email_option  = "CONFIRM_WITH_CODE"
    email_message         = null
    email_message_by_link = null
    email_subject         = null
    email_subject_by_link = null
    sms_message           = null
  }
}

# __generated__ by Terraform from "sl-engineer-skill-sheet"
resource "aws_s3_bucket" "skill_sheet_bucket" {
  provider            = aws.virginia
  bucket              = "sl-engineer-skill-sheet"
  bucket_prefix       = null
  force_destroy       = null
  object_lock_enabled = false
  tags = {
    project = "skill-link"
  }
  tags_all = {
    project = "skill-link"
  }
}

# 1. DynamoDB: LINEユーザー管理
resource "aws_dynamodb_table" "line_users" {
  provider     = aws.virginia
  name         = "SkillLink-LineUsers"
  billing_mode = "PAY_PER_REQUEST" # オンデマンドモード
  hash_key     = "userId"

  attribute {
    name = "userId"
    type = "S"
  }

  # 自動生成でエラーになりがちなバックアップ設定等は一旦無効化
  point_in_time_recovery {
    enabled = false
  }

  tags = {
    project = "skill-link"
  }
}

# 2. SQS: ナレッジベース同期用 (サイズ制限修正済み)
resource "aws_sqs_queue" "kb_sync_queue" {
  provider                  = aws.virginia
  name                      = "KnowledgeBaseSyncSQS"
  delay_seconds             = 0
  max_message_size          = 262144 # 256KB (修正済み)
  message_retention_seconds = 345600 # 4日
  receive_wait_time_seconds = 0
  visibility_timeout_seconds = 300   # Lambdaのタイムアウトに合わせる
}

# 3. Lambda: LINE Bot Webhook (東京)
resource "aws_lambda_function" "webhook_handler" {
  function_name = "SkillLinkWebhookHandler"
  role          = "arn:aws:iam::864624564932:role/service-role/SkillLinkWebhookHandler-role-xxxxxx" # ※後でロールARNを書き換える必要があります
  handler       = "index.handler"
  runtime       = "python3.11"
  
  # コード管理外の設定
  filename         = "dummy.zip" 
  source_code_hash = "dummy"
  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }
}

# 4. Lambda: 署名付きURL発行 (バージニア)
resource "aws_lambda_function" "presigned_url" {
  provider      = aws.virginia
  function_name = "get-presigned-url"
  role          = "arn:aws:iam::864624564932:role/service-role/get-presigned-url-role-xxxxxx" # ※後で書き換え
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"

  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }
}

# 5. Lambda: KB同期トリガー (バージニア)
resource "aws_lambda_function" "kb_sync" {
  provider      = aws.virginia
  function_name = "trigger-knowledge-base-sync"
  role          = "arn:aws:iam::864624564932:role/service-role/trigger-knowledge-base-sync-role-xxxxxx" # ※後で書き換え
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"

  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }
}