# ---------------------------------------------------------
# Authentication (Cognito User Pool)
# ---------------------------------------------------------
resource "aws_cognito_user_pool" "main_pool" {
  provider = aws.virginia
  name     = "SkillLink-Userpool"

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

  lambda_config {
    pre_sign_up = "arn:aws:lambda:us-east-1:<YOUR_ACCOUNT_ID>:function:SkillLinkDomainGuard"
  }

  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
  }

  tags = {
    project = "skill-link"
  }
}