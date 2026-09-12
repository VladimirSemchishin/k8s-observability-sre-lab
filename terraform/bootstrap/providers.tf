provider "digitalocean" {
  token             = var.do_token
  spaces_access_id  = var.spaces_access_id
  spaces_secret_key = var.spaces_secret_key
}

variable "do_token" {
  type      = string
  sensitive = true
}
variable "spaces_access_id" {
  type      = string
  sensitive = true
}
variable "spaces_secret_key" {
  type      = string
  sensitive = true
}
variable "region" {
  type    = string
  default = "nyc3"
}
variable "bucket_name" {
  type    = string
  default = "tf-state-k8s-observability-sre-lab"
}
