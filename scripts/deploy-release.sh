#!/usr/bin/env bash
set -euo pipefail
: "${RELEASE_SHA:?}" "${INSTANCE_ID:?}" "${DISTRIBUTION_ID:?}" "${SITE_URL:?}"
[[ "$RELEASE_SHA" =~ ^[a-f0-9]{40}$ ]] || exit 2
command_id=$(aws ssm send-command --document-name resume-website-deploy --instance-ids "$INSTANCE_ID" --parameters "Release=$RELEASE_SHA" --query Command.CommandId --output text)
status=Pending
for attempt in $(seq 1 150); do
  status=$(aws ssm get-command-invocation --command-id "$command_id" --instance-id "$INSTANCE_ID" --query Status --output text 2>/dev/null || echo Pending)
  case "$status" in
    Success) break ;;
    Failed|Cancelled|TimedOut|Cancelling) echo "Deployment failed: $status (SSM command $command_id)" >&2; exit 1 ;;
  esac
  sleep 10
done
[[ "$status" == Success ]] || { echo "SSM timed out ($command_id)" >&2; exit 1; }
invalidation=$(aws cloudfront create-invalidation --distribution-id "$DISTRIBUTION_ID" --paths '/*' --query Invalidation.Id --output text)
aws cloudfront wait invalidation-completed --distribution-id "$DISTRIBUTION_ID" --id "$invalidation"
python3 scripts/smoke.py "$SITE_URL" "$RELEASE_SHA"
