# ihatetimezones.com

A satirical static website about the absurdity of time zones, hosted on AWS (S3 + CloudFront) with Terraform-managed infrastructure.

## Architecture

```
Route 53 → CloudFront (HTTPS, gzip/brotli) → S3 (private, OAC)
```

- **S3** stores the static files, fully private (no public access)
- **CloudFront** serves the site with HTTPS, compression, and 24h caching
- **Origin Access Control (OAC)** connects CloudFront to S3 (not the legacy OAI)
- **ACM** provides the TLS certificate (DNS-validated via Route 53)
- **CloudFront Function** redirects `www` → apex in production

Two environments share the same Terraform config via `-var-file`:
- **prod**: `ihatetimezones.com` + `www.ihatetimezones.com` (www redirects to apex)
- **dev**: `dev.ihatetimezones.com`

## Prerequisites

- [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) configured with credentials
- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.5
- A Route 53 hosted zone for `ihatetimezones.com` already in your AWS account
- IAM permissions for S3, CloudFront, ACM, and Route 53

## Setup

### 1. Configure variables

```bash
cd infra
cp terraform.tfvars.example dev.tfvars
cp terraform.tfvars.example prod.tfvars
```

Edit each file to set the correct environment:

```hcl
# dev.tfvars
environment = "dev"

# prod.tfvars
environment = "prod"
```

### 2. Deploy infrastructure

Start with dev:

```bash
cd infra
terraform init
terraform plan -var-file=dev.tfvars
terraform apply -var-file=dev.tfvars
```

For production:

```bash
terraform plan -var-file=prod.tfvars
terraform apply -var-file=prod.tfvars
```

> **Note**: CloudFront distributions take 5–15 minutes to deploy. ACM certificate validation usually completes in under 2 minutes.

### 3. Deploy the site

```bash
./scripts/deploy.sh dev   # deploy to dev
./scripts/deploy.sh prod  # deploy to prod (requires confirmation)
```

The deploy script syncs files to S3 and creates a CloudFront cache invalidation.

## Project Structure

```
├── infra/                        # Terraform configuration
│   ├── main.tf                   # S3, CloudFront, ACM, Route 53, OAC
│   ├── variables.tf              # Input variables and locals
│   ├── outputs.tf                # Bucket name, distribution ID, site URL
│   ├── providers.tf              # AWS provider config + backend (commented out)
│   └── terraform.tfvars.example  # Variable template
├── site/                         # Static files served to S3
│   └── index.html                # The manifesto
├── scripts/
│   └── deploy.sh                 # S3 sync + CloudFront invalidation
├── .gitignore
└── README.md
```

## Environments

| | Production | Dev |
|---|---|---|
| Domain | `ihatetimezones.com` | `dev.ihatetimezones.com` |
| www redirect | Yes (→ apex) | No |
| S3 bucket | `ihatetimezones-prod-site` | `ihatetimezones-dev-site` |
| ACM SANs | `www.ihatetimezones.com` | — |
| Var file | `prod.tfvars` | `dev.tfvars` |

## Notes

- **Remote state**: The S3 backend block in `providers.tf` is commented out. Uncomment and configure it once you have a state bucket.
- **State per environment**: With the tfvars approach (not workspaces), each environment has its own local state file. Make sure to always use the correct `-var-file` flag.
- **Terraform fmt**: Run `terraform fmt` before committing Terraform changes.
