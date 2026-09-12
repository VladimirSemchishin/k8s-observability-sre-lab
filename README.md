# k8s-observability-sre-lab

DigitalOcean Kubernetes (DOKS) observability lab.

Architecture: [ARCHITECTURE.md](./ARCHITECTURE.md)  
Task: https://github.com/VladimirSemchishin/tasks/issues/1

```
terraform/     # VPC + DOKS (Spaces tfstate)
helmfile/      # Traefik (local charts + values + releases)
```

## What Terraform creates

| Resource | Name / value |
|---|---|
| Spaces bucket (tfstate) | `tf-state-k8s-observability-sre-lab` (`nyc3`) |
| VPC | `k8s-observability-sre-lab-net` `10.10.10.0/24` |
| DOKS | `k8s-observability-sre-lab`, version `1.35.7-do.4`, `ha=false` |
| Node pool | **2 × `s-2vcpu-4gb`** (4 GiB / 2 vCPU each) |

HA control plane is **off**. Official provider default is `ha=true` on 1.36+ ($40/mo).

Traefik Load Balancer IP is created in the helmfile step (DOKS `Service` type `LoadBalancer`), not as a Reserved IP.

## Node size (why 2×4 GiB)

From `GET /v2/sizes` (account, 2026-09-12):

- `s-2vcpu-2gb` = 2 GiB — too small for Prom + Loki + Jaeger + Traefik + Dashboard + kube-system
- `s-2vcpu-4gb` = 4 GiB, **$24/mo = $0.03571/hr**
- `s-4vcpu-8gb` = 8 GiB on one node, $48/mo

Two `s-2vcpu-4gb` ≈ 8 GiB / 4 vCPU, **$0.071/hr**. Destroy after the test.

## Deploy Terraform

Need: Terraform >= 1.5, DigitalOcean API token, Spaces access key + secret.

1. Copy `terraform/terraform.tfvars.example` → `terraform/terraform.tfvars` and fill in.

2. Bucket (once; local state in `terraform/bootstrap/`):

```bash
terraform -chdir=terraform/bootstrap init
terraform -chdir=terraform/bootstrap plan
terraform -chdir=terraform/bootstrap apply
```

3. Cluster (state in Spaces). Export Spaces keys as AWS creds for the S3 backend ([DO docs](https://docs.digitalocean.com/products/spaces/reference/terraform-backend/)):

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

5. Tear down (Helm first if applied, then):

```bash
terraform -chdir=terraform destroy
terraform -chdir=terraform/bootstrap destroy
```

## Helmfile (Traefik)

Official charts vendored under `helmfile/helm-charts/` (`traefik` 41.5.0 / `v3.7.13`, `traefik-crds` 1.18.0).

```bash
export TRAEFIK_BASICAUTH_HASH='...'   # bcrypt htpasswd hash; see helmfile/.env.helmfile.example
helmfile -f helmfile/helmfile.yaml template
# apply only after the template is checked
helmfile -f helmfile/helmfile.yaml apply
```

Dashboard: `https://<lb-ip>/ui/traefik` (Traefik default self-signed cert). Login `admin`. Other `/ui/*` routes land with those stacks.

Do not commit `terraform.tfvars`, `*.tfstate`, or `.env.helmfile`.
