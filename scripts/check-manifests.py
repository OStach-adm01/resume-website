"""Validate security properties of the rendered Helm chart."""
import sys
import yaml

docs = list(yaml.safe_load_all(sys.stdin))
deployment = next(d for d in docs if d and d['kind'] == 'Deployment')
pod = deployment['spec']['template']['spec']
assert pod['automountServiceAccountToken'] is False
assert pod['securityContext']['runAsNonRoot'] is True
assert pod['securityContext']['seccompProfile']['type'] == 'RuntimeDefault'
assert not pod.get('hostNetwork')
assert deployment['spec']['strategy']['rollingUpdate']['maxUnavailable'] == 0
for container in pod['containers'] + pod['initContainers']:
    security = container['securityContext']
    assert security['allowPrivilegeEscalation'] is False
    assert security['readOnlyRootFilesystem'] is True
    assert 'ALL' in security['capabilities']['drop']
    assert container['resources']['limits']['memory']
for container in pod['containers']:
    assert container['readinessProbe'] and container['livenessProbe']
print('Rendered workload security checks passed.')
