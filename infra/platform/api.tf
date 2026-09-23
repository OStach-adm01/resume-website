resource "aws_dynamodb_table" "recruiters" {
  name         = "${local.name}-recruiters"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "requestId"
  attribute {
    name = "requestId"
    type = "S"
  }
  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }
  server_side_encryption { enabled = true }
}
resource "aws_iam_role" "lambda" {
  name                 = "${local.name}-lambda"
  path                 = "/${local.name}/"
  permissions_boundary = var.runtime_boundary_arn
  assume_role_policy   = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }] })
}
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.name}-recruiter"
  retention_in_days = 7
}
resource "aws_iam_role_policy" "lambda" {
  role = aws_iam_role.lambda.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = "dynamodb:PutItem", Resource = aws_dynamodb_table.recruiters.arn },
    { Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"], Resource = "${aws_cloudwatch_log_group.lambda.arn}:*" }
  ] })
}
data "archive_file" "lambda" {
  type             = "zip"
  output_file_mode = "0644"
  source {
    content  = file("${path.module}/../../backend/recruiter/handler.py")
    filename = "handler.py"
  }
  output_path = "${path.module}/.terraform/recruiter.zip"
}
resource "aws_lambda_function" "recruiter" {
  function_name                  = "${local.name}-recruiter"
  role                           = aws_iam_role.lambda.arn
  handler                        = "handler.handler"
  runtime                        = "python3.12"
  architectures                  = ["arm64"]
  filename                       = data.archive_file.lambda.output_path
  source_code_hash               = data.archive_file.lambda.output_base64sha256
  timeout                        = 5
  memory_size                    = 128
  reserved_concurrent_executions = var.lambda_concurrency
  environment { variables = { TABLE_NAME = aws_dynamodb_table.recruiters.name } }
  depends_on = [aws_iam_role_policy.lambda, aws_cloudwatch_log_group.lambda]
}
resource "aws_api_gateway_rest_api" "recruiter" {
  name = local.name
  endpoint_configuration { types = ["REGIONAL"] }
}
resource "aws_api_gateway_resource" "api" {
  rest_api_id = aws_api_gateway_rest_api.recruiter.id
  parent_id   = aws_api_gateway_rest_api.recruiter.root_resource_id
  path_part   = "api"
}
resource "aws_api_gateway_resource" "recruiter" {
  rest_api_id = aws_api_gateway_rest_api.recruiter.id
  parent_id   = aws_api_gateway_resource.api.id
  path_part   = "recruiter-interest"
}
resource "aws_api_gateway_model" "request" {
  rest_api_id  = aws_api_gateway_rest_api.recruiter.id
  name         = "RecruiterRequest"
  content_type = "application/json"
  schema       = jsonencode({ "$schema" = "http://json-schema.org/draft-04/schema#", type = "object", additionalProperties = false, required = ["recruiter", "companyName"], properties = { recruiter = { type = "boolean", enum = [true] }, companyName = { type = "string", minLength = 2, maxLength = 120, pattern = "\\S" } } })
}
resource "aws_api_gateway_request_validator" "request" {
  name                        = "validate-body-and-idempotency-key"
  rest_api_id                 = aws_api_gateway_rest_api.recruiter.id
  validate_request_body       = true
  validate_request_parameters = true
}
resource "aws_api_gateway_method" "post" {
  rest_api_id          = aws_api_gateway_rest_api.recruiter.id
  resource_id          = aws_api_gateway_resource.recruiter.id
  http_method          = "POST"
  authorization        = "NONE"
  request_validator_id = aws_api_gateway_request_validator.request.id
  request_models       = { "$default" = aws_api_gateway_model.request.name }
  request_parameters   = { "method.request.header.Idempotency-Key" = true }
}
resource "aws_api_gateway_integration" "lambda" {
  rest_api_id             = aws_api_gateway_rest_api.recruiter.id
  resource_id             = aws_api_gateway_resource.recruiter.id
  http_method             = aws_api_gateway_method.post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.recruiter.invoke_arn
}
resource "aws_lambda_permission" "api" {
  statement_id  = "AllowOnlyRecruiterRoute"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.recruiter.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.recruiter.execution_arn}/*/POST/api/recruiter-interest"
}
resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.recruiter.id
  # Hash only configured API behavior, not provider-populated IDs or empty defaults.
  triggers = { redeployment = sha1(jsonencode({
    schema = aws_api_gateway_model.request.schema
    method = {
      path                = "/api/recruiter-interest"
      http_method         = aws_api_gateway_method.post.http_method
      authorization       = aws_api_gateway_method.post.authorization
      request_models      = aws_api_gateway_method.post.request_models
      request_parameters  = aws_api_gateway_method.post.request_parameters
      validate_body       = aws_api_gateway_request_validator.request.validate_request_body
      validate_parameters = aws_api_gateway_request_validator.request.validate_request_parameters
    }
    integration = {
      http_method = aws_api_gateway_integration.lambda.integration_http_method
      type        = aws_api_gateway_integration.lambda.type
      uri         = aws_api_gateway_integration.lambda.uri
    }
  })) }
  lifecycle { create_before_destroy = true }
}
resource "aws_api_gateway_stage" "prod" {
  rest_api_id   = aws_api_gateway_rest_api.recruiter.id
  deployment_id = aws_api_gateway_deployment.main.id
  stage_name    = "prod"
}
resource "aws_api_gateway_method_settings" "post" {
  rest_api_id = aws_api_gateway_rest_api.recruiter.id
  stage_name  = aws_api_gateway_stage.prod.stage_name
  method_path = "*/*"
  settings {
    throttling_burst_limit = 5
    throttling_rate_limit  = 1
    metrics_enabled        = true
    data_trace_enabled     = false
    logging_level          = "OFF"
  }
}
