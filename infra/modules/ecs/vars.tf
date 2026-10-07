variable "vpc_id" {
  description = "ID of the VPC the target group and load balancer live in."
  type        = string

  validation {
    condition     = can(regex("^vpc-([0-9a-f]{8}|[0-9a-f]{17})$", var.vpc_id))
    error_message = "vpc_id must be a VPC ID such as \"vpc-0123456789abcdef0\"."
  }
}

variable "vpc_endpoints_sg_id" {
  description = "ID of the security group attached to the VPC interface endpoints (ECR API, ECR DKR, CloudWatch Logs)."
  type        = string

  validation {
    condition     = can(regex("^sg-([0-9a-f]{8}|[0-9a-f]{17})$", var.vpc_endpoints_sg_id))
    error_message = "vpc_endpoints_sg_id must be a security group ID such as \"sg-0123456789abcdef0\"."
  }

}

variable "lb_security_group_id" {
  description = "ID of the security group attached to the ALB."
  type        = string

  validation {
    condition     = can(regex("^sg-([0-9a-f]{8}|[0-9a-f]{17})$", var.lb_security_group_id))
    error_message = "lb_security_group_id must be a security group ID such as \"sg-0123456789abcdef0\"."
  }
}


variable "app_service_ecr_repository_arn" {
  description = "ARN of the ECR repository the execution role may pull from."
  type        = string
}

variable "app_service_ecr_repository_url" {
  description = "URL of the ECR repository the execution role may pull from (not the name)."
  type        = string
}

variable "app_service_container_name" {
  description = "Name of the container in the task definition. Also used as the log stream prefix and the load balancer target."
  type        = string
  default     = "app"

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]{1,255}$", var.app_service_container_name))
    error_message = "app_service_container_name must be 1-255 characters of letters, digits, hyphens and underscores."
  }
}

variable "app_service_image_tag" {
  description = "Tag for the Docker image to deploy."
  type        = string
}

variable "app_service_port" {
  description = "Port the app listens on inside the container."
  type        = number
  default     = 8000

  validation {
    condition     = var.app_service_port >= 1 && var.app_service_port <= 65535 && floor(var.app_service_port) == var.app_service_port
    error_message = "app_service_port must be a whole number between 1 and 65535."
  }
}

variable "app_service_env_vars" {
  description = "Plain-text environment variables for the container. Do not put secrets here; use ECS secrets backed by Secrets Manager or SSM."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for k in keys(var.app_service_env_vars) : can(regex("^[A-Za-z_][A-Za-z0-9_]*$", k))])
    error_message = "Environment variable names must start with a letter or underscore and contain only letters, digits and underscores."
  }
}

variable "cpu" {
  description = "Fargate task CPU units (1024 = 1 vCPU)."
  type        = number
  default     = 256

  validation {
    condition     = contains([256], var.cpu)
    error_message = "cpu must be one of 256, 512, 1024, 2048, 4096, 8192 or 16384."
  }
}

variable "memory" {
  description = "Fargate task memory in MiB. Must be a valid pairing for the chosen cpu."
  type        = number
  default     = 512

  validation {
    condition = contains(lookup({
      256 = [512, 1024, 2048]
    }, var.cpu, []), var.memory)
    error_message = "memory is not a valid Fargate pairing for the chosen cpu (e.g. cpu 256 allows 512, 1024 or 2048)."
  }
}

variable "cpu_arch" {
  description = "CPU architecture for the task. Must match the architecture the image was built for."
  type        = string
  default     = "ARM64"

  validation {
    condition     = contains(["X86_64", "ARM64"], var.cpu_arch)
    error_message = "cpu_arch must be either \"X86_64\" or \"ARM64\"."
  }
}

variable "desired_count" {
  description = "Initial number of running tasks. Ignored after creation (see ignore_changes), so autoscaling controls it afterwards."
  type        = number
  default     = 1

  validation {
    condition     = var.desired_count >= 0 && floor(var.desired_count) == var.desired_count
    error_message = "desired_count must be a whole number of 0 or more."
  }
}

variable "app_subnet_ids" {
  description = "IDs of the private subnets the tasks run in. Use at least two, in different Availability Zones, for resilience."
  type        = list(string)

  validation {
    condition     = length(var.app_subnet_ids) >= 2
    error_message = "app_subnet_ids must contain at least two subnet IDs."
  }

  validation {
    condition     = alltrue([for s in var.app_subnet_ids : can(regex("^subnet-([0-9a-f]{8}|[0-9a-f]{17})$", s))])
    error_message = "Every entry in app_subnet_ids must be a subnet ID such as \"subnet-0123456789abcdef0\"."
  }
}

variable "app_service_target_group_arn" {
  description = "ARN of the ALB target group the service registers its tasks with."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:elasticloadbalancing:[a-z0-9-]+:[0-9]{12}:targetgroup/[A-Za-z0-9-]+/[0-9a-f]{16}$", var.app_service_target_group_arn))
    error_message = "app_service_target_group_arn must be a target group ARN."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain log events."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Common tags applied to every resource. Must include Tier and ProductName; add any others you like."
  type        = map(string)

  validation {
    condition     = alltrue([for k in ["Tier", "ProductName"] : contains(keys(var.tags), k)])
    error_message = "tags must include the keys \"Tier\" and \"ProductName\"."
  }

  validation {
    condition = alltrue([
      for k in ["Tier", "ProductName"] : can(regex("^[a-z0-9-]+$", lookup(var.tags, k, "")))
    ])
    error_message = "Tier and ProductName must be lowercase letters, digits and hyphens only (they are used in resource names)."
  }
}