import datetime
import sys

expiry = datetime.date.fromisoformat(sys.argv[1])
remaining = (expiry - datetime.datetime.now(datetime.timezone.utc).date()).days
print(f'AWS Free Plan: {remaining} days until configured expiry.')
if remaining <= 14:
    raise SystemExit('Choose account upgrade, migration, or teardown before expiry.')
