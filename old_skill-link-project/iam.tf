resource "aws_iam_role_policy" "webhook_app_policy" {
  name = "SkillLinkWebhookAppPolicy"
  role = aws_iam_role.webhook_handler_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # DynamoDB (ユーザー管理)
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:GetItem"
        ]
    
        Resource = "arn:aws:dynamodb:*:*:table/${var.project_name}-line-users" 
      },
      # Cognito (管理者操作)
      {
        Effect = "Allow"
        Action = [
          "cognito-idp:AdminGetUser",
          "cognito-idp:AdminSetUserPassword"
        ]
        Resource = "*"
      },
      # Bedrock (RAG検索 & モデル実行)
      {
        Effect = "Allow"
        Action = [
          "bedrock:RetrieveAndGenerate",
          "bedrock:Retrieve",
          "bedrock:InvokeModel"
        ]
        Resource = "*"
      },
      # S3 (スキルシート閲覧)
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.project_name}-engineer-skill-sheet",
          "arn:aws:s3:::${var.project_name}-engineer-skill-sheet/*"
        ]
      }
    ]
  })
}