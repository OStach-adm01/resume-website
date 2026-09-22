#!/usr/bin/env bash
set -euo pipefail
for dependency in docker helm python3 curl mktemp mkdir cp chmod cut seq sleep; do
  command -v "$dependency" >/dev/null || { echo "Missing test dependency: $dependency" >&2; exit 1; }
done
python3 -c 'import yaml' || { echo 'Install PyYAML before running this test.' >&2; exit 1; }
fixture=$(mktemp -d /tmp/resume-nginx-test.XXXXXX)
mkdir -p "$fixture/site" "$fixture/config" "$fixture/origin"
cp tests/fixtures/index.html "$fixture/site/index.html"
cp tests/fixtures/404.html "$fixture/site/404.html"
cp tests/fixtures/allow.conf "$fixture/origin/allow.conf"
helm template resume charts/resume | python3 -c 'import sys,yaml; docs=list(yaml.safe_load_all(sys.stdin)); print(next(d for d in docs if d and d["kind"]=="ConfigMap")["data"]["site.conf"])' > "$fixture/config/site.conf"
chmod -R a+rX "$fixture"
container_id=$(docker run -d --read-only --cap-drop=ALL --security-opt=no-new-privileges --tmpfs /tmp:uid=101,gid=101 -p 127.0.0.1::8080 -v "$fixture/site:/site:ro" -v "$fixture/config:/etc/nginx/conf.d:ro" -v "$fixture/origin:/etc/nginx/origin:ro" resume:test)
trap 'docker stop "$container_id" >/dev/null' EXIT
port=$(docker port "$container_id" 8080 | cut -d: -f2)
for attempt in $(seq 1 20); do
  if curl --fail --silent "http://127.0.0.1:$port/healthz" >/dev/null; then break; fi
  sleep 1
done
[[ $(curl --silent --output /dev/null --write-out '%{http_code}' "http://127.0.0.1:$port/") == 403 ]]
content=$(curl --fail --silent --show-error -H 'X-Origin-Token: test-token' "http://127.0.0.1:$port/")
[[ "$content" == *fixture* ]]
[[ $(curl --silent --output /dev/null --write-out '%{http_code}' -H 'X-Origin-Token: test-token' "http://127.0.0.1:$port/missing") == 404 ]]
echo 'Nginx readiness, origin gate, content, and 404 passed.'
