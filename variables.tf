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

variable "project_name" {
  type    = string
  default = "k8s-observability-sre-lab"
}

variable "region" {
  type    = string
  default = "nyc3"
}

variable "kubernetes_version" {
  type        = string
  default     = "1.35.7-do.4"
  description = "Slug from GET /v2/kubernetes/options"
}

variable "node_size" {
  type        = string
  default     = "s-2vcpu-4gb"
  description = "DOKS worker slug from /v2/kubernetes/options sizes"
}

variable "node_count" {
  type    = number
  default = 2
}

variable "ha" {
  type        = bool
  default     = false
  description = "HA control plane. Official default is true on 1.36+ ($40/mo). Keep false for this lab."
}

variable "vpc_ip_range" {
  type    = string
  default = "10.10.10.0/24"
}
