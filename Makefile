.PHONY: help test run build up down stop start destroy

help:
	@echo "test     run the unit suite locally"
	@echo "run      run the app locally on :8080"
	@echo "build    build the container locally"
	@echo "up       terraform apply"
	@echo "stop     scale the service to 0 (stops compute charges)"
	@echo "start    scale the service back to 2"
	@echo "destroy  tear everything down"

test:
	pip install -q -r app/requirements.txt pytest && pytest tests/test_app.py -v

run:
	cd app && python app.py

build:
	docker build -t provenance-lab:local .

up:
	cd infra && terraform init && terraform apply

# Fargate bills per second. Parking the service overnight leaves only the
# ALB running (~$0.55/day) and drops compute to zero.
stop:
	aws ecs update-service --cluster provenance-lab --service provenance-lab --desired-count 0 --no-cli-pager

start:
	aws ecs update-service --cluster provenance-lab --service provenance-lab --desired-count 2 --no-cli-pager

destroy:
	cd infra && terraform destroy
