# Terraform — VPC + DOKS

Creates the DigitalOcean Kubernetes cluster this lab runs on. App install is **not** here; that is [../helmfile/README.md](../helmfile/README.md).

## What it creates

| Resource | Value |
|---|---|
| Spaces bucket (tfstate) | `tf-state-k8s-observability-sre-lab` (`nyc3`) |
| VPC | `k8s-observability-sre-lab-net` `10.10.10.0/24` |
| DOKS | `k8s-observability-sre-lab`, `1.35.7-do.4`, `ha=false` |
| Node pool | 2 × `s-2vcpu-4gb` |

Control-plane HA is **off**. On Kubernetes 1.36+ the DigitalOcean provider defaults `ha=true` (~$40/mo extra).

The Traefik public IP is **not** a Reserved IP (those attach to Droplets only). Helmfile creates a `Service` of type `LoadBalancer`.

`s-2vcpu-2gb` is too small for this stack. Two `s-2vcpu-4gb` nodes are about $0.071/hr. Destroy the cluster when you are done.

## Layout

```
terraform/
  bootstrap/     # Spaces bucket, local state (once)
  modules/iac/   # network, k8s
  backend.tf     # S3-compatible Spaces backend
  terraform.tfvars.example
```

## Apply

Need: Terraform >= 1.5, `do_token`, Spaces access key + secret.

1. Copy `terraform.tfvars.example` → `terraform.tfvars` and fill in. Never commit that file.

2. Bucket (once; state stays local under `bootstrap/`):

```bash
terraform -chdir=terraform/bootstrap init
terraform -chdir=terraform/bootstrap plan
terraform -chdir=terraform/bootstrap apply
```

3. Cluster. Spaces credentials must look like AWS keys for the S3 backend ([DO docs](https://docs.digitalocean.com/products/spaces/reference/terraform-backend/)):

```bash
export AWS_ACCESS_KEY_ID="$spaces_access_id"
export AWS_SECRET_ACCESS_KEY="$spaces_secret_key"
terraform -chdir=terraform init
terraform -chdir=terraform plan
terraform -chdir=terraform apply
```

4. Kubeconfig:

```bash
terraform -chdir=terraform output -raw kubeconfig > kubeconfig
export KUBECONFIG=$PWD/kubeconfig
kubectl get nodes
```

Useful outputs: `vpc_id`, `cluster_id`, `cluster_endpoint`, `kubeconfig` (sensitive).

## Destroy

```bash
# helmfile destroy first if the stack is installed
terraform -chdir=terraform destroy
terraform -chdir=terraform/bootstrap destroy
```

Do not commit `terraform.tfvars`, `*.tfstate`, or `kubeconfig`.
