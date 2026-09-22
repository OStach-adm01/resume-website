#!/usr/bin/env bash
set -euo pipefail
: "${RELEASE_SHA:?}" "${ARTIFACTS_BUCKET:?}" "${IMAGE_DIGEST:?}"
[[ "$RELEASE_SHA" =~ ^[a-f0-9]{40}$ ]] || exit 2
[[ "$IMAGE_DIGEST" =~ ^sha256:[a-f0-9]{64}$ ]] || exit 2
export RESUME_VERSION=${RESUME_VERSION:-}
if [[ -n "$RESUME_VERSION" ]]; then
  [[ "$RESUME_VERSION" =~ ^[A-Za-z0-9_-]{1,64}$ ]] || exit 2
  aws s3api head-object --bucket "$ARTIFACTS_BUCKET" --key "resume/$RESUME_VERSION/resume.pdf" >/dev/null
fi
test -s dist/index.html
mkdir -p .artifacts
helm package charts/resume --destination .artifacts
# An existing manifest marks a completed, immutable release. Never rewrite it.
existing=$(aws s3api list-objects-v2 --bucket "$ARTIFACTS_BUCKET" --prefix "releases/$RELEASE_SHA/manifest.json" --query KeyCount --output text)
if [[ "$existing" != 0 ]]; then
  aws s3 cp "s3://$ARTIFACTS_BUCKET/releases/$RELEASE_SHA/manifest.json" .artifacts/existing-manifest.json --only-show-errors
  python3 -c 'import json,os; m=json.load(open(".artifacts/existing-manifest.json")); assert m["imageDigest"]==os.environ["IMAGE_DIGEST"] and m["resumeVersion"]==os.environ["RESUME_VERSION"], "Existing release differs; create a new commit"'
  echo 'Reusing the existing immutable release.'
  exit 0
fi
# Hashed assets coexist across rollouts; CloudFront uses private S3 OAC for this path.
aws s3 sync dist/_astro/ "s3://$ARTIFACTS_BUCKET/assets/_astro/" --cache-control 'public,max-age=31536000,immutable' --only-show-errors
aws s3 sync dist/ "s3://$ARTIFACTS_BUCKET/releases/$RELEASE_SHA/site/" --only-show-errors
aws s3 cp .artifacts/resume-0.1.0.tgz "s3://$ARTIFACTS_BUCKET/releases/$RELEASE_SHA/chart.tgz" --only-show-errors
python3 - <<'PY'
import hashlib, json, os
from pathlib import Path
m = {'release': os.environ['RELEASE_SHA'], 'imageDigest': os.environ['IMAGE_DIGEST'], 'resumeVersion': os.environ['RESUME_VERSION'], 'chartSha256': hashlib.sha256(Path('.artifacts/resume-0.1.0.tgz').read_bytes()).hexdigest()}
Path('.artifacts/manifest.json').write_text(json.dumps(m, indent=2))
PY
aws s3api put-object --bucket "$ARTIFACTS_BUCKET" --key "releases/$RELEASE_SHA/manifest.json" --body .artifacts/manifest.json --content-type application/json --if-none-match '*' >/dev/null
