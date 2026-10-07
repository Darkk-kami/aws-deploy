variable "vpc_id" {
  description = "ID of the VPC the target group and load balancer live in."
  type        = string

  validation {
    condition     = can(regex("^vpc-([0-9a-f]{8}|[0-9a-f]{17})$", var.vpc_id))
    error_message = "vpc_id must be a VPC ID such as \"vpc-0123456789abcdef0\"."
  }
}

variable "lb_subnet_ids" {
  description = "IDs of the public subnets the ALB is placed in. Must be in at least two Availability Zones; each should be /27 or larger."
  type        = list(string)

  validation {
    condition     = length(distinct(var.lb_subnet_ids)) >= 2
    error_message = "lb_subnet_ids must contain at least two distinct subnet IDs (an ALB needs two Availability Zones)."
  }

  validation {
    condition     = alltrue([for s in var.lb_subnet_ids : can(regex("^subnet-([0-9a-f]{8}|[0-9a-f]{17})$", s))])
    error_message = "Every entry in lb_subnet_ids must be a subnet ID such as \"subnet-0123456789abcdef0\"."
  }
}

variable "app_service_port" {
  description = "Port the app listens on; the target group forwards to this port."
  type        = number
  default     = 8000

  validation {
    condition     = var.app_service_port >= 1 && var.app_service_port <= 65535 && floor(var.app_service_port) == var.app_service_port
    error_message = "app_service_port must be a whole number between 1 and 65535."
  }
}

variable "elb_ssl_policy" {
  description = "TLS security policy for the HTTPS listener. The default allows TLS 1.3 with a TLS 1.2 fallback."
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  validation {
    condition     = can(regex("^ELBSecurityPolicy-", var.elb_ssl_policy))
    error_message = "elb_ssl_policy must be an AWS-provided policy name starting with \"ELBSecurityPolicy-\"."
  }
}

variable "drop_invalid_header_fields" {
  description = "Drop requests with invalid HTTP headers instead of forwarding them to the app. AWS defaults to false; true is the safer setting."
  type        = bool
  default     = true
}

variable "enable_deletion_protection" {
  description = "Block deletion of the ALB. Set to false in dev, otherwise terraform destroy will fail."
  type        = bool
}

variable "domain_name" {
  description = "Domain name for the ACM certificate, e.g. \"api.example.com\" or a wildcard like \"*.example.com\". Must be lowercase with no trailing dot."
  type        = string

  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$", var.domain_name))
    error_message = "domain_name must be a lowercase fully qualified domain name (no wildcard, no trailing dot), e.g. \"example.com\"."
  }

  validation {
    condition     = length(var.domain_name) <= 64
    error_message = "domain_name must be 64 characters or fewer (ACM limit for the primary domain)."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain log events."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Common tags applied to every resource. Must include Tier and ProductName keys, which are used in resource names."
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