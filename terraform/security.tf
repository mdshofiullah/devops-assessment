
resource "aws_security_group" "app" {
  name        = "${local.resource_name}-sg"
  description = "Allow application traffic only."
  vpc_id      = var.vpc_id

  ingress {
    description = "Application HTTP access"
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"

    cidr_blocks = var.app_ingress_cidr_blocks
  }

  egress {
    description = "Outbound access for image pulls and AWS services"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"

    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.resource_name}-sg"
  }
}
