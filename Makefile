PACKER_IMAGE     := ghcr.io/pw9876/packer-docker:1.15.1
PACKER           := docker run --rm \
                      -v "$(CURDIR):/workspace" \
                      -w /workspace \
                      --user "$(shell id -u):$(shell id -g)" \
                      -e PACKER_PLUGIN_PATH=/workspace/.packer.d/plugins \
                      $(PACKER_IMAGE)

PACKER_DIR       := packer
PACKER_LOCAL_DIR := packer/local
VARS_FILE        := eu-west-2.pkrvars.hcl
LOCAL_VARS_FILE  := local.pkrvars.hcl
ANSIBLE_DIR      := ansible

.PHONY: init init-local fmt validate validate-local lint build build-local clean help

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

init: ## Download Packer plugins and Ansible roles (AWS build)
	$(PACKER) init $(PACKER_DIR)/rhel9-cis.pkr.hcl
	ansible-galaxy install -r $(ANSIBLE_DIR)/requirements.yml \
		--roles-path $(ANSIBLE_DIR)/roles --force

init-local: ## Download Packer plugins and Ansible roles (local QEMU build)
	$(PACKER) init $(PACKER_LOCAL_DIR)/rhel9-cis-local.pkr.hcl
	ansible-galaxy install -r $(ANSIBLE_DIR)/requirements.yml \
		--roles-path $(ANSIBLE_DIR)/roles --force

fmt: ## Format Packer HCL files (writes in place)
	$(PACKER) fmt $(PACKER_DIR)/
	$(PACKER) fmt $(PACKER_LOCAL_DIR)/

validate: init ## Validate Packer template syntax (no AWS creds needed)
	$(PACKER) fmt -check $(PACKER_DIR)/
	$(PACKER) validate -syntax-only $(PACKER_DIR)/rhel9-cis.pkr.hcl

validate-local: init-local ## Validate local Packer template syntax
	$(PACKER) fmt -check $(PACKER_LOCAL_DIR)/
	$(PACKER) validate -syntax-only $(PACKER_LOCAL_DIR)/rhel9-cis-local.pkr.hcl

lint: ## Run ansible-lint on the playbook
	ansible-galaxy install -r $(ANSIBLE_DIR)/requirements.yml \
		--roles-path $(ANSIBLE_DIR)/roles --force
	ansible-lint $(ANSIBLE_DIR)/playbook.yml

build: init ## Build the AMI (requires AWS credentials and eu-west-2.pkrvars.hcl)
	@test -f $(VARS_FILE) || (echo "ERROR: $(VARS_FILE) not found. Copy eu-west-2.pkrvars.hcl.example and fill in values." && exit 1)
	$(PACKER) build -var-file=$(VARS_FILE) $(PACKER_DIR)/rhel9-cis.pkr.hcl

build-local: init-local ## Build a local QCOW2 image (requires QEMU and local.pkrvars.hcl)
	@test -f $(LOCAL_VARS_FILE) || (echo "ERROR: $(LOCAL_VARS_FILE) not found. Copy local.pkrvars.hcl.example and fill in values." && exit 1)
	$(PACKER) build -var-file=$(LOCAL_VARS_FILE) $(PACKER_LOCAL_DIR)/rhel9-cis-local.pkr.hcl

clean: ## Remove generated files (manifest, roles, collections, local output)
	rm -f manifest.json manifest-local.json
	rm -rf $(ANSIBLE_DIR)/roles $(ANSIBLE_DIR)/collections
	rm -rf output-local/
