.PHONY: setup dev build test check infra-check chart-check preview
setup:
	npm ci
dev:
	npm run dev
build:
	npm run build
test:
	npm test
	npm run test:api
check:
	npm run check
	npm run build
	npm test
	npm run test:api
	npm run test:e2e
infra-check:
	python3 -m unittest discover -s scripts -p 'test_check_deploy_plan.py'
	python3 -m unittest discover -s scripts -p 'test_publish_release.py'
	terraform fmt -check -recursive infra
	terraform -chdir=infra/bootstrap init -backend=false
	terraform -chdir=infra/bootstrap validate
	terraform -chdir=infra/bootstrap test
	terraform -chdir=infra/platform init -backend=false
	terraform -chdir=infra/platform validate
	terraform -chdir=infra/platform test
chart-check:
	helm lint charts/resume
	helm template resume charts/resume | python3 scripts/check-manifests.py
preview:
	npm run build
	npm run preview
