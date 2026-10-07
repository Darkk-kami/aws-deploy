module "app_repo" {
  source          = "../modules/ecr"
  repository_name = var.repository_name
  force_destroy   = var.ecr_force_destroy
  tags            = var.tags
}

module "app_network" {
  source           = "../modules/vpc"
  vpc_cidr         = var.vpc_cidr
  lb_subnet_cidrs  = var.public_subnet_cidrs
  app_subnet_cidrs = var.app_private_subnet_cidrs
  tags             = var.tags
}

module "app_monitoring" {
  source           = "../modules/cloudwatch"
  cluster_name     = module.app_service.ecs_cluster_name
  app_service_name = module.app_service.ecs_service_name
  tags             = var.tags
}

module "app_service" {
  source                         = "../modules/ecs"
  vpc_id                         = module.app_network.vpc_id
  vpc_endpoints_sg_id            = module.app_network.vpc_endpoint_security_group_id
  cpu_arch                       = "X86_64"
  app_service_port               = var.app_service_port
  app_service_env_vars           = var.app_service_env_vars
  app_service_ecr_repository_url = module.app_repo.repository_url
  app_service_ecr_repository_arn = module.app_repo.repository_arn
  app_service_image_tag          = var.app_service_image_tag
  app_service_container_name     = var.app_service_container_name
  app_service_target_group_arn   = module.app_lb.app_service_target_group_arn
  app_subnet_ids                 = module.app_network.private_subnet_ids
  lb_security_group_id           = module.app_lb.lb_security_group_id
  log_retention_days             = var.log_retention_days
  tags                           = var.tags
}

module "app_lb" {
  source                     = "../modules/alb"
  vpc_id                     = module.app_network.vpc_id
  lb_subnet_ids              = module.app_network.public_subnet_ids
  app_service_port           = var.app_service_port
  domain_name                = var.domain_name
  enable_deletion_protection = var.lb_enable_deletion_protection
  tags                       = var.tags
}