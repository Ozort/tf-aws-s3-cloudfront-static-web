# tf-aws-s3-cloudfront-static-web

Terraform module that hosts a static website on **AWS S3**, fronted by **CloudFront** for HTTPS, caching, and global delivery. The S3 bucket stays private — CloudFront reaches it through Origin Access Control (OAC), and a bucket policy locks `s3:GetObject` down to that specific distribution only.

## Architecture

```
Visitor ──HTTPS──▶ CloudFront Distribution ──OAC──▶ S3 Bucket (private)
                          │                              │
                          └── redirect-to-https           ├─ index.html
                          └── gzip/brotli compression      └─ error.html
```

- **S3 bucket** (`aws_s3_bucket.website_bucket`) — stores the site files. No public access; only reachable via CloudFront.
- **Public access block** — explicit `aws_s3_bucket_public_access_block` on top of the bucket policy, blocking public ACLs.
- **CloudFront distribution** — serves the site over HTTPS, caches responses (`default_ttl` 1hr, `max_ttl` 24hr), and redirects HTTP → HTTPS.
- **Origin Access Control (OAC)** — the modern replacement for OAI; CloudFront signs requests to S3 with SigV4.
- **Bucket policy** — grants `s3:GetObject` only to the CloudFront service principal, scoped to this distribution's ARN via a `Condition`.

## Repository structure

```
.
├── main.tf          # S3 bucket, public access block, site objects, CloudFront + OAC, bucket policy
├── variables.tf      # Input variables (bucket_name, website_index_document, aws_region)
├── Outputs.tf         # Outputs (S3 bucket name, CloudFront domain name, CloudFront distribution ID)
├── provider.tf        # Terraform + AWS provider configuration, S3 remote backend
├── website/            # Static site source files (index.html, error.html, ...)
└── .gitignore
```

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) ~> 1.x (tested against AWS provider `~> 6.0`)
- An AWS account with credentials configured (`aws configure`, environment variables, or an assumed role)
- IAM permissions to create S3 buckets/objects/policies and CloudFront distributions/OACs
- The **AWS CLI** installed and authenticated (used for manual cache invalidation and remote state setup below), plus `cloudfront:CreateInvalidation` permission
- An existing **S3 bucket and DynamoDB table** for remote state (see below) — Terraform can't create its own backend storage

### Remote state setup

`provider.tf` configures an S3 backend for state, which must point at infrastructure that already exists:

```bash
aws s3api create-bucket --bucket your-terraform-state-bucket --region us-east-1
aws dynamodb create-table \
  --table-name terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
```

Then edit the `backend "s3" {}` block in `provider.tf` with your actual bucket/table names before running `terraform init`.

## Usage

```bash
git clone https://github.com/Ozort/tf-aws-s3-cloudfront-static-web.git
cd tf-aws-s3-cloudfront-static-web

terraform init
terraform plan -var="bucket_name=your-unique-bucket-name"
terraform apply -var="bucket_name=your-unique-bucket-name"
```

On success, Terraform prints the S3 bucket name, the CloudFront domain name, and the distribution ID. Open the CloudFront domain in a browser to view the site — note that **initial propagation can take several minutes**.

### Updating site content

Every file under `website/` is uploaded automatically via a `for_each` over `fileset("website/", "**")`. Add, edit, or remove a file in that folder and re-run `terraform apply` — Terraform detects checksum changes per file and re-uploads only what changed. There's no need to add a matching resource block for new files.

Content changes can take up to an hour to appear (the `default_ttl`) because CloudFront caches by default. To see changes immediately after an `apply`, manually invalidate the cache:

```bash
aws cloudfront create-invalidation --distribution-id <your-distribution-id> --paths "/*"
```

Get `<your-distribution-id>` from the `cloudfront_distribution_id` output, or run `terraform output cloudfront_distribution_id`.

### Tearing down

```bash
terraform destroy -var="bucket_name=your-unique-bucket-name"
```

## Inputs

| Name                      | Description                                        | Type   | Default              |
|---------------------------|------------------------------------------------------|--------|-----------------------|
| `bucket_name`              | Name of the S3 bucket. **Required** — no default, must be globally unique. | string | — |
| `website_index_document`   | CloudFront's default root object                    | string | `"index.html"`        |
| `aws_region`               | AWS region to deploy into                           | string | `"us-east-1"`         |

```bash
terraform apply -var="bucket_name=your-unique-bucket-name" -var="aws_region=eu-west-1"
```

## Outputs

| Name                                     | Description                                              |
|--------------------------------------------|-------------------------------------------------------------|
| `s3_bucket_name`                           | Name of the created S3 bucket                                |
| `cloudfront_distribution_domain_name`      | CloudFront domain to access the site over HTTPS               |
| `cloudfront_distribution_id`               | Distribution ID — useful for manually running a cache invalidation |

## Known limitations

- **No custom domain / ACM certificate** — the distribution uses CloudFront's default `*.cloudfront.net` certificate. Adding a custom domain requires a `viewer_certificate` block with an ACM cert (must be issued in `us-east-1`) plus a Route 53/DNS record.
- **No automatic cache invalidation** — after updating content, run the `aws cloudfront create-invalidation` command above manually, or wait out the 1-hour `default_ttl`. (An earlier version of this project automated this via a `null_resource` + `local-exec` provisioner, but that approach hit shell-quoting issues on Windows — the AWS CLI received a literal `"/*"` including quote characters instead of `/*` — so it was removed in favor of the manual step.)
- **Bootstrap chicken-and-egg for remote state** — the S3 bucket and DynamoDB table used for the backend must be created outside this Terraform config (see Prerequisites), since a backend can't depend on resources it manages.

