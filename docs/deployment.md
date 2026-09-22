# Deployment

## Prerequisites

Use a dedicated AWS lab account. Enable root MFA, use a non-root administrative session for bootstrap, and record the actual Free Plan expiry. Buy the domain separately and delegate it to Cloudflare DNS. The project uses DNS-only records and CloudFront pay-as-you-go distribution configuration; AWS account Free Plan is a separate concept.

Install AWS CLI v2, Terraform 1.16.1, Node.js from `.nvmrc`, Python 3, Helm 3.19.0, and Git. Authenticate locally with temporary credentials. Confirm `aws sts get-caller-identity` matches the intended account before applying anything.

Review the resource plan and current AWS pricing. Expect one `t4g.small`, 16 GiB gp3, one charged public IPv4, and two running web pods on the same host. ECR retains twenty images; S3 retains current release prefixes until you prune them. Use approximately 730 hours/month for an always-on node and IPv4 when calculating the baseline. Additional credits are not guaranteed.

## Bootstrap

Copy the example configuration and supply your account-specific bucket name:

```bash
cp infra/bootstrap/terraform.tfvars.example infra/bootstrap/terraform.tfvars
terraform -chdir=infra/bootstrap init
terraform -chdir=infra/bootstrap plan -out=bootstrap.tfplan
terraform -chdir=infra/bootstrap apply bootstrap.tfplan
terraform -chdir=infra/bootstrap output
```

The first bootstrap uses local state to solve the backend creation dependency. Keep that state encrypted and outside Git. Once the bucket exists, copy `backend.tf.example` to `backend.tf` in the bootstrap module, then run `terraform init -migrate-state` with the bucket, region, encryption, `use_lockfile=true`, and key `bootstrap/terraform.tfstate`. Commit the backend declaration, never the state. CI roles are explicitly denied access to the bootstrap state prefix. The state bucket has `prevent_destroy`; preserve it during normal teardown.

If the GitHub OIDC provider already exists in the account, import it into bootstrap state before planning instead of creating a duplicate.

## First platform apply

Create Cloudflare API tokens scoped to the one zone: one with DNS edit/read for deployment and one DNS read-only token for drift. Zone identifiers and names are configuration, not credentials. Keep tokens in environment variables or a password manager.

```bash
cp infra/platform/terraform.tfvars.example infra/platform/terraform.tfvars
cp infra/platform/backend.hcl.example infra/platform/backend.hcl
# Edit both local files with real values, including the bootstrap boundary ARN.
# Export CLOUDFLARE_API_TOKEN without putting it in shell history or a file in Git.
terraform -chdir=infra/platform init -backend-config=backend.hcl
terraform -chdir=infra/platform plan -out=platform.tfplan
terraform -chdir=infra/platform apply platform.tfplan
terraform -chdir=infra/platform output
```

ACM validation waits for DNS; a missing Cloudflare delegation must be fixed before continuing. Confirm both SNS email subscriptions. CloudFront will initially show an origin error until the first application release is deployed. Do not publish this first-stage URL as a completed website.

The AMI is resolved from the public Amazon Linux 2023 parameter. A later AMI or cloud-init change can replace the single node and cause downtime. Read every infrastructure plan. Normal content releases do not require replacing the node.

## GitHub setup

Create the public `OStach-adm01/resume-website` repository and push the local project. Create a GitHub Environment named `production`, restrict deployment branches to `main`, and configure branch protection/rulesets requiring the CI website, infrastructure, and container jobs. For a solo repository, decide how reviews are satisfied before requiring another person's approval. Do not permit untrusted code onto `main`.

Set these **repository variables** so reusable and scheduled workflow conditions can read them:

| Variable               | Value                                             |
| ---------------------- | ------------------------------------------------- |
| `DEPLOY_ENABLED`       | Keep `false` until setup is complete; then `true` |
| `AWS_REGION`           | `eu-central-1`                                    |
| `STATE_BUCKET`         | Bootstrap state bucket                            |
| `DOMAIN_NAME`          | Domain without scheme or path                     |
| `CLOUDFLARE_ZONE_ID`   | The delegated zone identifier                     |
| `RUNTIME_BOUNDARY_ARN` | Bootstrap output                                  |
| `TERRAFORM_ROLE_ARN`   | Bootstrap `terraform` role                        |
| `PUBLISH_ROLE_ARN`     | Bootstrap `publish` role                          |
| `DEPLOY_ROLE_ARN`      | Bootstrap `deploy` role                           |
| `DRIFT_ROLE_ARN`       | Bootstrap `drift` role                            |
| `FREE_PLAN_EXPIRES_ON` | Actual `YYYY-MM-DD` expiry                        |
| `RESUME_VERSION`       | Empty until a PDF is published                    |

Set these **production environment secrets**: `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_READ_API_TOKEN`, and `ALERT_EMAIL`. No AWS secret access key is needed. Enable GitHub Actions issue creation so failed scheduled checks can open an issue.

Public repository workflow logs are public. The pipeline does not publish Terraform state, saved plans, recruiter input, or AWS response bodies. GitHub masks configured secret values, but review logs before attaching screenshots to portfolio material.

## Release

Merge a tested change into `main`. CI completes before deployment. The deployment job applies the current configuration, builds the site with its Git SHA and optional PDF version, scans/publishes an ARM64 image, and publishes the manifest last. Helm runs via SSM with the exact immutable release. A retry can reuse an identical published release.

If a live smoke test fails after rollout, the workflow fails visibly. Helm automatically rolls back a failed Kubernetes rollout, but a failed external smoke test does not automatically revert unrelated infrastructure. Use the Rollback workflow to select a known-good SHA.

The `production` environment is the authorization boundary for OIDC. Its branch restrictions are mandatory: the OIDC `sub` identifies the environment rather than embedding the branch name.
