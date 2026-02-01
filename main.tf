# ==============================================================================
# SKILL-LINK Infrastructure as Code
# ------------------------------------------------------------------------------
# 構成概要:
#   1. Provider & Variables (AWS設定, 変数)
#   2. Auth (Cognito)
#   3. Storage & DB (S3, DynamoDB, SQS)
#   4. AI & RAG (Bedrock, Pinecone連携)
#   5. Backend (Lambda Functions)
#   6. API Gateway (HTTP API)
#   7. Frontend Hosting (S3 + CloudFront)
#   8. Deployment Helpers (.env生成, アップロード)
#   9. Outputs(画面に表示する情報)
# ==============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.0" }
    random = { source = "hashicorp/random", version = "~> 3.0" }
  }
}

# 全リソースをバージニア (us-east-1) で作成
provider "aws" {
  region = "us-east-1"
}

# Cognitoなどのために明示的なエイリアスも残しておく
provider "aws" {
  alias  = "virginia"
  region = "us-east-1"
}

# ==============================================================================
# 0. Variables & Locals (変数定義)
# ==============================================================================
variable "project_name" {
  description = "Project Name for resource naming"
  default     = "skill-link"
}

variable "region" {
  default = "us-east-1"
}

variable "aws_account_id" {
  description = "AWS Account ID (12 digits)"
  type        = string
}

variable "line_channel_token" {
  description = "LINE Channel Access Token"
  type        = string
  sensitive   = true
}

variable "pinecone_index_url" {
  description = "Pinecone Index URL"
  type        = string
}

variable "pinecone_secret_arn" {
  description = "Secrets Manager ARN for Pinecone Key"
  type        = string
}

resource "random_id" "suffix" {
  byte_length = 4
}

# 簡易セキュリティ用APIキーの自動生成 (32文字)
resource "random_password" "api_key" {
  length  = 32
  special = false
}

# ==============================================================================
# 1. Authentication (Cognito: 認証基盤)
# ==============================================================================
resource "aws_cognito_user_pool" "main_pool" {
  provider = aws.virginia
  name     = "${var.project_name}-userpool"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  user_pool_tier           = "ESSENTIALS"
  deletion_protection      = "INACTIVE"
  mfa_configuration        = "OFF"

  username_configuration {
    case_sensitive = false
  }

  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true
  }

  password_policy {
    minimum_length                   = 8
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 7
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  tags = {
    project = var.project_name
  }
}

# Reactアプリが接続するためのクライアント設定
resource "aws_cognito_user_pool_client" "client" {
  provider = aws.virginia
  name     = "${var.project_name}-client"

  user_pool_id = aws_cognito_user_pool.main_pool.id

  # フロントエンドからのアクセスにはクライアントシークレット不要
  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH"
  ]
}

# ==============================================================================
# 2. Database & Storage (S3 / DynamoDB / SQS)
# ==============================================================================

# --- S3 Bucket (スキルシート保存用) ---
resource "aws_s3_bucket" "skill_sheet_bucket" {
  # 世界で一意にするためランダム文字列を追加
  bucket = "skill-link-engineer-skill-sheet-${random_id.suffix.hex}"
  
  # 中身があっても強制削除できるようにする
  force_destroy = true
}

# フォルダ構造の作成 (開発エンジニア用)
resource "aws_s3_object" "folder_dev" {
  bucket       = aws_s3_bucket.skill_sheet_bucket.id
  key          = "01_01_DevelopmentEngineer/"
  content_type = "application/x-directory"
}

# フォルダ構造の作成 (クラウドエンジニア用)
resource "aws_s3_object" "folder_cloud" {
  bucket       = aws_s3_bucket.skill_sheet_bucket.id
  key          = "02_CloudEngineer/"
  content_type = "application/x-directory"
}

# CORS設定 (Webアプリからの直接アップロード用)
resource "aws_s3_bucket_cors_configuration" "main" {
  bucket = aws_s3_bucket.skill_sheet_bucket.id
  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "POST", "GET", "HEAD"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# --- DynamoDB (LINEユーザー管理用) ---
resource "aws_dynamodb_table" "line_users" {
  provider     = aws.virginia
  name         = "${var.project_name}-line-users"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "userId"

  attribute {
    name = "userId"
    type = "S"
  }

  tags = {
    project = var.project_name
  }
}

# --- SQS (Knowledge Base同期トリガー用) ---
# S3へのファイルアップロード通知を一度ここに溜めることで、
# 大量アップロード時のLambda同時起動数(スロットリング)を制御する
resource "aws_sqs_queue" "kb_sync_queue" {
  provider                   = aws.virginia
  name                       = "${var.project_name}-kb-sync-queue"
  delay_seconds              = 0
  max_message_size           = 262144
  message_retention_seconds  = 345600
  # Lambdaのタイムアウト(60秒)より長く設定し、処理中の再配信を防ぐ
  visibility_timeout_seconds = 300 
}

# SQSポリシー: S3バケットからのメッセージ送信を許可
resource "aws_sqs_queue_policy" "s3_to_sqs" {
  queue_url = aws_sqs_queue.kb_sync_queue.id
  policy    = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "s3.amazonaws.com" },
      Action    = "sqs:SendMessage",
      Resource  = aws_sqs_queue.kb_sync_queue.arn,
      Condition = {
        ArnEquals = { "aws:SourceArn" = aws_s3_bucket.skill_sheet_bucket.arn }
      }
    }]
  })
}

# S3イベント通知: ファイル作成時にSQSへ通知を送る
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.skill_sheet_bucket.id
  queue {
    queue_arn     = aws_sqs_queue.kb_sync_queue.arn
    events        = ["s3:ObjectCreated:*"]
  }
  depends_on = [aws_sqs_queue_policy.s3_to_sqs]
}

# S3読み取り専用 IAMユーザー (Lambda等が使用)
resource "aws_iam_user" "s3_readonly_user" {
  name = "skill-link-s3-readonly-${random_id.suffix.hex}"
}
resource "aws_iam_user_policy" "s3_readonly_policy" {
  name = "S3ReadPolicy"
  user = aws_iam_user.s3_readonly_user.name
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      { Effect = "Allow", Action = ["s3:ListBucket"], Resource = [aws_s3_bucket.skill_sheet_bucket.arn] },
      { Effect = "Allow", Action = ["s3:GetObject"], Resource = ["${aws_s3_bucket.skill_sheet_bucket.arn}/*"] }
    ]
  })
}
resource "aws_iam_access_key" "s3_readonly_key" {
  user = aws_iam_user.s3_readonly_user.name
}

# ==============================================================================
# 3. Bedrock Knowledge Base (AI検索基盤)
# ==============================================================================

# (A) Bedrock用 IAM Role
resource "aws_iam_role" "bedrock_kb_role" {
  name = "bedrock-kb-role-${random_id.suffix.hex}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "bedrock.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "bedrock_policies" {
  name = "BedrockAllPolicies"
  role = aws_iam_role.bedrock_kb_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        # Embeddingsモデルの実行権限
        Effect = "Allow", Action = ["bedrock:InvokeModel"],
        Resource = ["arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"]
      },
      {
        # S3データソースへのアクセス権限
        Effect = "Allow", Action = ["s3:GetObject", "s3:ListBucket"],
        Resource = [aws_s3_bucket.skill_sheet_bucket.arn, "${aws_s3_bucket.skill_sheet_bucket.arn}/*"]
      },
      {
        # PineconeのAPIキー取得権限
        Effect = "Allow", Action = ["secretsmanager:GetSecretValue"],
        Resource = [var.pinecone_secret_arn]
      }
    ]
  })
}

# (B) Knowledge Base 定義 (Pinecone接続)
resource "aws_bedrockagent_knowledge_base" "main" {
  name     = "skill-link-kb-${random_id.suffix.hex}"
  role_arn = aws_iam_role.bedrock_kb_role.arn

  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
    }
  }

  storage_configuration {
    type = "PINECONE"
    pinecone_configuration {
      connection_string      = var.pinecone_index_url
      credentials_secret_arn = var.pinecone_secret_arn
      field_mapping {
        metadata_field = "metadata"
        text_field     = "text"
      }
    }
  }
  depends_on = [aws_iam_role_policy.bedrock_policies]
}

# (C) Data Source (S3とKBの紐付け)
resource "aws_bedrockagent_data_source" "main" {
  knowledge_base_id = aws_bedrockagent_knowledge_base.main.id
  name              = "skill-link-datasource-${random_id.suffix.hex}"
  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn = aws_s3_bucket.skill_sheet_bucket.arn
    }
  }
}

# ==============================================================================
# 4. Backend Logic (Lambda Functions)
# ==============================================================================

# --- IAM Roles for Lambda ---

# 1. KB Sync Role (同期実行用Lambdaの権限)
# SQSからメッセージを受け取り、Bedrockの同期を開始するために必要
resource "aws_iam_role" "kb_sync_role" {
  name = "skill-link-kb-sync-role-${random_id.suffix.hex}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}
resource "aws_iam_role_policy" "kb_sync_policy" {
  name = "SyncPolicy"
  role = aws_iam_role.kb_sync_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        # Bedrock同期ジョブの実行権限 (権限エラー対策でAssociateThirdPartyを追加)
        Effect = "Allow", 
        Action = ["bedrock:StartIngestionJob", "bedrock:GetIngestionJob", "bedrock:AssociateThirdPartyKnowledgeBase"],
        Resource = [aws_bedrockagent_knowledge_base.main.arn]
      },
      {
        # SQSからのメッセージ受信・削除権限
        Effect = "Allow",
        Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"],
        Resource = [aws_sqs_queue.kb_sync_queue.arn]
      }
    ]
  })
}
resource "aws_iam_role_policy_attachment" "kb_sync_basic" {
  role       = aws_iam_role.kb_sync_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# 2. Presigned URL Role (署名付きURL発行用)
resource "aws_iam_role" "presigned_url_role" {
  name = "skill-link-presigned-role-${random_id.suffix.hex}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}
resource "aws_iam_role_policy" "presigned_policy" {
  name = "PresignedPolicy"
  role = aws_iam_role.presigned_url_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Effect = "Allow", Action = ["s3:PutObject", "s3:GetObject"], Resource = "${aws_s3_bucket.skill_sheet_bucket.arn}/*" }]
  })
}
resource "aws_iam_role_policy_attachment" "presigned_basic" {
  role       = aws_iam_role.presigned_url_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# 3. Webhook Role (LINE Bot用)
resource "aws_iam_role" "webhook_role" {
  name = "skill-link-webhook-role-${random_id.suffix.hex}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}

# Webhook Lambdaに必要な権限セット
resource "aws_iam_role_policy" "webhook_policy" {
  name = "WebhookPolicy"
  role = aws_iam_role.webhook_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = [
        "bedrock:RetrieveAndGenerate", # RAG検索
        "bedrock:Retrieve",
        "bedrock:InvokeModel",
        "dynamodb:PutItem", # ユーザー登録
        "dynamodb:GetItem", 
        "dynamodb:UpdateItem"
      ],
      Resource = "*" 
    }]
  })
}
resource "aws_iam_role_policy_attachment" "webhook_basic" {
  role       = aws_iam_role.webhook_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# --- Lambda Function Definitions ---

# Function A: KB Sync (Triggered by SQS)
data "archive_file" "kb_sync_zip" {
  type        = "zip"
  source_file = "${path.module}/backend/lambda/kb_sync.py"
  output_path = "${path.module}/backend/lambda/kb_sync.zip"
}
resource "aws_lambda_function" "kb_sync" {
  filename         = data.archive_file.kb_sync_zip.output_path
  function_name    = "skill-link-kb-sync-${random_id.suffix.hex}"
  role             = aws_iam_role.kb_sync_role.arn
  handler          = "kb_sync.lambda_handler"
  runtime          = "python3.11"
  timeout          = 60
  source_code_hash = data.archive_file.kb_sync_zip.output_base64sha256
  
  environment {
    variables = {
      KNOWLEDGE_BASE_ID = aws_bedrockagent_knowledge_base.main.id
      DATA_SOURCE_ID    = aws_bedrockagent_data_source.main.data_source_id
    }
  }
}

# ★Event Source Mapping: SQS -> Lambda
# SQSにメッセージが入ると、Lambdaが自動的に起動される設定
resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.kb_sync_queue.arn
  function_name    = aws_lambda_function.kb_sync.arn
  batch_size       = 1    # 1件ずつ確実に処理する
  enabled          = true # トリガー有効化
}

# Function B: Presigned URL (For Frontend Upload)
data "archive_file" "presigned_zip" {
  type        = "zip"
  source_file = "${path.module}/backend/lambda/presigned.py"
  output_path = "${path.module}/backend/lambda/presigned.zip"
}
resource "aws_lambda_function" "presigned" {
  filename         = data.archive_file.presigned_zip.output_path
  function_name    = "skill-link-presigned-${random_id.suffix.hex}"
  role             = aws_iam_role.presigned_url_role.arn
  handler          = "presigned.lambda_handler"
  runtime          = "python3.11"
  timeout          = 10
  source_code_hash = data.archive_file.presigned_zip.output_base64sha256
  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.skill_sheet_bucket.id
      API_KEY     = random_password.api_key.result
    }
  }
}

# Function C: Webhook Handler (For LINE Bot)
data "archive_file" "webhook_zip" {
  type        = "zip"
  source_file = "${path.module}/backend/lambda/webhook_handler.py"
  output_path = "${path.module}/backend/lambda/webhook_handler.zip"
}
resource "aws_lambda_function" "webhook_handler" {
  filename         = data.archive_file.webhook_zip.output_path
  function_name    = "skill-link-webhook-${random_id.suffix.hex}"
  role             = aws_iam_role.webhook_role.arn
  handler          = "webhook_handler.lambda_handler"
  runtime          = "python3.11"
  timeout          = 60
  source_code_hash = data.archive_file.webhook_zip.output_base64sha256

  environment {
    variables = {
      LINE_CHANNEL_ACCESS_TOKEN = var.line_channel_token
      BUCKET_NAME               = aws_s3_bucket.skill_sheet_bucket.id
      BEDROCK_KB_ID             = aws_bedrockagent_knowledge_base.main.id
      S3_ACCESS_KEY             = aws_iam_access_key.s3_readonly_key.id
      S3_SECRET_KEY             = aws_iam_access_key.s3_readonly_key.secret
      DYNAMODB_TABLE_NAME       = aws_dynamodb_table.line_users.name
    }
  }
}

# ==============================================================================
# 5. API Gateway (HTTP API)
# ==============================================================================
resource "aws_apigatewayv2_api" "main" {
  name          = "skill-link-api-${random_id.suffix.hex}"
  protocol_type = "HTTP"
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["content-type", "authorization", "x-skill-link-auth"]
    max_age       = 300
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "prod"
  auto_deploy = true
}

# --- Route 1: Presigned URL (POST /upload) ---
resource "aws_apigatewayv2_integration" "presigned_integration" {
  api_id             = aws_apigatewayv2_api.main.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.presigned.invoke_arn
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "post_upload_url" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "POST /upload"
  target    = "integrations/${aws_apigatewayv2_integration.presigned_integration.id}"
}

resource "aws_lambda_permission" "api_gw_presigned" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.presigned.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

# --- Route 2: Webhook (POST /callback) ---
resource "aws_apigatewayv2_integration" "webhook_integration" {
  api_id             = aws_apigatewayv2_api.main.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.webhook_handler.invoke_arn
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "post_callback" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "POST /callback"
  target    = "integrations/${aws_apigatewayv2_integration.webhook_integration.id}"
}

resource "aws_lambda_permission" "api_gw_webhook" {
  statement_id  = "AllowExecutionFromAPIGatewayWebhook"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.webhook_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

# ==============================================================================
# 6. Frontend Hosting (S3 + CloudFront)
# ==============================================================================

# 1. S3 Bucket (FrontendのHTML/JSを置く場所)
resource "aws_s3_bucket" "frontend_bucket" {
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
  name                              = "${var.project_name}-oac-${random_id.suffix.hex}"
  description                       = "OAC for Frontend S3"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}
# ==============================================================================
# Route53 & ACM Custom Domain Configuration
# ※独自ドメイン運用時にコメントアウトを解除して有効化するセクション
# ==============================================================================

# variable "domain_name" {
#   description = "Webサイトの独自ドメイン (例: skill-link.com)"
#   type        = string
#   default     = "example.com" # ここに実際のドメインを入力
# }

# # 1. ホストゾーンの参照 (既にRoute53にドメイン登録済みと仮定)
# data "aws_route53_zone" "main" {
#   provider = aws.virginia
#   name     = var.domain_name
# }

# # 2. ACM証明書の作成 (CloudFront用に必ずus-east-1で作成)
# resource "aws_acm_certificate" "cert" {
#   provider          = aws.virginia
#   domain_name       = var.domain_name
#   validation_method = "DNS"
#   lifecycle { create_before_destroy = true }
# }

# # 3. DNS検証用レコードの作成
# resource "aws_route53_record" "cert_validation" {
#   provider = aws.virginia
#   for_each = {
#     for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
#       name   = dvo.resource_record_name
#       record = dvo.resource_record_value
#       type   = dvo.resource_record_type
#     }
#   }
#   allow_overwrite = true
#   name            = each.value.name
#   records         = [each.value.record]
#   ttl             = 60
#   type            = each.value.type
#   zone_id         = data.aws_route53_zone.main.zone_id
# }

# # 4. 証明書の有効化待ち
# resource "aws_acm_certificate_validation" "cert" {
#   provider                = aws.virginia
#   certificate_arn         = aws_acm_certificate.cert.arn
#   validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
# }

# # 5. CloudFrontのエイリアスレコード登録 (Aレコード)
# resource "aws_route53_record" "cdn_alias" {
#   provider = aws.virginia
#   zone_id  = data.aws_route53_zone.main.zone_id
#   name     = var.domain_name
#   type     = "A"
#   alias {
#     name                   = aws_cloudfront_distribution.frontend_cdn.domain_name
#     zone_id                = aws_cloudfront_distribution.frontend_cdn.hosted_zone_id
#     evaluate_target_health = false
#   }
# }

# 4. CloudFront Distribution
resource "aws_cloudfront_distribution" "frontend_cdn" {
  origin {
    domain_name              = aws_s3_bucket.frontend_bucket.bucket_regional_domain_name
    origin_id                = "S3Origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend_oac.id
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3Origin"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

# [Future Update] 独自ドメイン使用時は aliases を有効化
  # aliases = [var.domain_name]

  viewer_certificate {
    cloudfront_default_certificate = true
    minimum_protocol_version       = "TLSv1"
    
    # [Future Update] ACM有効化時は上記3行を削除し、以下を使用
    # acm_certificate_arn      = aws_acm_certificate.cert.arn
    # ssl_support_method       = "sni-only"
    # minimum_protocol_version = "TLSv1.2_2021"
  }
  
  tags = {
    Name    = "${var.project_name}-web-prd"
    project = var.project_name
  }
}

# ==============================================================================
# 7. Deployment Helpers (.env自動生成 & アップロード)
# ==============================================================================

# フロントエンド用 .env ファイルの自動生成
resource "local_file" "frontend_env" {
  filename = "${path.module}/frontend/.env"
  content  = <<EOF
VITE_API_URL=${aws_apigatewayv2_stage.default.invoke_url}
VITE_COGNITO_USER_POOL_ID=${aws_cognito_user_pool.main_pool.id}
VITE_COGNITO_CLIENT_ID=${aws_cognito_user_pool_client.client.id}
VITE_API_KEY=${random_password.api_key.result}
EOF
}

# ビルド成果物 (distフォルダ) のS3アップロード
resource "aws_s3_object" "frontend_assets" {
  # frontend/dist フォルダが存在する場合のみ実行
  for_each = fileset("${path.module}/frontend/dist", "**/*")

  bucket = aws_s3_bucket.frontend_bucket.id
  key    = each.value
  source = "${path.module}/frontend/dist/${each.value}"

  content_type = lookup({
    "html" = "text/html"
    "css"  = "text/css"
    "js"   = "application/javascript"
    "png"  = "image/png"
    "jpg"  = "image/jpeg"
    "svg"  = "image/svg+xml"
    "json" = "application/json"
  }, split(".", each.value)[length(split(".", each.value)) - 1], "application/octet-stream")

  etag = filemd5("${path.module}/frontend/dist/${each.value}")
}

# ==============================================================================
# 9. Outputs
# ==============================================================================
output "api_gateway_url" {
  value = aws_apigatewayv2_stage.default.invoke_url
}

output "cloudfront_url" {
  value = "https://${aws_cloudfront_distribution.frontend_cdn.domain_name}"
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main_pool.id
}

output "cognito_client_id" {
  value = aws_cognito_user_pool_client.client.id
}