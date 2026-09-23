# Deployment

## Prerequisites

Use a dedicated AWS lab account. Enable root MFA, use a non-root administrative session for bootstrap, and record the actual Free Plan expiry. Buy the domain separately and delegate it to Cloudflare DNS. The project uses DNS-only records and CloudFront pay-as-you-go distribution configuration; AWS account Free Plan is a separate concept.

Install AWS CLI v2, Terraform 1.16.1, Node.js from `.nvmrc`, Python 3, Helm 3.19.0, and Git. Authenticate locally with temporary credentials. Confirm `aws sts get-caller-identity` matches the intended account before applying anything.

Review the resource plan and current AWS pricing. Expect one `t4g.small`, 16 GiB gp3, one charged public IPv4, and two running web pods on the same host. ECR retains twenty images; S3 retains current release prefixes until you prune them. Use approximately 730 hours/month for an always-on node and IPv4 when calculating the baseline. Additional credits are not guaranteed.

## Deployment checkpoint: 2026-09-22

This is the handoff point for a later Codex session. Treat the entries below as historical evidence and re-check AWS, GitHub, DNS, and the local checkout before making a change.

### Completed

- AWS account `108327566685` is active. The owner reported a `$100` credit balance and confirmed the Free Plan expiry as `2027-03-22`. Root MFA is intentionally not enabled; do not state that it is enabled.
- Local CLI access uses temporary console credentials: profile `resume-login` is the browser-login profile and `resume-terraform` is the `credential_process` profile Terraform uses. The verified caller was `arn:aws:iam::108327566685:user/resume-bootstrap`, not root. Never create or store AWS access keys.
- Bootstrap Terraform was applied successfully: `21 added, 0 changed, 0 destroyed`. It created only the protected state bucket, GitHub OIDC provider, GitHub deployment roles, and the runtime permissions boundary. Platform resources have not been applied.
- Bootstrap state was migrated to `s3://resume-website-108327566685-state/bootstrap/terraform.tfstate`. It was verified as private, SSE-S3 encrypted, versioned, and configured with the S3 lockfile backend. A local private state backup exists under `.artifacts/` and must not be committed.
- Bootstrap outputs are:

  | Output           | Value                                                              |
  | ---------------- | ------------------------------------------------------------------ |
  | State bucket     | `resume-website-108327566685-state`                                |
  | Runtime boundary | `arn:aws:iam::108327566685:policy/resume-website-runtime-boundary` |
  | Terraform role   | `arn:aws:iam::108327566685:role/resume-website-terraform`          |
  | Publish role     | `arn:aws:iam::108327566685:role/resume-website-publish`            |
  | Deploy role      | `arn:aws:iam::108327566685:role/resume-website-deploy`             |
  | Drift role       | `arn:aws:iam::108327566685:role/resume-website-drift`              |

- GitHub repository `OStach-adm01/resume-website` is public. Its `production` environment permits only `main`; repository variable `DEPLOY_ENABLED` is `false`. The `main` ruleset blocks deletion and force pushes, requires a pull request with zero approvals, and requires the `infrastructure`, `website`, and `container` checks to pass and be current.
- CI passed for commit `cc32f0c0e8e0db3afa48bdf304216dbdeb066f87`; deployment was skipped because `DEPLOY_ENABLED=false`. The CI fix added ShellCheck to local tooling and corrected rollback command error handling.
- Bootstrap remote-state changes were merged through PR #11 into `main` at commit `6982c0b`. The local deployment and drift workflow changes that read the Zone ID from secrets still need to be published and merged after CI passes.
- The first local platform plan was reviewed: `59 to add, 0 to change, 0 to destroy`, targeting account `108327566685`, region `eu-central-1`, and expiry `2027-03-22`. No apply was performed. The saved plan is private and ignored by Git. A successful initial plan does not establish that the Cloudflare token can access the intended zone or that existing DNS records are conflict-free.
- Baseline list pricing checked on 2026-09-22 is approximately `$19.19/month` at 730 hours: `$14.02` for `t4g.small`, `$1.52` for 16 GiB gp3, and `$3.65` for public IPv4. Storage beyond the root disk, requests, monitoring, traffic, and taxes are additional; credits are excluded. The configured `$20` budget is an alert threshold, not a spending cap.

### Safe resume procedure

1. Check the current branch, working tree, remote, and recent commits. Do not overwrite local ignored files such as `infra/bootstrap/backend.hcl`, `infra/bootstrap/terraform.tfvars`, or Terraform state.
2. Check the active AWS identity with `aws sts get-caller-identity --profile resume-terraform`. It must be the intended non-root bootstrap identity in account `108327566685`.
3. Confirm the remote bootstrap state object exists and is private, encrypted, and versioned. Run `terraform -chdir=infra/bootstrap init -backend-config=backend.hcl` followed by `terraform -chdir=infra/bootstrap plan`; require `No changes` before using any state output.
4. Preserve local changes while updating from `main`; publish the Zone ID secret wiring through a pull request and require its CI checks to pass before merging. The generic `backend.tf` is safe to commit; `backend.hcl` is not.
5. Keep `DEPLOY_ENABLED=false`. Verify Cloudflare access and the user-configured GitHub settings, then prepare a platform plan. Do not apply the platform module until its exact plan, account plan/expiry, current estimate, and Cloudflare configuration have been reviewed.

### Secrets and data boundaries

- Never put Cloudflare tokens, AWS credentials, backend files, state files, plans, the origin token, recruiter records, or PDF source files in Git, issue text, PR text, or public workflow logs.
- Certificate image links remain owner-supplied and intentionally unverified by CI.
- The owner purchased `olgierdstach.com` through Cloudflare and confirmed adding the requested GitHub secrets and variables, including the deployment and drift tokens, `CLOUDFLARE_ZONE_ID`, `ALERT_EMAIL`, and the `2027-03-22` expiry. This is owner-reported; authenticated GitHub settings verification remains pending. Keep the Zone ID out of committed files and repository variables; the local Terraform configuration is ignored by Git. No PDF version has been supplied.

## Bootstrap

### New account only: create the state bucket

Use this sequence only when the account has not been bootstrapped and no remote bootstrap state exists. The committed backend declaration must be temporarily disabled because its S3 bucket does not exist yet. On an already bootstrapped account, use the existing-backend instructions below instead.

Copy the example configuration and supply your account-specific bucket name. Authenticate using your non-root bootstrap profile before proceeding:

```bash
cp infra/bootstrap/terraform.tfvars.example infra/bootstrap/terraform.tfvars
# Edit terraform.tfvars with the intended account, repository, and region.
umask 077
mv infra/bootstrap/backend.tf infra/bootstrap/backend.tf.disabled
terraform -chdir=infra/bootstrap init
terraform -chdir=infra/bootstrap plan -out=bootstrap.tfplan
# Review the plan before applying it.
terraform -chdir=infra/bootstrap apply bootstrap.tfplan
terraform -chdir=infra/bootstrap output
```

The first bootstrap uses local state to solve the backend creation dependency. Keep it on encrypted storage and outside Git. After a successful apply, make a private backup of `infra/bootstrap/terraform.tfstate`, then restore the backend declaration and configure the destination:

```bash
mv infra/bootstrap/backend.tf.disabled infra/bootstrap/backend.tf
cp infra/bootstrap/backend.hcl.example infra/bootstrap/backend.hcl
# Edit backend.hcl: bucket name and allowed_account_ids must match your account.
terraform -chdir=infra/bootstrap init -migrate-state -backend-config=backend.hcl
terraform -chdir=infra/bootstrap plan
```

Confirm copying the existing local state when prompted. If the destination already contains conflicting state, stop and investigate; do not force an overwrite. After migration, verify the remote object is versioned and encrypted, and require a no-change plan before continuing. Keep the private backup until verification is complete. Do not reuse the pre-migration saved plan.

Only the generic backend declaration and example settings belong in Git. The real `backend.hcl`, state, backups, and saved plans are ignored. CI roles are explicitly denied access to the bootstrap state prefix. The state bucket has `prevent_destroy`; preserve it during normal teardown.

### Existing backend: initialize another checkout

Restore your account-specific `terraform.tfvars` and `backend.hcl` from the examples, then authenticate with the intended bootstrap administrator and run:

```bash
terraform -chdir=infra/bootstrap init -backend-config=backend.hcl
terraform -chdir=infra/bootstrap plan
```

Do not disable the backend or migrate unrelated local state into an existing deployment. A fresh checkout must find the existing resources through remote state, not propose creating them again.

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
| `RUNTIME_BOUNDARY_ARN` | Bootstrap output                                  |
| `TERRAFORM_ROLE_ARN`   | Bootstrap `terraform` role                        |
| `PUBLISH_ROLE_ARN`     | Bootstrap `publish` role                          |
| `DEPLOY_ROLE_ARN`      | Bootstrap `deploy` role                           |
| `DRIFT_ROLE_ARN`       | Bootstrap `drift` role                            |
| `FREE_PLAN_EXPIRES_ON` | Actual `YYYY-MM-DD` expiry                        |
| `RESUME_VERSION`       | Empty until a PDF is published                    |

Set these **production environment secrets**: `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_READ_API_TOKEN`, `CLOUDFLARE_ZONE_ID`, and `ALERT_EMAIL`. The Zone ID is stored as a secret at the owner's request so GitHub masks its value in workflow logs. No AWS secret access key is needed. Enable GitHub Actions issue creation so failed scheduled checks can open an issue.

Public repository workflow logs are public. The pipeline does not publish Terraform state, saved plans, recruiter input, or AWS response bodies. GitHub masks configured secret values, but review logs before attaching screenshots to portfolio material.

## Release

Before enabling deployment, compare repository variables and any `production` environment overrides with the reviewed local configuration. In particular, `DOMAIN_NAME` must be the bare domain and `RUNTIME_BOUNDARY_ARN` must match the bootstrap output exactly. The release workflow rejects resource deletions/replacements and changes to existing IAM permissions boundaries. Review and apply intentional changes of those kinds separately before releasing; do not bypass the check to fix misconfigured variables.

Merge a tested change into `main`. CI completes before deployment. The deployment job applies the current configuration, builds the site with its Git SHA and optional PDF version, scans/publishes an ARM64 image, and publishes the manifest last. Helm runs via SSM with the exact immutable release. A retry can reuse an identical published release.

If a live smoke test fails after rollout, the workflow fails visibly. Helm automatically rolls back a failed Kubernetes rollout, but a failed external smoke test does not automatically revert unrelated infrastructure. Use the Rollback workflow to select a known-good SHA.

The `production` environment is the authorization boundary for OIDC. Its branch restrictions are mandatory: the OIDC `sub` identifies the environment rather than embedding the branch name.

GitHub uses immutable OIDC subjects for this repository. Bootstrap trust policies must match `repo:OWNER@OWNER_ID/REPO@REPOSITORY_ID:environment:production`, including both numeric IDs. Set `github_owner_id` and `github_repository_id` alongside `github_repository` when adapting the project. A name-only subject causes `sts:AssumeRoleWithWebIdentity` to fail. Verify the presented subject through CloudTrail without logging the JWT; retain exact `StringEquals` matching and the `sts.amazonaws.com` audience.
