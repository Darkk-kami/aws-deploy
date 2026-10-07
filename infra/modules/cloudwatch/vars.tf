variable "app_service_name" {
  description = "Name of the ECS service to monitor."
  type        = string
}

variable "cluster_name" {
  description = "Name of the ECS cluster the service runs in."
  type        = string
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