# pfuetze — homelab infrastructure
# Usage: just <target>
# Requires: just, opentofu, packer, ansible

set dotenv-load := true
set dotenv-filename := ".env"

# show available targets
default:
    @just --list

# ── images (packer) ──────────────────────────────────────────────────────────

# build a VM image template
image target="debian-base-13":
    cd images/{{target}} && packer build -var-file={{target}}.pkrvars.hcl .

# initialise packer template (run once after cloning)
images-init target="debian-base-13":
    cd images/{{target}} && packer init .

# validate packer templates
images-validate target="debian-base-13":
    cd images/{{target}} && packer validate -var-file={{target}}.pkrvars.hcl .

# ── infra (opentofu) ──────────────────────────────────────────────────────────

# initialise opentofu providers (run once after cloning)
infra-init:
    cd infra && tofu init

# show planned changes
infra-plan:
    cd infra && tofu plan

# apply changes
infra-apply:
    cd infra && tofu apply

# apply changes for single vm (target needs prefix: proxmox_virtual_environment_vm)
infra-apply-target target:
    cd infra && tofu apply -target {{target}}

# destroy single vm (target needs prefix: proxmox_virtual_environment_vm)
infra-destroy-target target:
    cd infra && tofu destroy -target {{target}}

