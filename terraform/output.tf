output "kuma_public_ip_instructions" {
  value = "Obtén la IP con el comando de AWS CLI y entra a http://IP:3001"
}

output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}