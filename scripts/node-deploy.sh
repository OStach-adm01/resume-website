#!/usr/bin/env bash
set -euo pipefail
release_sha=${1:?Release SHA required}
[[ "$release_sha" =~ ^[a-f0-9]{40}$ ]] || exit 2
set -a
source /etc/resume.env
set +a
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
export RELEASE_SHA="$release_sha"
export ARTIFACTS_BUCKET="resume-website-${AWS_ACCOUNT_ID}-artifacts"
exec 9>/var/lock/resume-deploy.lock
flock -n 9 || { echo 'Another deployment is running'; exit 1; }
cloud-init status --wait >/dev/null
release_dir=$(mktemp -d /tmp/resume-release.XXXXXX)
trap 'rm -f "$release_dir/values.json" "$release_dir/origin.json"' EXIT
aws s3 cp "s3://$ARTIFACTS_BUCKET/releases/$release_sha/manifest.json" "$release_dir/manifest.json" --only-show-errors
export RELEASE_DIR="$release_dir"
python3 - <<'PY'
import json, os, re
from pathlib import Path
root = Path(os.environ['RELEASE_DIR'])
m = json.loads((root / 'manifest.json').read_text())
assert m['release'] == os.environ['RELEASE_SHA']
assert re.fullmatch(r'sha256:[a-f0-9]{64}', m['imageDigest'])
assert re.fullmatch(r'[a-f0-9]{64}', m['chartSha256'])
assert re.fullmatch(r'[A-Za-z0-9_-]{1,64}', m['resumeVersion']) or m['resumeVersion'] == ''
repo = os.environ['AWS_ACCOUNT_ID'] + '.dkr.ecr.' + os.environ['AWS_DEFAULT_REGION'] + '.amazonaws.com/resume-website'
values = {'releaseSha': m['release'], 'bucket': os.environ['ARTIFACTS_BUCKET'], 'region': os.environ['AWS_DEFAULT_REGION'], 'resumeVersion': m['resumeVersion'], 'image': {'repository': repo, 'digest': m['imageDigest']}}
(root / 'values.json').write_text(json.dumps(values))
PY
aws s3 cp "s3://$ARTIFACTS_BUCKET/releases/$release_sha/chart.tgz" "$release_dir/chart.tgz" --only-show-errors
python3 - <<'PY'
import hashlib, json, os
from pathlib import Path
p = Path(os.environ['RELEASE_DIR'])
assert hashlib.sha256((p / 'chart.tgz').read_bytes()).hexdigest() == json.loads((p / 'manifest.json').read_text())['chartSha256']
PY
aws ssm get-parameter --name /resume-website/origin-token --with-decryption --query Parameter.Value --output text | python3 -c 'import sys,json,base64; token=sys.stdin.read().strip(); assert token.isalnum(); print(json.dumps({"apiVersion":"v1","kind":"Secret","metadata":{"name":"origin-token","namespace":"resume"},"data":{"allow.conf":base64.b64encode(("\""+token+"\" 1;\n").encode()).decode()}}))' | k3s kubectl apply -f -
/usr/local/bin/refresh-ecr
helm upgrade --install resume "$release_dir/chart.tgz" --namespace resume --values "$release_dir/values.json" --atomic --timeout 10m --history-max 10
k3s kubectl rollout status deployment/resume -n resume --timeout=120s
echo "Deployed release $release_sha"
