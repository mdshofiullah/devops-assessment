
locals {
  resource_name = "${var.project_name}-${var.environment}"

  ecr_pull_actions = [
    "ecr:BatchCheckLayerAvailability",
    "ecr:BatchGetImage",
    "ecr:GetDownloadUrlForLayer"
  ]

  log_write_actions = [
    "logs:CreateLogStream",
    "logs:PutLogEvents"
  ]

  image_uri = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"
}
