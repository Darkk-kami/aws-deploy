resource "aws_cloudwatch_dashboard" "app_services_dashboard" {
  dashboard_name = "${local.name_prefix}-dashboard"
  dashboard_body = jsonencode(
    {
      "widgets" : [
        {
          "type" : "metric",
          "x" : 0,
          "y" : 0,
          "width" : 6,
          "height" : 6,
          "properties" : {
            "legend" : {
              "position" : "hidden"
            },
            "metrics" : [
              ["AWS/ECS", "CPUUtilization", "ServiceName", var.app_service_name, "ClusterName", var.cluster_name]
            ],
            "region" : data.aws_region.current.region,
            "stacked" : false,
            "title" : "CPUUtilization",
            "view" : "timeSeries"
          }
        },
        {
          "type" : "metric",
          "x" : 6,
          "y" : 0,
          "width" : 6,
          "height" : 6,
          "properties" : {
            "legend" : {
              "position" : "hidden"
            },
            "metrics" : [
              ["AWS/ECS", "MemoryUtilization", "ServiceName", var.app_service_name, "ClusterName", var.cluster_name]
            ],
            "region" : data.aws_region.current.region,
            "stacked" : false,
            "title" : "MemoryUtilization",
            "view" : "timeSeries"
          }
        },
        {
          "type" : "metric",
          "x" : 0,
          "y" : 6,
          "width" : 12,
          "height" : 6,
          "properties" : {
            "legend" : {
              "position" : "hidden"
            },
            "metrics" : [
              ["AWS/ECS", "RunningTaskCount", "ServiceName", var.app_service_name, "ClusterName", var.cluster_name]
            ],
            "region" : data.aws_region.current.region,
            "stat" : "Average",
            "stacked" : false,
            "title" : "Running task count",
            "view" : "timeSeries"
          }
        }
      ]
    }
  )
}