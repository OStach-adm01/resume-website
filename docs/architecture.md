# Architecture and decisions

## ADR 001: Kubernetes as the web runtime

Astro emits static HTML, images, CSS, and JavaScript. Immutable release prefixes in S3 are the source for each Kubernetes pod. The init container downloads a release and its selected PDF into an `emptyDir`; unprivileged Nginx serves that volume read-only. A lost pod can fetch the release again without a persistent volume.

The single EC2 node runs k3s. Two replicas enable rolling updates but do not survive a node failure. The API remains independently hosted in Lambda, even if the node is unavailable. There is no EKS control-plane charge, ALB, NAT Gateway, Argo CD, or database inside the cluster.

## ADR 002: Immutable assets across rolling releases

CloudFront serves HTML, course images, and PDF through the Kubernetes origin. Hashed `/_astro/*` files have a separate private S3 origin with OAC. Both old and new hashed assets remain available during a rollout; otherwise an old HTML response can reference an asset missing from a new pod. S3's public access block remains enabled. Only the distribution can read the asset prefix through its resource policy.

The stable PDF alias can overlap during a rolling update, so the modal uses a versioned PDF URL. A manifest binds the source commit, runtime image digest, chart checksum, and PDF version. The release and manifest are published before changing the running workload. Unlike hashed CSS/JavaScript, each pod holds only its release's PDF: an old page can receive a PDF 404 after a PDF-changing rollout, and mixed pods can briefly return a 404 during it. Reload the page after deployment. Serving versioned PDFs through a private S3 origin is a future improvement if uninterrupted downloads across PDF changes are required.

## ADR 003: Terraform and application ownership

Terraform owns AWS resources, IAM, DNS, and cloud-init. Helm owns the application workload. GitHub Actions owns the artifact publication and invokes the constrained SSM deployment document. Uploading every generated file as a Terraform resource would enlarge state and mix content releases with infrastructure changes.

Terraform state includes the generated origin token. The state bucket is encrypted and private, and saved plans must remain private. Never claim that a `sensitive` flag removes a value from state. Bootstrap state is isolated from platform CI.

## ADR 004: AWS identity boundaries

GitHub uses OIDC with an exact repository/environment subject and audience. Runtime roles have a bootstrap-owned permissions boundary. The Lambda role can only write recruiter items and its application logs. The publishing role can write artifact objects and push images. The deployment role can invoke the project SSM document on tagged nodes.

The Terraform role has broad lifecycle permissions for several services in this dedicated account. It is a privileged infrastructure role, not an assertion of fully minimized production IAM. It cannot create runtime roles without the boundary or modify its own bootstrap role. The drift role uses AWS ReadOnlyAccess plus the specific platform-state lock permissions; it can read sensitive infrastructure metadata and must be treated accordingly.

For this single-tenant k3s lab, the S3 init container uses the EC2 instance profile via IMDSv2 with a hop limit of two. This also makes the node's bounded role reachable from other pods. Pod-level IAM isolation is not implemented. Do not run untrusted workloads here; migrating to workload identity requires a separate design. No AWS keys or Kubernetes API tokens are embedded in images.

ECR pull credentials expire. A systemd timer refreshes the pull secret every six hours, and deployment refreshes it again. SSM and the image refresh service use the instance role. Kubernetes secrets are encrypted at rest by k3s.

## ADR 005: Network and TLS boundaries

Viewer connections use CloudFront HTTPS and an ACM certificate. API-origin and S3-origin connections use HTTPS. The Kubernetes origin currently uses HTTP over port 30080, protected by the CloudFront managed prefix list and a random origin header. This last connection is not end-to-end TLS and the origin header is not an encryption substitute. No recruiter request bodies are routed through that connection. Treat origin TLS as a documented improvement before handling sensitive content or making a production-security claim.

The CloudFront prefix list consumes a large number of security-group rules. Verify the account quota if creating the group fails. There are no public port 22 or 6443 rules. Systems Manager supplies administration without inbound management ports.

## ADR 006: Recruiter interest and data minimization

No selection defaults to Yes. Selecting No does not create a recruiting-interest record. Selecting Yes requires a company name and successful persistence. Both options then call `/api/resume-download`, which validates a Turnstile token before reading the configured private PDF from S3. The recruiter endpoint remains separate: API Gateway validates its body through the `$default` model, including `recruiter: true`. Lambda rejects invalid input on both routes.

Turnstile is loaded only when the download dialog opens. Server-side Siteverify requires success, the configured root/www hostname, and the `resume-download` action. Expired or reused tokens fail closed. The secret is an SSM SecureString, provisioned outside Terraform so its value does not enter Terraform state. Lambda can read only the selected PDF object and the exact secret parameter. The small PDF (maximum 2 MB) is returned as base64 JSON with `Cache-Control: no-store`, then downloaded using a browser Blob. Nginx rejects `/resume/` and no PDF is copied into the public site. CloudFront's S3 policy grants access to built assets only, not resume objects. CAPTCHA is an abuse guard, not confidentiality or DRM: a recipient can still share a downloaded PDF.

An idempotency key plus a conditional DynamoDB write prevents duplicate records on retry. A payload hash detects changed content reusing the same key. DynamoDB's conditional failure response permits this check without granting GetItem. The record contains the company, timestamp, expiry, random identifier, payload hash, and source. It records interest, not proof of recruiter identity or a completed browser download.

TTL is set to 30 days; physical deletion is asynchronous. No PITR/export/backups retain these records. Access logs and request-body tracing are disabled. Fixed application error messages avoid logging company names, IP addresses, or request bodies. Public API Gateway remains callable directly; CORS and a UI question are not authentication. Throttling is a best-effort abuse/cost guard, not a hard quota.

New accounts can have Lambda concurrency quotas too small for reservations. The default `lambda_concurrency=-1` keeps deployment possible; change it to 5 after the account supports reserving concurrency while leaving AWS's required unreserved pool. API throttling is active in either case.

## ADR 007: Certificates supplied by the owner

Course images are ordinary local static assets linked to owner-supplied credential URLs. No Credly-specific representation is required, and no third-party scripts or embeds are loaded. The owner adds images and checks the links. The empty state does not fabricate credentials.
