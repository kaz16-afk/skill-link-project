# ---------------------------------------------------------
# API Gateway (HTTP API)
# ---------------------------------------------------------
resource "aws_apigatewayv2_api" "webhook_api" {
  name                         = "skilllink-line-webhook-api"
  protocol_type                = "HTTP"
  route_selection_expression   = "$request.method $request.path"
  api_key_selection_expression = "$request.header.x-api-key"
  disable_execute_api_endpoint = false
  ip_address_type              = "ipv4"

  tags = {
    project = "skill-link"
  }
}

# ---------------------------------------------------------
# API Gateway Stage
# ---------------------------------------------------------
# WAFをアタッチするために明示的なステージ定義を追加
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.webhook_api.id
  name        = "$default"
  auto_deploy = true

  tags = {
    project = "skill-link"
  }
}

# ---------------------------------------------------------
# Lambda Functions
# ---------------------------------------------------------

# 1. LINE Bot Webhook Handler (Tokyo)
resource "aws_lambda_function" "webhook_handler" {
  function_name = "SkillLinkWebhookHandler"
  role          = "arn:aws:iam::<YOUR_ACCOUNT_ID>:role/service-role/SkillLinkWebhookHandler-role-xxxxxx"
  handler       = "index.handler"
  runtime       = "python3.11"
  
  # -------------------------------------------------------
  # CI/CD Deployment Strategy
  # アプリケーションコードはGitHub Actions等のCI/CDパイプラインでデプロイするため、
  # Terraformではダミーファイルを配置し、コードの変更差分を検知しない設定にします。
  # -------------------------------------------------------
  filename         = "dummy.zip" 
  source_code_hash = "dummy"

  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }

  tags = {
    project = "skill-link"
  }
}

# 2. Get Presigned URL (Virginia)
resource "aws_lambda_function" "presigned_url" {
  provider      = aws.virginia
  function_name = "get-presigned-url"
  role          = "arn:aws:iam::<YOUR_ACCOUNT_ID>:role/service-role/get-presigned-url-role-xxxxxx"
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"

  # CI/CD管理対象のため、Terraformでのコード変更は無視
  filename         = "dummy.zip" 
  source_code_hash = "dummy"
  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }

  tags = {
    project = "skill-link"
  }
}

# 3. Trigger KB Sync (Virginia)
resource "aws_lambda_function" "kb_sync" {
  provider      = aws.virginia
  function_name = "trigger-knowledge-base-sync"
  role          = "arn:aws:iam::<YOUR_ACCOUNT_ID>:role/service-role/trigger-knowledge-base-sync-role-xxxxxx"
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"

  # CI/CD管理対象のため、Terraformでのコード変更は無視
  filename         = "dummy.zip" 
  source_code_hash = "dummy"
  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }

  tags = {
    project = "skill-link"
  }
}