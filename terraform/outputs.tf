# terraform/outputs.tf
# Output values for Reddit Sentiment Analyzer

# S3 Outputs
output "s3_bucket_name" {
  description = "Name of the S3 bucket for Reddit data"
  value       = aws_s3_bucket.reddit_data.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for Reddit data"
  value       = aws_s3_bucket.reddit_data.arn
}

output "s3_bucket_region" {
  description = "Region of the S3 bucket"
  value       = aws_s3_bucket.reddit_data.region
}

# DynamoDB Outputs
output "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  value       = aws_dynamodb_table.reddit_posts.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table"
  value       = aws_dynamodb_table.reddit_posts.arn
}

# Lambda Function Outputs
output "lambda_ingest_function_name" {
  description = "Name of the ingestion Lambda function"
  value       = aws_lambda_function.reddit_ingest.function_name
}

output "lambda_ingest_function_arn" {
  description = "ARN of the ingestion Lambda function"
  value       = aws_lambda_function.reddit_ingest.arn
}

output "lambda_process_function_name" {
  description = "Name of the processing Lambda function"
  value       = aws_lambda_function.reddit_process.function_name
}

output "lambda_process_function_arn" {
  description = "ARN of the processing Lambda function"
  value       = aws_lambda_function.reddit_process.arn
}

output "lambda_api_function_name" {
  description = "Name of the API Lambda function"
  value       = aws_lambda_function.reddit_api.function_name
}

output "lambda_api_function_arn" {
  description = "ARN of the API Lambda function"
  value       = aws_lambda_function.reddit_api.arn
}

# IAM Outputs
output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "lambda_execution_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.name
}

# CloudWatch Outputs
output "cloudwatch_log_group_ingest" {
  description = "CloudWatch log group for ingestion Lambda"
  value       = aws_cloudwatch_log_group.ingest_lambda_logs.name
}

output "cloudwatch_log_group_process" {
  description = "CloudWatch log group for processing Lambda"
  value       = aws_cloudwatch_log_group.process_lambda_logs.name
}

output "cloudwatch_log_group_api" {
  description = "CloudWatch log group for API Lambda"
  value       = aws_cloudwatch_log_group.api_lambda_logs.name
}

# EventBridge Outputs
output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for scheduled ingestion"
  value       = aws_cloudwatch_event_rule.reddit_ingestion_schedule.name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for scheduled ingestion"
  value       = aws_cloudwatch_event_rule.reddit_ingestion_schedule.arn
}

# API Gateway Outputs (conditional)
output "api_gateway_url" {
  description = "The URL of the API Gateway"
  value       = var.create_api_gateway ? "https://${aws_api_gateway_rest_api.reddit_api[0].id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.environment}/sentiment" : null
}

output "api_gateway_id" {
  description = "ID of the API Gateway"
  value       = var.create_api_gateway ? aws_api_gateway_rest_api.reddit_api[0].id : null
}

output "api_gateway_execution_arn" {
  description = "Execution ARN of the API Gateway"
  value       = var.create_api_gateway ? aws_api_gateway_rest_api.reddit_api[0].execution_arn : null
}

# Environment Information
output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "project_name" {
  description = "Project name"
  value       = var.project_name
}

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}

output "random_suffix" {
  description = "Random suffix used for unique resource names"
  value       = random_string.suffix.result
}

# Deployment Information
output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    environment           = var.environment
    region               = var.aws_region
    s3_bucket           = aws_s3_bucket.reddit_data.bucket
    dynamodb_table      = aws_dynamodb_table.reddit_posts.name
    lambda_functions    = {
      ingest  = aws_lambda_function.reddit_ingest.function_name
      process = aws_lambda_function.reddit_process.function_name
      api     = aws_lambda_function.reddit_api.function_name
    }
    api_gateway_url     = var.create_api_gateway ? aws_api_gateway_deployment.reddit_api_deployment[0].invoke_url : "Not created"
    scheduled_ingestion = var.enable_scheduled_ingestion ? "Enabled" : "Disabled"
  }
}