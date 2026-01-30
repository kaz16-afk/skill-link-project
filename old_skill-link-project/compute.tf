# --------------------------------------------------------------------------------
# API Gateway (HTTP API)
# --------------------------------------------------------------------------------
resource "aws_apigatewayv2_api" "webhook_api" {
  name                         = "${var.project_name}-webhook-api"
  protocol_type                = "HTTP"
  route_selection_expression   = "$request.method $request.path"
  api_key_selection_expression = "$request.header.x-api-key"
  disable_execute_api_endpoint = false
  ip_address_type              = "ipv4"

  tags = {
    project = var.project_name
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.webhook_api.id
  name        = "$default"
  auto_deploy = true

  tags = {
    project = var.project_name
  }
}

# --------------------------------------------------------------------------------
# Lambda Source Code Management (Auto-Zip)
# --------------------------------------------------------------------------------
# backend/src フォルダを自動でZIP化する設定
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/backend/src"
  output_path = "${path.module}/lambda_function.zip"
}

# --------------------------------------------------------------------------------
# Lambda Functions
# --------------------------------------------------------------------------------

# 1. LINE Bot Webhook Handler (Tokyo)
resource "aws_lambda_function" "webhook_handler" {
  function_name = "${var.project_name}-webhook-handler"
  role          = aws_iam_role.webhook_handler_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  timeout       = 30

  # 自動生成されたZIPファイルを使用
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      LINE_CHANNEL_SECRET = var.line_channel_secret
      LINE_CHANNEL_ACCESS_TOKEN = var.line_channel_token
    }
  }

  tags = {
    project = var.project_name
  }
}

# 2. Get Presigned URL (Virginia)
resource "aws_lambda_function" "presigned_url" {
  provider      = aws.virginia
  function_name = "${var.project_name}-presigned-url"
  role          = aws_iam_role.presigned_url_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"

  # 自動生成されたZIPファイルを使用
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  tags = {
    project = var.project_name
  }
}

# 3. Trigger KB Sync (Virginia)
resource "aws_lambda_function" "kb_sync" {
  provider      = aws.virginia
  function_name = "${var.project_name}-kb-sync"
  role          = aws_iam_role.kb_sync_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  timeout       = 300

  # 自動生成されたZIPファイルを使用
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  tags = {
    project = var.project_name
  }
}