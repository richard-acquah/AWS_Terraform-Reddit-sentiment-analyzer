# terraform/main.tf
# Main Terraform configuration for Reddit Sentiment Analyzer

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "Reddit Sentiment Analyzer"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# Data source for current AWS caller identity
data "aws_caller_identity" "current" {}

# Data source for current AWS region
data "aws_region" "current" {}

# Random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# S3 bucket for Reddit data storage
resource "aws_s3_bucket" "reddit_data" {
  bucket = "${var.s3_bucket_prefix}-${random_string.suffix.result}"
}

resource "aws_s3_bucket_versioning" "reddit_data_versioning" {
  bucket = aws_s3_bucket.reddit_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "reddit_data_encryption" {
  bucket = aws_s3_bucket.reddit_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "reddit_data_pab" {
  bucket = aws_s3_bucket.reddit_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB table for storing processed data and metadata
resource "aws_dynamodb_table" "reddit_posts" {
  name           = "${var.project_name}-posts-${var.environment}"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "post_id"
  range_key      = "timestamp"

  attribute {
    name = "post_id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "N"
  }

  attribute {
    name = "subreddit"
    type = "S"
  }

  global_secondary_index {
    name     = "SubredditIndex"
    hash_key = "subreddit"
    range_key = "timestamp"
    projection_type = "ALL"

  }

  tags = {
    Name = "${var.project_name}-posts-${var.environment}"
  }
}

# IAM role for Lambda functions
resource "aws_iam_role" "lambda_execution_role" {
  name = "${var.project_name}-lambda-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM policy for Lambda functions
resource "aws_iam_policy" "lambda_policy" {
  name = "${var.project_name}-lambda-policy-${var.environment}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.reddit_data.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.reddit_data.arn
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.reddit_posts.arn,
          "${aws_dynamodb_table.reddit_posts.arn}/*"
        ]
      }
    ]
  })
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# Create ZIP files for Lambda functions
data "archive_file" "ingest_lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda-functions/ingest"
  output_path = "${path.module}/lambda_packages/ingest.zip"
}

data "archive_file" "process_lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda-functions/process"
  output_path = "${path.module}/lambda_packages/process.zip"
}

data "archive_file" "api_lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda-functions/api"
  output_path = "${path.module}/lambda_packages/api.zip"
}

# Lambda function for Reddit ingestion
resource "aws_lambda_function" "reddit_ingest" {
  filename         = data.archive_file.ingest_lambda_zip.output_path
  function_name    = "${var.project_name}-ingest-${var.environment}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "main.lambda_handler"
  runtime         = "python3.11"
  timeout         = 300
  memory_size     = 512

  source_code_hash = data.archive_file.ingest_lambda_zip.output_base64sha256

  environment {
    variables = {
      REDDIT_CLIENT_ID     = var.reddit_client_id
      REDDIT_CLIENT_SECRET = var.reddit_client_secret
      REDDIT_USER_AGENT    = var.reddit_user_agent
      S3_BUCKET_NAME       = aws_s3_bucket.reddit_data.bucket
      DYNAMODB_TABLE_NAME  = aws_dynamodb_table.reddit_posts.name
      ENVIRONMENT          = var.environment
    }
  }
}

# Lambda function for data processing
resource "aws_lambda_function" "reddit_process" {
  filename         = data.archive_file.process_lambda_zip.output_path
  function_name    = "${var.project_name}-process-${var.environment}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "main.lambda_handler"
  runtime         = "python3.11"
  timeout         = 900
  memory_size     = 1024

  source_code_hash = data.archive_file.process_lambda_zip.output_base64sha256

  environment {
    variables = {
      S3_BUCKET_NAME      = aws_s3_bucket.reddit_data.bucket
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.reddit_posts.name
      ENVIRONMENT         = var.environment
    }
  }
}

# Lambda function for API
resource "aws_lambda_function" "reddit_api" {
  filename         = data.archive_file.api_lambda_zip.output_path
  function_name    = "${var.project_name}-api-${var.environment}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "main.lambda_handler"
  runtime         = "python3.11"
  timeout         = 30
  memory_size     = 256

  source_code_hash = data.archive_file.api_lambda_zip.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.reddit_posts.name
      ENVIRONMENT         = var.environment
    }
  }
}

# CloudWatch Log Groups for Lambda functions
resource "aws_cloudwatch_log_group" "ingest_lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.reddit_ingest.function_name}"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "process_lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.reddit_process.function_name}"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "api_lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.reddit_api.function_name}"
  retention_in_days = var.log_retention_days
}

# EventBridge rule to trigger ingestion Lambda on schedule
resource "aws_cloudwatch_event_rule" "reddit_ingestion_schedule" {
  name        = "${var.project_name}-ingestion-schedule-${var.environment}"
  description = "Trigger Reddit ingestion Lambda on schedule"
  
  schedule_expression = var.ingestion_schedule
  state              = var.enable_scheduled_ingestion ? "ENABLED" : "DISABLED"
}

# EventBridge target for ingestion Lambda
resource "aws_cloudwatch_event_target" "ingest_lambda_target" {
  rule      = aws_cloudwatch_event_rule.reddit_ingestion_schedule.name
  target_id = "RedditIngestLambdaTarget"
  arn       = aws_lambda_function.reddit_ingest.arn
}

# Permission for EventBridge to invoke ingestion Lambda
resource "aws_lambda_permission" "allow_eventbridge_ingest" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.reddit_ingest.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.reddit_ingestion_schedule.arn
}

# S3 event notification to trigger processing Lambda
resource "aws_s3_bucket_notification" "reddit_data_notification" {
  bucket = aws_s3_bucket.reddit_data.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.reddit_process.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "raw-data/"
  }

  depends_on = [aws_lambda_permission.allow_s3_process]
}

# Permission for S3 to invoke processing Lambda
resource "aws_lambda_permission" "allow_s3_process" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.reddit_process.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.reddit_data.arn
}

# API Gateway for the API Lambda (optional)
resource "aws_api_gateway_rest_api" "reddit_api" {
  count = var.create_api_gateway ? 1 : 0
  name  = "${var.project_name}-api-${var.environment}"
  
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "reddit_api_resource" {
  count       = var.create_api_gateway ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.reddit_api[0].id
  parent_id   = aws_api_gateway_rest_api.reddit_api[0].root_resource_id
  path_part   = "sentiment"
}

resource "aws_api_gateway_method" "reddit_api_method" {
  count         = var.create_api_gateway ? 1 : 0
  rest_api_id   = aws_api_gateway_rest_api.reddit_api[0].id
  resource_id   = aws_api_gateway_resource.reddit_api_resource[0].id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "reddit_api_integration" {
  count       = var.create_api_gateway ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.reddit_api[0].id
  resource_id = aws_api_gateway_resource.reddit_api_resource[0].id
  http_method = aws_api_gateway_method.reddit_api_method[0].http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.reddit_api.invoke_arn
}

# Fixed API Gateway deployment without deprecated stage_name
resource "aws_api_gateway_deployment" "reddit_api_deployment" {
  count       = var.create_api_gateway ? 1 : 0
  depends_on  = [aws_api_gateway_integration.reddit_api_integration]
  rest_api_id = aws_api_gateway_rest_api.reddit_api[0].id
  
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.reddit_api_resource[0].id,
      aws_api_gateway_method.reddit_api_method[0].id,
      aws_api_gateway_integration.reddit_api_integration[0].id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Separate stage resource
resource "aws_api_gateway_stage" "reddit_api_stage" {
  count         = var.create_api_gateway ? 1 : 0
  deployment_id = aws_api_gateway_deployment.reddit_api_deployment[0].id
  rest_api_id   = aws_api_gateway_rest_api.reddit_api[0].id
  stage_name    = var.environment
  
  xray_tracing_enabled = true
  
  tags = {
    Environment = var.environment
    Name        = "${var.project_name}-api-stage-${var.environment}"
  }
}

# Updated Lambda permission for API Gateway
resource "aws_lambda_permission" "allow_api_gateway" {
  count         = var.create_api_gateway ? 1 : 0
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.reddit_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.reddit_api[0].execution_arn}/*/*"
}