output "vpc_id" {
  value = module.network.vpc_id
}

output "cluster_id" {
  value = module.k8s.cluster_id
}

output "cluster_endpoint" {
  value = module.k8s.endpoint
}

output "kubeconfig" {
  value     = module.k8s.kube_config_raw
  sensitive = true
}
