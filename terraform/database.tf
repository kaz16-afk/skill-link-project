# ---------------------------------------------------------
# DynamoDB (User Management)
# ---------------------------------------------------------
resource "aws_dynamodb_table" "line_users" {
  provider     = aws.virginia
  name         = "SkillLink-LineUsers"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "userId"

  attribute {
    name = "userId"
    type = "S"
  }

  point_in_time_recovery {
    enabled = false
  }

  tags = {
    project = "skill-link"
  }
}

# ---------------------------------------------------------
# SQS (Knowledge Base Sync)
# ---------------------------------------------------------
resource "aws_sqs_queue" "kb_sync_queue" {
  provider                   = aws.virginia
  name                       = "KnowledgeBaseSyncSQS"
  delay_seconds              = 0
  max_message_size           = 262144
  message_retention_seconds  = 345600
  receive_wait_time_seconds  = 0
  visibility_timeout_seconds = 300

  tags = {
    project = "skill-link"
  }
}