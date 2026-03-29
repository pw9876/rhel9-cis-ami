PACKER_DIR   := packer
VARS_FILE    := eu-west-2.pkrvars.hcl
ANSIBLE_DIR  := ansible

.PHONY: init fmt validate lint build clean help

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

init: ## Download Packer plugins and Ansible roles
	packer init $(PACKER_DIR)/rhel9-cis.pkr.hcl
	ansible-galaxy install -r $(ANSIBLE_DIR)/requirements.yml \
		--roles-path $(ANSIBLE_DIR)/roles --force

fmt: ## Format Packer HCL files (writes in place)
	packer fmt $(PACKER_DIR)/

validate: init ## Validate Packer template syntax (no AWS creds needed)
	packer fmt -check $(PACKER_DIR)/
	packer validate -syntax-only $(PACKER_DIR)/rhel9-cis.pkr.hcl

lint: ## Run ansible-lint on the playbook
	ansible-galaxy install -r $(ANSIBLE_DIR)/requirements.yml \
		--roles-path $(ANSIBLE_DIR)/roles --force
	ansible-lint $(ANSIBLE_DIR)/playbook.yml

build: init ## Build the AMI (requires AWS credentials and eu-west-2.pkrvars.hcl)
	@test -f $(VARS_FILE) || (echo "ERROR: $(VARS_FILE) not found. Copy eu-west-2.pkrvars.hcl.example and fill in values." && exit 1)
	packer build -var-file=$(VARS_FILE) $(PACKER_DIR)/rhel9-cis.pkr.hcl

clean: ## Remove generated files (manifest, roles, collections)
	rm -f manifest.json
	rm -rf $(ANSIBLE_DIR)/roles $(ANSIBLE_DIR)/collections
