"""Read-only checks of the public delivery path. Does not submit recruiter records."""
import json
import sys
import urllib.request

base = sys.argv[1].rstrip('/')
assert base.startswith('https://'), 'HTTPS is required'
with urllib.request.urlopen(base, timeout=20) as result:
    assert result.status == 200
    assert 'text/html' in result.headers.get('Content-Type', '')
    for name in ['Content-Security-Policy', 'Strict-Transport-Security', 'X-Content-Type-Options']:
        assert result.headers.get(name), f'Missing {name}'
    assert b'<html lang="en"' in result.read()
with urllib.request.urlopen(base + '/release.json', timeout=20) as result:
    release = json.load(result)['release']
    if len(sys.argv) > 2:
        assert release == sys.argv[2], 'Unexpected release'
print('HTTPS, English HTML, security headers, and release identity passed.')
