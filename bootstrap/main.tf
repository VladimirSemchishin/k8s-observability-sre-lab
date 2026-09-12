# https://github.com/digitalocean/terraform-provider-digitalocean/blob/main/docs/resources/spaces_bucket.md
resource "digitalocean_spaces_bucket" "tf_state" {
  name   = var.bucket_name
  region = var.region
  acl    = "private"
}

output "bucket_name" {
  value = digitalocean_spaces_bucket.tf_state.name
}

output "endpoint" {
  value = digitalocean_spaces_bucket.tf_state.endpoint
}
