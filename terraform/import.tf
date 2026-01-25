#########################################################
# ✅ 成功するリソース（これらだけ先にコード化します）
#########################################################

# CloudFront
import {
  to = aws_cloudfront_distribution.frontend_cdn
  id = "E1CSUDH2Y02E8T"
}

# S3: フロントエンド用
import {
  to = aws_s3_bucket.frontend_bucket
  id = "skill-link-frontend"
}

# API Gateway
import {
  to = aws_apigatewayv2_api.webhook_api
  id = "57kg1g3s3c"
}

# S3: スキルシート保存用
import {
  to = aws_s3_bucket.skill_sheet_bucket
  id = "sl-engineer-skill-sheet"
  provider = aws.virginia
}

# Cognito User Pool
import {
  to = aws_cognito_user_pool.main_pool
  id = "us-east-1_kwnRvLfPn"
  provider = aws.virginia
}

#########################################################
# ❌ エラーが出るリソース（一旦コメントアウトして無視します）
#########################################################

# Lambda: LINE Bot用
# import {
#   to = aws_lambda_function.webhook_handler
#   id = "SkillLinkWebhookHandler"
# }

# DynamoDB
# import {
#   to = aws_dynamodb_table.line_users
#   id = "SkillLink-LineUsers"
#   provider = aws.virginia
# }

# Bedrock KB (依存関係でエラーになるため一旦除外)
# import {
#   to = aws_bedrockagent_knowledge_base.skill_link_kb
#   id = "PHT26UYFVY"
#   provider = aws.virginia
# }

# Lambda 1
# import {
#   to = aws_lambda_function.presigned_url
#   id = "get-presigned-url"
#   provider = aws.virginia
# }

# Lambda 2
# import {
#   to = aws_lambda_function.kb_sync
#   id = "trigger-knowledge-base-sync"
#   provider = aws.virginia
# }

# SQS
# import {
#   to = aws_sqs_queue.kb_sync_queue
#   id = "https://sqs.us-east-1.amazonaws.com/864624564932/KnowledgeBaseSyncSQS"
#   provider = aws.virginia
# }