#!/usr/bin/env bash
set -euo pipefail
: "${ARTIFACTS_BUCKET:?Set the artifact bucket}"
pdf_path=${1:?PDF path required}
pdf_version=${2:?Version required, for example 2026-10-en}
[[ "$pdf_version" =~ ^[A-Za-z0-9_-]{1,64}$ ]] || exit 2
[[ $(head -c 5 "$pdf_path") == '%PDF-' ]] || { echo 'Expected a PDF file' >&2; exit 2; }
aws s3api put-object --bucket "$ARTIFACTS_BUCKET" --key "resume/$pdf_version/resume.pdf" --body "$pdf_path" --content-type application/pdf --if-none-match '*' >/dev/null
echo "Published $pdf_version. Set RESUME_VERSION in GitHub and deploy a new commit."
