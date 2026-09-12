locals {
  name_prefix  = replace(lower(var.project_name), "_", "-")
  cluster_name = substr(local.name_prefix, 0, 32)
}

module "network" {
  source       = "./modules/iac/network"
  project_name = local.name_prefix
  region       = var.region
  ip_range     = var.vpc_ip_range
}

module "k8s" {
  source             = "./modules/iac/k8s"
  cluster_name       = local.cluster_name
  region             = var.region
  kubernetes_version = var.kubernetes_version
  vpc_uuid           = module.network.vpc_id
  node_size          = var.node_size
  node_count         = var.node_count
  ha                 = var.ha

  depends_on = [module.network]
}
