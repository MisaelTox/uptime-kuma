variable "region" {
  description = "AWS region where resources will be deployed"
  type        = string
  default     = "eu-north-1"
}

variable "user_email" {
  description = "Email address to receive CloudWatch alerts"
  type        = string
  default     = "your-email@example.com"
}