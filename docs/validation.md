# Validation evidence

This file distinguishes local checks from deployment evidence. Update it with actual results, dates, and commit identifiers when deploying.

## Automated checks

- Astro type checking, ESLint, Prettier, and static production build.
- Frontend company-name validation unit tests.
- Python Lambda tests: validation, affirmative-only writes, 30-day expiry, retry idempotency, conflicting retries, and storage failures.
- Playwright desktop/mobile tests: English page, accessibility, no-call No flow, required company, failed save, retry, PDF download, and modal keyboard behavior.
- Lighthouse performance and accessibility budgets.
- Terraform validation and mocked security assertions; no AWS credentials are used by mocked tests.
- Helm lint, rendered Kubernetes schemas, and workload security assertions.
- Actionlint and Trivy configuration, secret, and container checks.
- Container integration checks: read-only runtime, health endpoint, missing-origin-header rejection, content delivery, and 404 behavior.

Certificate links are deliberately not checked. The owner will add and verify them.

## Local results: 2026-09-20

The project is not yet committed or deployed. These results apply to the local working tree, not a GitHub Actions run or AWS resources:

- Astro diagnostics, ESLint, formatting, and the production build passed.
- Two frontend unit tests and six Lambda unit tests passed.
- Eight browser tests passed across desktop and mobile Chromium, using the production build with the deployed Content Security Policy enforced.
- Lighthouse scored 100 for performance, accessibility, and best practices on the local test build. These are not live-site scores.
- Both Terraform modules passed validation, each passed its mocked test, and TFLint reported no findings.
- Helm lint, rendered workload security assertions, Kubernetes schema checks, and Actionlint passed.
- The npm audit reported zero vulnerabilities at the time of validation.
- The pinned Nginx base image passed the fixable HIGH/CRITICAL vulnerability gate on AMD64 and ARM64. The pinned AWS CLI init image passed the same gate on ARM64. These remote scans do not prove that the final container starts successfully.
- Trivy configuration checks passed with the explicit lab exceptions below; the secret scan reported no findings.

Docker Engine 29.8.1 is installed locally. The owner supplied successful output from the AMD64 runtime image build and the complete integration rerun: `Nginx readiness, origin gate, content, and 404 passed.` The test ran with a read-only root filesystem, dropped capabilities, and no privilege escalation, using the Helm-rendered Nginx configuration. It confirmed readiness, rejection of requests without the origin header, authorized content delivery, and a 404 for a missing page. This is owner-run local evidence, not an agent-run Docker test, ARM64 startup verification, or a live Kubernetes deployment.

The initial run stopped because `rg` was unavailable in the sudo environment; the script now uses a Bash-native assertion and checks prerequisites before starting a container. To reproduce the successful check (rebuilding is unnecessary if the image is unchanged):

```bash
cd /home/stanley/resume-website
sudo docker build --target runtime -f containers/nginx/Dockerfile -t resume:test .
sudo env "PATH=$PWD/.artifacts/tools:$PATH" bash scripts/test-container.sh
```

Do not make the Docker socket world-writable. These commands use sudo without changing group membership or daemon permissions.

## Explicit configuration-scan exceptions

The Terraform files contain narrowly scoped Trivy ignore annotations with their rationale. They are deliberate lab tradeoffs, not scanner bypasses for unexplained findings:

- `AVD-AWS-0132`: SSE-S3 encryption instead of a customer-managed KMS key for the state and artifact buckets.
- `AVD-AWS-0011`: no paid WAF deployment for this budget-constrained lab.
- `AVD-AWS-0104`: outbound HTTP/HTTPS for package installation and AWS API access.
- `AVD-AWS-0095`: SNS carries operational alarm metadata only; customer-managed encryption is not configured.

Image checks reject fixable HIGH/CRITICAL vulnerabilities. Lower-severity and unfixed findings are outside that blocking gate and still need periodic review. Dependabot updates the Nginx Dockerfile; review and refresh the pinned AWS CLI image in `charts/resume/values.yaml` when scanning reports a fix or during regular maintenance.

## Cloud checks still required after provisioning

- Confirm Free Plan service eligibility, available credits, quotas, and the current regional estimate.
- Apply bootstrap and platform with the intended account identity.
- Confirm ACM validation, Cloudflare delegation, CloudFront delivery, and restricted direct-origin access.
- Confirm ARM64 image startup, S3 init-container access, SSM deployment, and ECR credential refresh.
- Confirm OIDC rejects unauthorized repository/environment subjects.
- Check the live form with one synthetic record and delete that test record.
- Confirm SNS emails, rollback, drift detection, and a second no-change Terraform plan at the same configuration/AMI.

No AWS resources, GitHub repository, or Cloudflare records are created by local validation alone.
