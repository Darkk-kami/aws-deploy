resource "aws_security_group" "app" {
  name_prefix = "${local.name_prefix}-app-sg-"
  description = "App tasks: accept traffic from the ALB only"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-app-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Inbound: app port from the ALB only
resource "aws_vpc_security_group_ingress_rule" "app_from_lb" {
  security_group_id            = aws_security_group.app.id
  description                  = "App port from the ALB"
  referenced_security_group_id = var.lb_security_group_id
  from_port                    = var.app_service_port
  to_port                      = var.app_service_port
  ip_protocol                  = "tcp"
}

# Outbound: ALB port to the app tasks
resource "aws_vpc_security_group_egress_rule" "lb_to_app" {
  security_group_id            = var.lb_security_group_id
  description                  = "ALB to app tasks"
  referenced_security_group_id = aws_security_group.app.id
  from_port                    = var.app_service_port
  to_port                      = var.app_service_port
  ip_protocol                  = "tcp"
}

# Outbound: interface endpoints (ECR API, ECR DKR, CloudWatch Logs)
resource "aws_vpc_security_group_egress_rule" "app_to_endpoints" {
  security_group_id            = aws_security_group.app.id
  description                  = "HTTPS to VPC interface endpoints"
  referenced_security_group_id = var.vpc_endpoints_sg_id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

# Outbound: S3 gateway endpoint (ECR stores image layers in S3)
resource "aws_vpc_security_group_egress_rule" "app_to_s3" {
  security_group_id = aws_security_group.app.id
  description       = "HTTPS to S3 via the gateway endpoint"
  prefix_list_id    = data.aws_prefix_list.s3.id
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}