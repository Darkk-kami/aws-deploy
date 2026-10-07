resource "aws_lb" "main" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb_sg.id]
  subnets            = var.lb_subnet_ids

  drop_invalid_header_fields = var.drop_invalid_header_fields
  enable_deletion_protection = var.enable_deletion_protection

}

resource "aws_lb_target_group" "app_service" {
  name        = "${local.name_prefix}-tg-app-service"
  port        = var.app_service_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  health_check {
    enabled             = true
    protocol            = "HTTP"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    matcher             = "200-399"
    interval            = 30
    path                = "/health"
    timeout             = 10
  }
}


resource "aws_lb_listener" "app_service" {
  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = var.elb_ssl_policy
  certificate_arn   = data.aws_acm_certificate.issued.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_service.arn
  }
}

# Redirect www to non-www
resource "aws_lb_listener_rule" "www_redirect" {
  listener_arn = aws_lb_listener.app_service.arn
  priority     = 50

  action {
    type = "redirect"

    redirect {
      host        = var.domain_name
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  condition {
    host_header {
      values = ["www.${var.domain_name}"]
    }
  }
}

resource "aws_cloudwatch_log_group" "lb_log_group" {
  name              = "/aws/lb/${local.name_prefix}-lb"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_cloudwatch_log_delivery_source" "access_logs" {
  name         = "${local.name_prefix}-lb-access-logs"
  log_type     = "ALB_ACCESS_LOGS"
  resource_arn = aws_lb.main.arn
}

resource "aws_cloudwatch_log_delivery_source" "conn_logs" {
  name         = "${local.name_prefix}-lb-conn-logs"
  log_type     = "ALB_CONNECTION_LOGS"
  resource_arn = aws_lb.main.arn
}

resource "aws_cloudwatch_log_delivery_source" "healthcheck_logs" {
  name         = "${local.name_prefix}-lb-healthcheck-logs"
  log_type     = "ALB_HEALTH_CHECK_LOGS"
  resource_arn = aws_lb.main.arn
}

# delivery destination for the ALB logs
resource "aws_cloudwatch_log_delivery_destination" "logs" {
  for_each = {
    access_logs      = "ALB_ACCESS_LOGS"
    conn_logs        = "ALB_CONNECTION_LOGS"
    healthcheck_logs = "ALB_HEALTH_CHECK_LOGS"
  }

  name          = "${local.name_prefix}-lb-${each.key}"
  output_format = "json"

  delivery_destination_configuration {
    destination_resource_arn = aws_cloudwatch_log_group.lb_log_group.arn
  }
}

resource "aws_cloudwatch_log_resource_policy" "alb_logs" {
  resource_arn = aws_cloudwatch_log_group.lb_log_group.arn
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "delivery.logs.amazonaws.com"
      }
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "${aws_cloudwatch_log_group.lb_log_group.arn}:*"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
        ArnLike = {
          "aws:SourceArn" = "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:delivery-source:*"
        }
      }
    }]
  })
}

resource "aws_cloudwatch_log_delivery" "logs" {
  for_each = aws_cloudwatch_log_delivery_destination.logs

  delivery_source_name     = local.log_delivery_sources[each.key]
  delivery_destination_arn = each.value.arn

  depends_on = [aws_cloudwatch_log_resource_policy.alb_logs]
}