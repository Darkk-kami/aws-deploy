resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-ecs-cluster"

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-ecs-cluster"
  })
}

resource "aws_ecs_task_definition" "app_service" {
  family                   = "${local.name_prefix}-ecs-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = tostring(var.cpu)
  memory                   = tostring(var.memory)
  execution_role_arn       = aws_iam_role.app_service_execution_role.arn

  runtime_platform {
    cpu_architecture        = var.cpu_arch
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([
    {
      name                   = var.app_service_container_name
      image                  = "${var.app_service_ecr_repository_url}:${var.app_service_image_tag}"
      essential              = true
      readonlyRootFilesystem = true
      privileged             = false
      user                   = "10001:10001"

      linuxParameters = {
        capabilities = {
          add  = []
          drop = ["ALL"]
        }

        tmpfs = [
          {
            containerPath = "/tmp"
            size          = 64
            mountOptions  = ["nosuid", "noexec", "nodev", "rw", "mode=1777"]
          }
        ]
      }

      portMappings = [
        {
          containerPort = var.app_service_port
          hostPort      = var.app_service_port
          protocol      = "tcp"
        }
      ]

      environment = [
        for key, value in var.app_service_env_vars : {
          name  = key
          value = value
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/aws/ecs/${local.name_prefix}-ecs-service"
          awslogs-region        = data.aws_region.current.region
          awslogs-stream-prefix = var.app_service_container_name
        }
      }
    }
  ])

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-ecs-task"
  })
}

resource "aws_ecs_service" "app_service" {
  name                               = "${local.name_prefix}-ecs-service"
  cluster                            = aws_ecs_cluster.main.id
  task_definition                    = aws_ecs_task_definition.app_service.arn
  desired_count                      = var.desired_count
  launch_type                        = "FARGATE"
  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = var.app_subnet_ids
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.app_service_target_group_arn
    container_name   = var.app_service_container_name
    container_port   = var.app_service_port
  }

  lifecycle {
    ignore_changes = [desired_count] #Ignore changes due to application auto-scaling
  }

  force_new_deployment = true
}

resource "aws_cloudwatch_log_group" "app_service_log_group" {
  name              = "/aws/ecs/${local.name_prefix}-ecs-service"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}
