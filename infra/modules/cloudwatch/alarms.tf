resource "aws_cloudwatch_metric_alarm" "app_cpu_utilization_high" {
  alarm_name        = "${local.name_prefix}-app-cpu-utilization-high"
  alarm_description = "Average ECS service CPU utilization is above 70% for two consecutive minutes."

  namespace           = "AWS/ECS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 70
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.cluster_name
    ServiceName = var.app_service_name
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "app_memory_utilization_high" {
  alarm_name        = "${local.name_prefix}-app-memory-utilization-high"
  alarm_description = "Average ECS service memory utilization is above 70% for two consecutive minutes."

  namespace           = "AWS/ECS"
  metric_name         = "MemoryUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 70
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.cluster_name
    ServiceName = var.app_service_name
  }

  tags = var.tags
}
