#!/usr/bin/env bash
set -euo pipefail
# Verified release archives are installed only into a user-writable tools directory.
tools_dir=${RESUME_TOOLS_DIR:-"$PWD/.artifacts/tools"}
mkdir -p "$tools_dir"
tools_dir=$(cd "$tools_dir" && pwd)
download_dir=$(mktemp -d /tmp/resume-tools-download.XXXXXX)
cd "$download_dir"
fetch() { curl --fail --silent --show-error --location --retry 3 --max-time 120 "$1" -o "$2"; }
fetch https://get.helm.sh/helm-v3.19.0-linux-amd64.tar.gz helm-v3.19.0-linux-amd64.tar.gz
fetch https://get.helm.sh/helm-v3.19.0-linux-amd64.tar.gz.sha256sum helm.sha256
sha256sum -c helm.sha256
tar -xzf helm-v3.19.0-linux-amd64.tar.gz
install linux-amd64/helm "$tools_dir/helm"
# Actionlint uses ShellCheck when available; pin it so local and CI checks agree.
fetch https://github.com/koalaman/shellcheck/releases/download/v0.11.0/shellcheck-v0.11.0.linux.x86_64.tar.gz shellcheck.tar.gz
# SHA-256 published on the official GitHub release asset.
printf '%s\n' 'b7af85e41cc99489dcc21d66c6d5f3685138f06d34651e6d34b42ec6d54fe6f6  shellcheck.tar.gz' | sha256sum -c -
tar -xzf shellcheck.tar.gz
install shellcheck-v0.11.0/shellcheck "$tools_dir/shellcheck"
for spec in 'terraform-linters/tflint v0.64.0 tflint_linux_amd64.zip checksums.txt tflint' 'rhysd/actionlint v1.7.12 actionlint_1.7.12_linux_amd64.tar.gz actionlint_1.7.12_checksums.txt actionlint' 'yannh/kubeconform v0.8.0 kubeconform-linux-amd64.tar.gz CHECKSUMS kubeconform' 'aquasecurity/trivy v0.74.0 trivy_0.74.0_Linux-64bit.tar.gz trivy_0.74.0_checksums.txt trivy'; do
  read -r repo version archive checksums binary <<< "$spec"
  fetch "https://github.com/$repo/releases/download/$version/$archive" "$archive"
  fetch "https://github.com/$repo/releases/download/$version/$checksums" "$checksums"
  awk -v name="$archive" '$2 == name || $2 == "*"name {print}' "$checksums" | sha256sum -c -
  if [[ "$archive" == *.zip ]]; then unzip -q -o "$archive"; else tar -xzf "$archive"; fi
  install "$binary" "$tools_dir/$binary"
done
if [[ -n "${GITHUB_PATH:-}" ]]; then printf '%s\n' "$tools_dir" >> "$GITHUB_PATH"; fi
echo "Tools installed in $tools_dir"
