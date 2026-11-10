
resource "aws_iam_role" "app" {
  name = "${local.resource_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "ec2.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "app" {
  name = "${local.resource_name}-profile"
  role = aws_iam_role.app.name
}

# Allows secure EC2 management using Systems Manager.
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Custom policy for ECR image pulling and CloudWatch logging.
resource "aws_iam_role_policy" "app" {
  name = "${local.resource_name}-policy"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "ECRAuthorization"
        Effect = "Allow"

        Action = [
          "ecr:GetAuthorizationToken"
        ]

        Resource = "*"
      },
      {
        Sid      = "PullApplicationImage"
        Effect   = "Allow"
        Action   = local.ecr_pull_actions
        Resource = aws_ecr_repository.app.arn
      },
      {
        Sid    = "WriteApplicationLogs"
        Effect = "Allow"

        Action   = local.log_write_actions
        Resource = "${aws_cloudwatch_log_group.app.arn}:*"
      }
    ]
  })
}
