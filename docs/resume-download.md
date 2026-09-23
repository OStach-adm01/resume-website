# Resume download activation

The content update adds the three credentials from the supplied CV, a Projects placeholder page, and a blue palette. It does not automatically publish the PDF or apply infrastructure.

## Content provenance

The owner selected `/home/stanley/Desktop/cv/build/portfolio/resume-website-cv.pdf` (74,619 bytes), SHA-256 `fd7a81259118b03772388c149d07628c34663f40553bfc07ce24a6b21d919e5d`.
Use immutable version `2026-09-23-fd7a81259118`. Keep the PDF outside Git and the public Astro directory.

Certificates, in CV order: IBM DevOps and Software Engineering (`OG7XTC9Q0CWA`), AWS Cloud Solutions Architect (`L0EBMK39LFOO`), Python for Everybody (`CJKI5FPQFJOA`). Images were downloaded from Coursera and visually checked against the owner and credential names. Their source URL pattern is `https://s3.amazonaws.com/coursera_assets/meta_images/generated/CERTIFICATE_LANDING_PAGE/CERTIFICATE_LANDING_PAGE~ID/CERTIFICATE_LANDING_PAGE~ID.jpeg`. Local copies avoid third-party image requests. Verification links are in `app/src/data/certificates.ts`. The AWS program is a Coursera Professional Certificate, not an AWS certification exam.

## Configuration and review gates

1. Keep `DEPLOY_ENABLED=false` while preparing the infrastructure change. Do not merge an auto-deploying change before these gates pass.
2. Configure the Managed Turnstile widget for `olgierdstach.com` and `www.olgierdstach.com`, without pre-clearance. Set GitHub production variable `TURNSTILE_SITE_KEY` to the public key `0x4AAAAAAFBcTfBvaQjdUyOW`. Never use the Secret Key as a public variable.
3. After checking the AWS identity, run `python3 scripts/configure-turnstile-secret.py`. It prompts without echo and writes `/resume-website/turnstile-secret` as SSM SecureString using the default AWS-managed SSM key. It intentionally replaces an existing value if rerun. CLI input uses a temporary 0600 file inside a 0700 directory, removed on normal completion or exception; do not forcibly kill the process while it holds the secret. No secret enters process arguments, terminal output, Terraform, or GitHub build artifacts. Failures display only a sanitized error code. This seekable input avoids the AWS CLI v2 `/dev/stdin` JSON parsing failure.
4. Prepare and review a bootstrap plan. Expected scope is the runtime boundary adding read access to that one SSM parameter. Apply only after explicit review/approval.
5. Publish the exact PDF to the private artifact bucket using the existing immutable publisher:

   ```bash
   AWS_PROFILE=resume-terraform ARTIFACTS_BUCKET=resume-website-108327566685-artifacts bash scripts/publish-resume.sh /home/stanley/Desktop/cv/build/portfolio/resume-website-cv.pdf 2026-09-23-fd7a81259118
   ```

   Verify its hash first. Publishing requires explicit approval for this S3 write; no public ACL is added.

6. Set GitHub production variable `RESUME_VERSION=2026-09-23-fd7a81259118`. Set local Terraform `resume_version` to the same value (ignored tfvars or `TF_VAR_resume_version`). Deployment and drift workflows both pass this variable. Leaving it empty disables the backend download and the frontend button.
7. Prepare and review the platform plan. Expected changes include Lambda code/environment/IAM/timeout, a new API route and permission, a replacement API deployment snapshot, its stage reference, and CSP allowances for Turnstile scripts/frames. Stop on unrelated destructive changes. The CI plan guard intentionally blocks the snapshot replacement: apply the reviewed plan separately; do not weaken the guard.
8. Require a fresh no-change platform plan with the same variables, green PR checks, then enable deployment and merge. The chart stops copying PDFs to the web root and rejects `/resume/`.

## Verification

- Locally: `npm run check`, `npm test`, `npm run test:api`, `npm run test:e2e`, Terraform validation/mock tests, Helm render/security checks. Browser tests mock the external challenge; they do not prove the production widget or secret works.
- Live: confirm all certificate images and official links, Projects navigation, blue desktop/mobile layouts, no CAPTCHA request until the download dialog opens, and a working challenge on both allowed hostnames.
- Test No and Yes download paths; compare the downloaded PDF hash with the source. A recruiter record can be saved before a failed challenge; it records interest, not proof of download.
- Missing/invalid/reused token must not return PDF data. Direct `/resume/VERSION/resume.pdf` and `/resume/latest/resume.pdf` must return 404. Direct S3 access must remain private.
- Turnstile uses [server-side validation](https://developers.cloudflare.com/turnstile/get-started/server-side-validation/) and the documented [CSP allowances](https://developers.cloudflare.com/turnstile/reference/content-security-policy/). A client-only widget is insufficient.
- A rollback to an older release may lack these protections. Disable downloads before selecting a pre-CAPTCHA release; keep PDFs out of public artifacts.
