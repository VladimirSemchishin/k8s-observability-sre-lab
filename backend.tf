# Remote state in DigitalOcean Spaces (S3-compatible).
# Create the bucket first: terraform -chdir=bootstrap init && apply
# Official: https://docs.digitalocean.com/products/spaces/reference/terraform-backend/
terraform {
  backend "s3" {
    endpoints = {
      s3 = "https://nyc3.digitaloceanspaces.com"
    }
    bucket                      = "tf-state-k8s-observability-sre-lab"
    key                         = "k8s-observability-sre-lab/terraform.tfstate"
    region                      = "us-east-1"
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_s3_checksum            = true
  }
}
