import json
import sys

outputs = json.load(sys.stdin)
for key in ['artifacts_bucket', 'ecr_repository', 'instance_id', 'distribution_id', 'site_url']:
    value = outputs[key]['value']
    assert isinstance(value, str) and '\n' not in value and '\r' not in value
    print(f'{key.upper()}={value}')
