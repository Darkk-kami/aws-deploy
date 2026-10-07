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

variable "repository_name" {
  description = "Name of the ECR repository. Lowercase letters, digits and . _ - separators, with optional / namespaces."
  type        = string

  validation {
    condition     = can(regex("^(?:[a-z0-9]+(?:[._-][a-z0-9]+)*/)*[a-z0-9]+(?:[._-][a-z0-9]+)*$", var.repository_name))
    error_message = "repository_name must be lowercase, and may use . _ - as separators and / for namespaces (e.g. \"myteam/api\")."
  }
}

variable "encryption_type" {
  description = "Encryption for images at rest: AES256 (AWS-managed, free) or KMS."
  type        = string
  default     = "AES256"

  validation {
    condition     = contains(["AES256", "KMS"], var.encryption_type)
    error_message = "encryption_type must be either \"AES256\" or \"KMS\"."
  }
}

variable "image_retention_count" {
  description = "Number of most recent images to keep; older ones are expired by the lifecycle policy."
  type        = number
  default     = 3

  validation {
    condition     = var.image_retention_count >= 1 && floor(var.image_retention_count) == var.image_retention_count
    error_message = "image_retention_count must be a whole number of at least 1."
  }
}

variable "force_destroy" {
  description = "If true, the repository will be deleted even if it contains images. Use with caution."
  type        = bool
  default     = false
}