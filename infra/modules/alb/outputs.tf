output "lb_security_group_id" {
  value = aws_security_group.lb_sg.id
}

output "app_service_target_group_arn" {
  value = aws_lb_target_group.app_service.arn
}