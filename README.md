# k8s-observability-sre-lab

DigitalOcean Kubernetes (DOKS) observability lab. Infra first (this step), Helm later.

Architecture: [ARCHITECTURE.md](./ARCHITECTURE.md)  
Task: https://github.com/VladimirSemchishin/tasks/issues/1

## What Terraform creates

| Resource | Name / value |
|---|---|
| Spaces bucket (tfstate) | `tf-state-k8s-observability-sre-lab` (`nyc3`) |
| VPC | `k8s-observability-sre-lab-net` `10.10.10.0/24` |
| DOKS | `k8s-observability-sre-lab`, version `1.35.7-do.4`, `ha=false` |
| Node pool | **2 × `s-2vcpu-4gb`** (4 GiB / 2 vCPU each) |

HA control plane is **off**. Official provider default is `ha=true` on 1.36+ ($40/mo).

Reserved IP / Traefik LB — not in this step.

## Node size (why 2×4 GiB)

From `GET /v2/sizes` (account, 2026-09-12):

- `s-2vcpu-2gb` = 2 GiB — too small for Prom + Loki + Jaeger + Traefik + Dashboard + kube-system
- `s-2vcpu-4gb` = 4 GiB, **$24/mo = $0.03571/hr**
- `s-4vcpu-8gb` = 8 GiB on one node, $48/mo

Two `s-2vcpu-4gb` ≈ 8 GiB / 4 vCPU, **$0.071/hr**. Enough for kube-prometheus-stack + Loki + Alloy + Jaeger all-in-one (without OpenSearch). Destroy after the test.

## Deploy from your machine

Need: Terraform >= 1.5, DigitalOcean API token, Spaces access key + secret.

1. Copy `terraform.tfvars.example` → `terraform.tfvars` and fill:

```hcl
do_token           = "dop_v1_..."
spaces_access_id   = "DO00..."
spaces_secret_key  = "..."
region             = "nyc3"
project_name       = "k8s-observability-sre-lab"
kubernetes_version = "1.35.7-do.4"
node_size          = "s-2vcpu-4gb"
node_count         = 2
ha                 = false
```

2. Bucket (once; local state in `bootstrap/`):

```bash
terraform -chdir=bootstrap init
terraform -chdir=bootstrap plan
terraform -chdir=bootstrap apply
```

3. Cluster (state in Spaces). Export Spaces keys as AWS creds for the S3 backend ([DO docs](https://docs.digitalocean.com/products/spaces/reference/terraform-backend/)):

```bash
export AWS_ACCESS_KEY_ID="$spaces_access_id"
export AWS_SECRET_ACCESS_KEY="$spaces_secret_key"
terraform init
terraform plan
terraform apply
```

4. Kubeconfig:

```bash
terraform output -raw kubeconfig > kubeconfig
export KUBECONFIG=$PWD/kubeconfig
kubectl get nodes
```

5. Tear down (order matters):

```bash
terraform destroy
terraform -chdir=bootstrap destroy
```

Do not commit `terraform.tfvars` or `*.tfstate`.
