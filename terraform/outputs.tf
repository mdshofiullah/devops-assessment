
output "ecr_repository_url" {
  description = "Application ECR repository URL."
  value       = aws_ecr_repository.app.repository_url
}

output "security_group_id" {
  description = "Application security group ID."
  value       = aws_security_group.app.id
}

output "cloudwatch_log_group" {
  description = "Application CloudWatch log group."
  value       = aws_cloudwatch_log_group.app.name
}

output "ec2_instance_id" {
  description = "EC2 instance ID, when enabled."
  value       = try(aws_instance.app[0].id, null)
}

output "application_url" {
  description = "Application URL, when EC2 is enabled."
  value       = try("http://${aws_instance.app[0].public_ip}:${var.app_port}", null)
}
