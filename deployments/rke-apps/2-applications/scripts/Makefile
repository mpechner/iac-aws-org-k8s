# ECR repo lives in the dev account; pass the dev account ID on the make line:
#   ECR_ACCOUNT_ID=<dev-account-id> make -C scripts
ECR_ACCOUNT_ID    ?= $(error ECR_ACCOUNT_ID is required: ECR_ACCOUNT_ID=<dev-account-id> make -C scripts)
AWS_ASSUME_ROLE   ?= arn:aws:iam::$(ECR_ACCOUNT_ID):role/terraform-execute
ECR_REGION        := us-west-2
ECR_REPO          := openvpn-dev
IMAGE_TAG         := latest
TIMESTAMP_TAG     := $(shell date +%Y%m%d-%H%M%S)

ECR_REGISTRY      := $(ECR_ACCOUNT_ID).dkr.ecr.$(ECR_REGION).amazonaws.com
IMAGE_URI_LATEST  := $(ECR_REGISTRY)/$(ECR_REPO):$(IMAGE_TAG)
IMAGE_URI_TIMESTAMP := $(ECR_REGISTRY)/$(ECR_REPO):$(TIMESTAMP_TAG)
PUBLISHER_DIR     := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))../../../modules/tls-issue/publisher

.PHONY: build push login all tag

all: login build tag push

login:
	@CREDS=$$(aws sts assume-role --role-arn "$(AWS_ASSUME_ROLE)" --role-session-name "ecr-push" \
	  --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text); \
	export AWS_ACCESS_KEY_ID=$$(echo $$CREDS | awk '{print $$1}'); \
	export AWS_SECRET_ACCESS_KEY=$$(echo $$CREDS | awk '{print $$2}'); \
	export AWS_SESSION_TOKEN=$$(echo $$CREDS | awk '{print $$3}'); \
	aws ecr get-login-password --region $(ECR_REGION) \
	  | docker login --username AWS --password-stdin $(ECR_REGISTRY)

build:
	docker build --platform linux/amd64 -t $(IMAGE_URI_TIMESTAMP) $(PUBLISHER_DIR)

tag:
	docker tag $(IMAGE_URI_TIMESTAMP) $(IMAGE_URI_LATEST)
	@echo "Tagged: $(IMAGE_URI_TIMESTAMP)"
	@echo "Tagged: $(IMAGE_URI_LATEST)"

push: login
	@CREDS=$$(aws sts assume-role --role-arn "$(AWS_ASSUME_ROLE)" --role-session-name "ecr-push" \
	  --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text); \
	export AWS_ACCESS_KEY_ID=$$(echo $$CREDS | awk '{print $$1}'); \
	export AWS_SECRET_ACCESS_KEY=$$(echo $$CREDS | awk '{print $$2}'); \
	export AWS_SESSION_TOKEN=$$(echo $$CREDS | awk '{print $$3}'); \
	docker push $(IMAGE_URI_TIMESTAMP); \
	docker push $(IMAGE_URI_LATEST)
	@echo ""
	@echo "Pushed:"
	@echo "  $(IMAGE_URI_TIMESTAMP)"
	@echo "  $(IMAGE_URI_LATEST)"
	@echo ""
	@echo "For terraform.tfvars use:"
	@echo "  openvpn_cert_publisher_image = \"$(IMAGE_URI_LATEST)\""
