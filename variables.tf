variable "aws_access_key" {
  description = "AWS Access Key"
  type        = string
  sensitive   = true
}

variable "aws_secret_key" {
  description = "AWS Secret"
  type        = string
  sensitive   = true
}

variable "aws_account_id" {
  description = "AWS Account ID"
  type        = string
  sensitive   = true
}

variable "telegram_token" {
  description = "Telegram token"
  type        = string
  sensitive   = true
}

variable "telegram_chat_id" {
  description = "Telegram chat ID"
  type        = string
  sensitive   = true
}
