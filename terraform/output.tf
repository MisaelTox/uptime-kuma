output "kuma_public_ip_instructions" {
  description = "Instructions to retrieve the public IP of the Uptime Kuma task"
  value       = "Get the task IP with the AWS CLI and access http://IP:3001"
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic used for CloudWatch alerts"
  value       = aws_sns_topic.alerts.arn
}

output "ecr_repository_url" {
  description = "URL of the ECR repository for the Uptime Kuma image"
  value       = aws_ecr_repository.uptime_kuma.repository_url
}