
resource "aws_cloudwatch_log_group" "app" {
  name              = "/devops-assessment/${var.environment}"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${local.resource_name}-logs"
  }
}
