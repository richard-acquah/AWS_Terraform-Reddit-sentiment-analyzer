# terraform/variables.tf
# Variable definitions for Reddit Sentiment Analyzer

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "reddit-sentiment-analyzer"
}

variable "s3_bucket_prefix" {
  description = "Prefix for S3 bucket name (will be made unique with random suffix)"
  type        = string
  default     = "reddit-sentiment-data"
}

# Reddit API Configuration
variable "reddit_client_id" {
  description = "Reddit API client ID"
  type        = string
  sensitive   = true
}

variable "reddit_client_secret" {
  description = "Reddit API client secret"
  type        = string
  sensitive   = true
}

variable "reddit_user_agent" {
  description = "Reddit API user agent"
  type        = string
  default     = "reddit-sentiment-analyzer/1.0"
}

# Lambda Configuration
variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 14
  
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

# Scheduling Configuration
variable "ingestion_schedule" {
  description = "Schedule expression for Reddit ingestion (EventBridge format)"
  type        = string
  default     = "rate(1 hour)"
  
  validation {
    condition     = can(regex("^(rate\\(\\d+\\s+(minute|minutes|hour|hours|day|days)\\)|cron\\(.+\\))$", var.ingestion_schedule))
    error_message = "Schedule must be a valid EventBridge schedule expression."
  }
}

variable "enable_scheduled_ingestion" {
  description = "Whether to enable scheduled ingestion"
  type        = bool
  default     = true
}

# API Gateway Configuration
variable "create_api_gateway" {
  description = "Whether to create API Gateway for the API Lambda"
  type        = bool
  default     = true
}

# Monitoring Configuration
variable "enable_detailed_monitoring" {
  description = "Enable detailed monitoring for Lambda functions"
  type        = bool
  default     = false
}

# Reddit Configuration
variable "default_subreddits" {
  description = "Default subreddits to monitor"
  type        = list(string)
  default     = ["technology", "news", "worldnews", "politics"]
}

variable "posts_per_subreddit" {
  description = "Number of posts to fetch per subreddit"
  type        = number
  default     = 25
  
  validation {
    condition     = var.posts_per_subreddit > 0 && var.posts_per_subreddit <= 100
    error_message = "Posts per subreddit must be between 1 and 100."
  }
}

# DynamoDB Configuration
variable "dynamodb_point_in_time_recovery" {
  description = "Enable point-in-time recovery for DynamoDB table"
  type        = bool
  default     = false
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}