terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
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

resource "random_id" "suffix" {
  byte_length = 4
}

# ==============================================================================
# 1. S3 バケット (データソース用 - Skill Sheet)
# ==============================================================================
resource "aws_s3_bucket" "skill_sheet_bucket" {
  # 世界で一意にするためランダム文字列を追加
  bucket = "skill-link-engineer-skill-sheet-${random_id.suffix.hex}"
  
  # 中身があっても強制削除できるようにする
  force_destroy = true
}

# バケット配下に 01_01_DevelopmentEngineer フォルダを作成
resource "aws_s3_object" "folder_dev" {
  bucket       = aws_s3_bucket.skill_sheet_bucket.id
  key          = "01_01_DevelopmentEngineer/"
  content_type = "application/x-directory"
}

# バケット配下に 02_CloudEngineer フォルダを作成
resource "aws_s3_object" "folder_cloud" {
  bucket       = aws_s3_bucket.skill_sheet_bucket.id
  key          = "02_CloudEngineer/"
  content_type = "application/x-directory"
}

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
# ==============================================================================
# 2. Bedrock Knowledge Base (Pinecone連携)
# ==============================================================================

# (A) IAM Role
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
        Effect = "Allow", Action = ["bedrock:InvokeModel"],
        Resource = ["arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"]
      },
      {
        Effect = "Allow", Action = ["s3:GetObject", "s3:ListBucket"],
        Resource = [aws_s3_bucket.skill_sheet_bucket.arn, "${aws_s3_bucket.skill_sheet_bucket.arn}/*"]
      },
      {
        Effect = "Allow", Action = ["secretsmanager:GetSecretValue"],
        Resource = [var.pinecone_secret_arn]
      }
    ]
  })
}

# (B) Knowledge Base
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

# (C) Data Source
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
# 3. IAM Roles for Lambda
# ==============================================================================
# (簡略化のためポリシーアタッチメントを共通化していますが、役割は分かれています)

# --- KB Sync Role ---
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
    Statement = [{
      Effect = "Allow", Action = ["bedrock:StartIngestionJob", "bedrock:GetIngestionJob"],
      Resource = [aws_bedrockagent_knowledge_base.main.arn]
    }]
  })
}
resource "aws_iam_role_policy_attachment" "kb_sync_basic" {
  role       = aws_iam_role.kb_sync_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# --- Presigned URL Role ---
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

# --- Webhook Role ---
resource "aws_iam_role" "webhook_role" {
  name = "skill-link-webhook-role-${random_id.suffix.hex}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}
resource "aws_iam_role_policy" "webhook_policy" {
  name = "WebhookPolicy"
  role = aws_iam_role.webhook_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = ["bedrock:RetrieveAndGenerate", "bedrock:Retrieve", "bedrock:InvokeModel"],
      Resource = "*" 
    }]
  })
}
resource "aws_iam_role_policy_attachment" "webhook_basic" {
  role       = aws_iam_role.webhook_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ==============================================================================
# 4. Lambda Functions (★Path Updated)
# ==============================================================================

# --- (A) KB Sync ---
data "archive_file" "kb_sync_zip" {
  type        = "zip"
  # ★パス修正: ルートから見て backend/lambda にある
  source_file = "${path.module}/backend/lambda/kb_sync.py"
  output_path = "${path.module}/backend/lambda/kb_sync.zip"
}

resource "aws_lambda_function" "kb_sync" {
  filename      = data.archive_file.kb_sync_zip.output_path
  function_name = "skill-link-kb-sync-${random_id.suffix.hex}"
  role          = aws_iam_role.kb_sync_role.arn
  handler       = "kb_sync.lambda_handler"
  runtime       = "python3.11"
  timeout       = 60
  source_code_hash = data.archive_file.kb_sync_zip.output_base64sha256
  
  environment {
    variables = {
      KNOWLEDGE_BASE_ID = aws_bedrockagent_knowledge_base.main.id
      DATA_SOURCE_ID    = aws_bedrockagent_data_source.main.data_source_id
    }
  }
}

# --- (B) Presigned URL ---
data "archive_file" "presigned_zip" {
  type        = "zip"
  source_file = "${path.module}/backend/lambda/presigned.py"
  output_path = "${path.module}/backend/lambda/presigned.zip"
}
resource "aws_lambda_function" "presigned" {
  filename      = data.archive_file.presigned_zip.output_path
  function_name = "skill-link-presigned-${random_id.suffix.hex}"
  role          = aws_iam_role.presigned_url_role.arn
  handler       = "presigned.lambda_handler"
  runtime       = "python3.11"
  timeout       = 10
  source_code_hash = data.archive_file.presigned_zip.output_base64sha256
  environment {
    variables = { BUCKET_NAME = aws_s3_bucket.skill_sheet_bucket.id }
  }
}

# --- (C) Webhook Handler ---
data "archive_file" "webhook_zip" {
  type        = "zip"
  source_file = "${path.module}/backend/lambda/webhook_handler.py"
  output_path = "${path.module}/backend/lambda/webhook_handler.zip"
}
resource "aws_lambda_function" "webhook_handler" {
  filename      = data.archive_file.webhook_zip.output_path
  function_name = "skill-link-webhook-${random_id.suffix.hex}"
  role          = aws_iam_role.webhook_role.arn
  handler       = "webhook_handler.lambda_handler"
  runtime       = "python3.11"
  timeout       = 60
  source_code_hash = data.archive_file.webhook_zip.output_base64sha256

  environment {
    variables = {
      LINE_CHANNEL_ACCESS_TOKEN = var.line_channel_token
      BUCKET_NAME               = aws_s3_bucket.skill_sheet_bucket.id
      BEDROCK_KB_ID             = aws_bedrockagent_knowledge_base.main.id
      S3_ACCESS_KEY             = aws_iam_access_key.s3_readonly_key.id
      S3_SECRET_KEY             = aws_iam_access_key.s3_readonly_key.secret
    }
  }
}

# ==============================================================================
# 5. S3 Trigger
# ==============================================================================
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.kb_sync.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.skill_sheet_bucket.arn
}
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.skill_sheet_bucket.id
  lambda_function {
    lambda_function_arn = aws_lambda_function.kb_sync.arn
    events              = ["s3:ObjectCreated:*"]
  }
  depends_on = [aws_lambda_permission.allow_s3]
}

# ==============================================================================
# 6. IAM User for S3 Read-Only
# ==============================================================================
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