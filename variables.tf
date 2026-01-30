variable "project_name" {
  description = "Project Name for resource naming"
  default     = "skill-link"
}

variable "region" {
  default = "us-east-1"
}

variable "line_channel_token" {
  description = "LINE Channel Access Token"
  type        = string
  sensitive   = true
}

variable "pinecone_index_url" {
  description = "Pinecone Index URL"
  type        = string
}

variable "pinecone_secret_arn" {
  description = "Secrets Manager ARN for Pinecone Key"
  type        = string
}

variable "aws_account_id" {
  description = "AWS Account ID (12 digits)"
  type        = string
}