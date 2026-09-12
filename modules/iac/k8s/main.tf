# https://github.com/digitalocean/terraform-provider-digitalocean/blob/main/docs/resources/kubernetes_cluster.md
resource "digitalocean_kubernetes_cluster" "this" {
  name    = var.cluster_name
  region  = var.region
  version = var.kubernetes_version
  vpc_uuid = var.vpc_uuid
  ha      = var.ha

  # Tear down LBs/volumes created via K8s API with the cluster (lab).
  destroy_all_associated_resources = true

  node_pool {
    name       = "worker-pool"
    size       = var.node_size
    node_count = var.node_count
  }
}
