variable "cluster_name" { type = string }
variable "region" { type = string }
variable "kubernetes_version" { type = string }
variable "vpc_uuid" { type = string }
variable "node_size" { type = string }
variable "node_count" { type = number }
variable "ha" { type = bool }
