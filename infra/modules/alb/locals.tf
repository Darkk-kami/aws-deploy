locals {
  name_prefix = "${var.tags.Tier}-${var.tags.ProductName}" # e.g. prod-app

  log_delivery_sources = {
    access_logs      = aws_cloudwatch_log_delivery_source.access_logs.name
    conn_logs        = aws_cloudwatch_log_delivery_source.conn_logs.name
    healthcheck_logs = aws_cloudwatch_log_delivery_source.healthcheck_logs.name
  }
}