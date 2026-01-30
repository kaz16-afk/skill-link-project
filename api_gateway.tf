resource "aws_apigatewayv2_api" "main" {
  name          = "skill-link-api-${random_id.suffix.hex}"
  protocol_type = "HTTP"
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "OPTIONS"]
    allow_headers = ["content-type", "authorization"]
    max_age       = 300
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "prod"
  auto_deploy = true
}

# --- Presigned URL Integration ---
resource "aws_apigatewayv2_integration" "presigned_integration" {
  api_id           = aws_apigatewayv2_api.main.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.presigned.invoke_arn
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "get_upload_url" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "GET /upload"
  target    = "integrations/${aws_apigatewayv2_integration.presigned_integration.id}"
}

resource "aws_lambda_permission" "api_gw_presigned" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.presigned.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

# --- Webhook Integration ---
resource "aws_apigatewayv2_integration" "webhook_integration" {
  api_id           = aws_apigatewayv2_api.main.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.webhook_handler.invoke_arn
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

output "api_gateway_url" {
  value = aws_apigatewayv2_stage.default.invoke_url
}