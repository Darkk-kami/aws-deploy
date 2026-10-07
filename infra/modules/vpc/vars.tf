variable "vpc_cidr" {
  description = "CIDR block for the VPC (RFC1918, /16 to /28)."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid CIDR block, e.g. 10.10.0.0/16."
  }

  validation {
    condition     = can(regex("^(10\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.|192\\.168\\.)", var.vpc_cidr))
    error_message = "vpc_cidr must be RFC1918 (10.0.0.0/8, 172.16.0.0/12 or 192.168.0.0/16)."
  }

  validation {
    condition = (
      can(cidrhost(var.vpc_cidr, 0)) &&
      tonumber(split("/", var.vpc_cidr)[1]) >= 16 &&
      tonumber(split("/", var.vpc_cidr)[1]) <= 28
    )
    error_message = "vpc_cidr prefix length must be between /16 and /28."
  }
}

variable "desired_azs" {
  description = "Number of Availability Zones to spread subnets across (capped at what the region offers)."
  type        = number
  default     = 2

  validation {
    condition     = var.desired_azs >= 1 && var.desired_azs <= 6
    error_message = "desired_azs must be between 1 and 6."
  }
}

variable "enable_igw" {
  description = "Create an Internet Gateway and a default route for the public subnets."
  type        = bool
  default     = true
}

variable "lb_subnet_cidrs" {
  description = "CIDRs for public subnets (load balancers). One subnet is created per entry; use /27 or larger for an ALB. Assigned to AZs round-robin."
  type        = list(string)

  validation {
    condition     = alltrue([for c in var.lb_subnet_cidrs : can(cidrhost(c, 0))])
    error_message = "Every entry in lb_subnet_cidrs must be a valid CIDR block."
  }
}

variable "app_subnet_cidrs" {
  description = "CIDRs for private app subnets. One subnet is created per entry, assigned to AZs round-robin."
  type        = list(string)
  default     = ["10.10.10.0/24", "10.10.20.0/24"]

  validation {
    condition     = alltrue([for c in var.app_subnet_cidrs : can(cidrhost(c, 0))])
    error_message = "Every entry in app_subnet_cidrs must be a valid CIDR block."
  }
}

variable "enabled_vpc_endpoints" {
  description = "List of VPC endpoints to enable."
  type        = list(string)
  default     = ["ecr.api", "ecr.dkr", "s3", "logs"]
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