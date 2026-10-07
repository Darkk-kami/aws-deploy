resource "aws_security_group" "lb_sg" {
  name_prefix = "${local.name_prefix}-lb-sg-"
  description = "Allow External traffic from Internet to ALB"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from Internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-lb-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}