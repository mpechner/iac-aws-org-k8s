AWS_ACCOUNT_ID ?= $(shell aws sts get-caller-identity --query Account --output text)
ECR_ACCOUNT    := $(AWS_ACCOUNT_ID)
ECR_REGION    := us-west-2
ECR_REPO      := openvpn-dev
IMAGE_TAG     := latest
TIMESTAMP_TAG := $(shell date +%Y%m%d-%H%M%S)

ECR_REGISTRY  := $(ECR_ACCOUNT).dkr.ecr.$(ECR_REGION).amazonaws.com
IMAGE_URI_LATEST := $(ECR_REGISTRY)/$(ECR_REPO):$(IMAGE_TAG)
IMAGE_URI_TIMESTAMP := $(ECR_REGISTRY)/$(ECR_REPO):$(TIMESTAMP_TAG)
PUBLISHER_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))../../../modules/tls-issue/publisher

.PHONY: build push login all tag

all: build tag push

login:
	aws ecr get-login-password --region $(ECR_REGION) \
	  | docker login --username AWS --password-stdin $(ECR_REGISTRY)

build:
	docker build --platform linux/amd64 -t $(IMAGE_URI_TIMESTAMP) $(PUBLISHER_DIR)

tag:
	docker tag $(IMAGE_URI_TIMESTAMP) $(IMAGE_URI_LATEST)
	@echo "Tagged: $(IMAGE_URI_TIMESTAMP)"
	@echo "Tagged: $(IMAGE_URI_LATEST)"

push: login
	docker push $(IMAGE_URI_TIMESTAMP)
	docker push $(IMAGE_URI_LATEST)
	@echo ""
	@echo "Pushed:"
	@echo "  $(IMAGE_URI_TIMESTAMP)"
	@echo "  $(IMAGE_URI_LATEST)"
	@echo ""
	@echo "For terraform.tfvars use:"
	@echo "  openvpn_cert_publisher_image = \"$(IMAGE_URI_LATEST)\""
