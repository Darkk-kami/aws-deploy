output "dashboard_name" {
  description = "Name of the ECS service monitoring dashboard."
  value       = aws_cloudwatch_dashboard.app_services_dashboard.dashboard_name
}

output "cpu_alarm_name" {
  description = "Name of the high ECS service CPU utilization alarm."
  value       = aws_cloudwatch_metric_alarm.app_cpu_utilization_high.alarm_name
}

output "memory_alarm_name" {
  description = "Name of the high ECS service memory utilization alarm."
  value       = aws_cloudwatch_metric_alarm.app_memory_utilization_high.alarm_name
}