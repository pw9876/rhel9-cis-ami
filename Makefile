PACKER_IMAGE     := ghcr.io/pw9876/packer-docker:1.15.1
# AWS targets run packer inside Docker (no local packer install required)
PACKER           := docker run --rm \
                      -v "$(CURDIR):/workspace" \
                      -w /workspace \
                      --user "$(shell id -u):$(shell id -g)" \
                      -e PACKER_PLUGIN_PATH=/workspace/.packer.d/plugins \
                      $(PACKER_IMAGE)
# Local QEMU build runs packer on the host (Docker cannot access QEMU/HVF)
PACKER_HOST      ?= packer

PACKER_DIR       := packer
PACKER_LOCAL_DIR := packer/local
VARS_FILE        := eu-west-2.pkrvars.hcl
LOCAL_VARS_FILE  := local.pkrvars.hcl
SCRIPTS_DIR      := scripts

.PHONY: init init-local fmt validate validate-local lint build build-local clean help

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

init: ## Download Packer plugins (AWS build — uses Docker)
	$(PACKER) init $(PACKER_DIR)/

init-local: ## Download Packer plugins (local QEMU build — requires packer on host)
	$(PACKER_HOST) init $(PACKER_LOCAL_DIR)/

fmt: ## Format Packer HCL files (writes in place)
	$(PACKER) fmt $(PACKER_DIR)/
	$(PACKER_HOST) fmt $(PACKER_LOCAL_DIR)/

validate: init ## Validate AWS Packer template syntax
	$(PACKER) fmt -check $(PACKER_DIR)/
	$(PACKER) validate -syntax-only $(PACKER_DIR)/

validate-local: init-local ## Validate local Packer template syntax
	$(PACKER_HOST) fmt -check $(PACKER_LOCAL_DIR)/
	$(PACKER_HOST) validate -syntax-only $(PACKER_LOCAL_DIR)/

lint: ## Run shellcheck on harden.sh
	shellcheck $(SCRIPTS_DIR)/harden.sh

build: init ## Build the AMI (requires AWS credentials and eu-west-2.pkrvars.hcl)
	@test -f $(VARS_FILE) || (echo "ERROR: $(VARS_FILE) not found. Copy eu-west-2.pkrvars.hcl.example and fill in values." && exit 1)
	$(PACKER) build -var-file=$(VARS_FILE) $(PACKER_DIR)/

build-local: init-local ## Build a local QCOW2 image (requires packer + QEMU on host)
	@test -f $(LOCAL_VARS_FILE) || (echo "ERROR: $(LOCAL_VARS_FILE) not found. Copy local.pkrvars.hcl.example and fill in values." && exit 1)
	$(PACKER_HOST) build -var-file=$(LOCAL_VARS_FILE) $(PACKER_LOCAL_DIR)/

clean: ## Remove generated files (manifest, local output)
	rm -f manifest.json manifest-local.json
	rm -rf output-local/
