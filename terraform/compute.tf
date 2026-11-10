
resource "aws_instance" "app" {
  count = var.enable_ec2_instance ? 1 : 0

  ami           = var.ami_id
  instance_type = var.instance_type

  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.app.id]

  associate_public_ip_address = true

  iam_instance_profile = aws_iam_instance_profile.app.name

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    aws_region     = var.aws_region
    ecr_registry   = split("/", aws_ecr_repository.app.repository_url)[0]
    image_uri      = local.image_uri
    log_group_name = aws_cloudwatch_log_group.app.name
    container_name = local.resource_name
    app_port       = var.app_port
    app_version    = var.app_version
  })

  user_data_replace_on_change = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    encrypted             = true
    volume_size           = var.root_volume_size_gb
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = local.resource_name
  }

  depends_on = [
    aws_iam_role_policy.app,
    aws_iam_role_policy_attachment.ssm
  ]
}
