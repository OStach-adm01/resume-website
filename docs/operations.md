# Operations

## Healthy release

After deployment, run `python3 scripts/smoke.py https://YOUR_DOMAIN EXPECTED_SHA`. Through an authorized SSM session, inspect `sudo k3s kubectl get pods -n resume` and `sudo k3s kubectl rollout status deployment/resume -n resume`. Verify the `resume-ecr.timer` is active. Confirm both SNS subscriptions and send a test notification from the SNS console to check email delivery.

The test endpoint `/healthz` reports process readiness, not an external availability guarantee. The init container must find `index.html` before the pod starts. The public smoke test checks the actual delivery path and release identity.

## Rollback

Run the GitHub Rollback workflow from `main` with a previously successful 40-character release SHA. It fetches the stored manifest and chart and reapplies them with Helm. It restores that release's PDF selection. It does not revert Terraform changes or deleted AWS resources.

ECR retains the twenty most recent images. A release whose image has expired cannot be rolled back until its exact runtime image is recovered. Verify retention before pruning; preserve known-good release artifacts and image digests together. S3 lifecycle removes noncurrent object versions after 30 days but leaves current release prefixes intact. Prune unneeded release prefixes explicitly after reviewing the exact target.

## Failed rollout

Inspect the GitHub job and SSM command status. SSM emits only the release identifier and fixed deployment errors, not the origin secret. In an SSM session use `sudo k3s kubectl describe pod -n resume POD_NAME` and the init-container logs. Common causes include an unpublished PDF version, missing S3 release, expired ECR credentials, insufficient memory, failed cloud-init, and registry/network problems. Check `sudo cloud-init status --long` and `sudo journalctl -u k3s` for node bootstrap problems.

Helm uses `--atomic` and a ten-minute timeout. If the external smoke test alone fails, check DNS, CloudFront propagation, and response headers before choosing rollback. An invalidation completes before the smoke check.

## Node recovery

Terraform can recreate the instance and its cloud-init configuration. The replacement gets the Elastic IP. Redeploy a known-good release through SSM after the node is registered and bootstrapped. The cluster database is not backed up; application state lives in S3, Terraform, and DynamoDB. This is a documented single-node recovery procedure, not automatic failover.

## Origin token rotation

Rotate the Terraform random password using an explicit `-replace=random_password.origin` plan. Apply, then deploy a new source commit so Nginx restarts with the new secret. Expect a temporary origin outage during this coordinated rotation. Do not post the Terraform plan, token, or Kubernetes Secret to GitHub. Reusing an already-running release without restarting the pods will not reload the Nginx map.

## Recruiter data

The application does not expose a read/list endpoint. Inspect records only with a separate, authorized AWS console session. To test the live API, submit a clearly identified test company once, inspect the single item and expiry, then delete that exact test item. Repeating the same request identifier must not create another row. Selecting No in the browser must produce no `/api` request. Do not use real company data in automated CI.

## Drift and costs

The Monday workflow uses a read-only AWS role and read-only Cloudflare token. Exit code 2 from Terraform means a change was found; it opens one deduplicated issue. The run also checks the website and warns fourteen days before the configured Free Plan expiry. It never applies corrections. AWS AMI updates can legitimately produce a plan to replace the node; decide and schedule that change explicitly.

Budgets cover the account's costs before credits at USD 5, 10, and 20 actual spend, and USD 20 forecast. Alert delivery and cost reporting can lag. Monitor the Billing console's credit balance and actual account plan separately; the workflow date is supplied configuration, not a live check of account eligibility.

## Teardown

Disable `DEPLOY_ENABLED` first. Export anything you intend to retain, including the current source, selected release artifacts, PDF, and encrypted state backups. Review `terraform plan -destroy` for the platform only. The nonempty S3 bucket intentionally prevents accidental complete deletion. If full deletion is intended, inventory that exact project bucket and its object versions, then explicitly empty it before applying the reviewed destroy plan. Do not use a broad or unresolved bucket target.

Retain the protected state bucket and bootstrap resources until the platform is fully removed. Cloudflare records managed by the platform are removed with the platform. Domain registration and renewal are outside Terraform and must be managed separately. Release unused public IPv4 addresses as part of teardown and re-check Billing for residual resources. There is no automatic destructive cost shutdown.
