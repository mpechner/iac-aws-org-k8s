ECR_ACCOUNT  := REDACTED_ACCOUNT_ID
ECR_REGION   := us-west-2
ECR_REPO     := openvpn-dev
IMAGE_TAG    := latest

ECR_REGISTRY := $(ECR_ACCOUNT).dkr.ecr.$(ECR_REGION).amazonaws.com
IMAGE_URI    := $(ECR_REGISTRY)/$(ECR_REPO):$(IMAGE_TAG)
PUBLISHER_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))../../../modules/tls-issue/publisher

.PHONY: build push login all

all: build push

login:
	aws ecr get-login-password --region $(ECR_REGION) \
	  | docker login --username AWS --password-stdin $(ECR_REGISTRY)

build:
	docker build --platform linux/amd64 -t $(IMAGE_URI) $(PUBLISHER_DIR)

push: login
	docker push $(IMAGE_URI)
	@echo ""
	@echo "Done. openvpn_cert_publisher_image = \"$(IMAGE_URI)\""
