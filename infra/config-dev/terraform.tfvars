vpc_cidr                 = "10.10.0.0/16"
public_subnet_cidrs      = ["10.10.0.0/27", "10.10.0.32/27"]
app_private_subnet_cidrs = ["10.10.10.0/24", "10.10.20.0/24"]
repository_name          = "aws-deploy"
domain_name              = "<add-your-domain>"
app_service_image_tag    = "<app-version>"
app_service_port         = 8000

app_service_env_vars = {
  "APP_ENV" = "dev"
}

log_retention_days         = 1
app_service_container_name = "aws-deploy"

lb_enable_deletion_protection = false
ecr_force_destroy             = false

tags = {
  Tier        = "dev"
  ProductName = "aws-deploy"
}