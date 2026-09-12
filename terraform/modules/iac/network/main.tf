# https://github.com/digitalocean/terraform-provider-digitalocean/blob/main/docs/resources/vpc.md
resource "digitalocean_vpc" "this" {
  name     = "${var.project_name}-net"
  region   = var.region
  ip_range = var.ip_range
}
