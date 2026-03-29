# rhel9-cis-ami

Produces a **CIS Level 2 hardened RHEL 9 AMI** in `eu-west-2` using [Packer](https://www.packer.io/) (HCL2) and the [`ansible-lockdown/RHEL9-CIS`](https://github.com/ansible-lockdown/RHEL9-CIS) Ansible role.

## Prerequisites

| Tool | Version |
|------|---------|
| Packer | ≥ 1.10 |
| Ansible | ≥ 2.15 (ansible-core) |
| ansible-lint | ≥ 24.x |
| AWS CLI | configured with credentials for eu-west-2 |

## Quick start

```bash
# 1. Copy and populate the var file
cp eu-west-2.pkrvars.hcl.example eu-west-2.pkrvars.hcl
$EDITOR eu-west-2.pkrvars.hcl

# 2. Download plugins and roles
make init

# 3. Build the AMI
make build
```

## Make targets

| Target | Description |
|--------|-------------|
| `make init` | Download Packer plugins and Ansible roles |
| `make fmt` | Format HCL files in place |
| `make validate` | Syntax-only validation (no AWS creds needed) |
| `make lint` | Run ansible-lint |
| `make build` | Build the AMI (requires AWS credentials) |
| `make clean` | Remove generated artefacts |

## CIS Level 2 exceptions

EC2-specific overrides are documented in [`ansible/group_vars/all/cis.yml`](ansible/group_vars/all/cis.yml):

- `rhel9cis_set_boot_pass: false` — bootloader password is not practical on cloud images
- Separate partition controls disabled by default (single-root AMI layout)
- Physical-only AIDE initialisation skipped at build time

## CI pipeline

CI runs lint and validate only — no AWS credentials are required or stored in CI.

| Job | Description |
|-----|-------------|
| `validate` | `packer init` + `packer fmt -check` + `packer validate -syntax-only` |
| `lint` | `ansible-galaxy install` + `ansible-lint` |
| `dependency-scan` | `pip-audit` |
| `security` | GitGuardian ggshield |
| `semgrep` | Semgrep SAST |
| `quality` | SonarCloud |

Full AMI builds are run locally (`make build`) or triggered manually with AWS credentials.

## Secrets required (GitHub repo secrets)

| Secret | Purpose |
|--------|---------|
| `GITGUARDIAN_API_KEY` | GitGuardian secret scanning |
| `SEMGREP_APP_TOKEN` | Semgrep SAST |
| `SONAR_TOKEN` | SonarCloud quality gate |
