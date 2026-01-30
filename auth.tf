# --------------------------------------------------------------------------------
# Authentication (Cognito User Pool)
# --------------------------------------------------------------------------------
resource "aws_cognito_user_pool" "main_pool" {
  provider = aws.virginia

  name = "${var.project_name}-userpool"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  user_pool_tier           = "ESSENTIALS"
  deletion_protection      = "ACTIVE"
  mfa_configuration        = "OFF"

  username_configuration {
    case_sensitive = false
  }

  schema {
    name                     = "email"
    attribute_data_type      = "String"
    required                 = true
    mutable                  = true
    developer_only_attribute = false
    string_attribute_constraints {
      min_length = "0"
      max_length = "2048"
    }
  }

  password_policy {
    minimum_length                   = 8
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 7
    password_history_size            = 0
  }

  sign_in_policy {
    allowed_first_auth_factors = ["PASSWORD"]
  }

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
    email_sending_account = "COGNITO_DEFAULT"
  }

  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
  }

  tags = {
    project = var.project_name
  }
}

# ================================================================================
# ★追加: Reactアプリが接続するためのクライアント設定
# ================================================================================
resource "aws_cognito_user_pool_client" "client" {
  provider = aws.virginia

  name = "${var.project_name}-client"

  user_pool_id = aws_cognito_user_pool.main_pool.id

  # フロントエンド(React)からのアクセスには「クライアントシークレット」は不要(false)
  generate_secret = false

  # Reactアプリ(Amplify)が必要とする認証フローを許可
  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",       # セキュアなパスワード認証 (推奨)
    "ALLOW_REFRESH_TOKEN_AUTH",  # ログイン維持
    "ALLOW_USER_PASSWORD_AUTH"   # 通常のパスワード認証
  ]

  # トークンの有効期限設定（必要に応じて調整）
  refresh_token_validity = 30
  access_token_validity  = 1
  id_token_validity      = 1

  token_validity_units {
    refresh_token = "days"
    access_token  = "hours"
    id_token      = "hours"
  }
}