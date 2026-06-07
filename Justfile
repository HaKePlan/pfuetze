# pfuetze — homelab infrastructure
# Usage: just <target>
# Requires: just, opentofu, packer, ansible

set dotenv-load := true
set dotenv-filename := ".env"

# show available targets, grouped as in this file
default:
    @just --list

# ── images (packer) ──────────────────────────────────────────────────────────

# build a VM image template
[group('images')]
image target="debian-base-13":
    cd images/{{target}} && packer build -var-file={{target}}.pkrvars.hcl .

# initialise packer template (run once after cloning)
[group('images')]
images-init target="debian-base-13":
    cd images/{{target}} && packer init .

# validate packer templates
[group('images')]
images-validate target="debian-base-13":
    cd images/{{target}} && packer validate -var-file={{target}}.pkrvars.hcl .

# ── infra (opentofu) ──────────────────────────────────────────────────────────

# initialise opentofu providers (run once after cloning)
[group('infra')]
infra-init:
    cd infra && tofu init

# show planned changes
[group('infra')]
infra-plan:
    cd infra && tofu plan

# apply changes
[group('infra')]
infra-apply:
    cd infra && tofu apply

# apply changes for single vm (target needs prefix: proxmox_virtual_environment_vm)
[group('infra')]
infra-apply-target target:
    cd infra && tofu apply -target {{target}}

# destroy single vm (target needs prefix: proxmox_virtual_environment_vm)
[group('infra')]
infra-destroy-target target:
    cd infra && tofu destroy -target {{target}}

# ── config (ansible) ──────────────────────────────────────────────────────────

# configure the chuebel proxmox node
[group('config')]
config-proxmox:
    cd config && venv/bin/ansible-playbook proxmox.yml

# configure proxmox node networking (run manually only — risky to apply remotely, see CLAUDE.md Network section)
[group('config')]
config-networking:
    cd config && venv/bin/ansible-playbook playbooks/networking.yml

# reconcile dns entries for all vms (idempotent — creates any missing entries, leaves existing ones unchanged)
[group('config')]
config-dns-reconcile:
    cd config && venv/bin/ansible-playbook playbooks/manage_dns_entries.yml

# ── snapshots (ansible) ───────────────────────────────────────────────────────

# create a vm snapshot
[group('snapshots')]
snapshot-create name snapshot:
    cd config && venv/bin/ansible-playbook playbooks/create_snapshot.yml --limit {{name}} -e snapshot_name={{snapshot}}

# rollback a vm to a snapshot (also starts the vm afterwards)
[group('snapshots')]
snapshot-rollback name snapshot:
    cd config && venv/bin/ansible-playbook playbooks/rollback_snapshot.yml --limit {{name}} -e snapshot_name={{snapshot}}

# remove a vm snapshot
[group('snapshots')]
snapshot-remove name snapshot:
    cd config && venv/bin/ansible-playbook playbooks/remove_snapshot.yml --limit {{name}} -e snapshot_name={{snapshot}}

# ── lifecycle (infra + config combined) ──────────────────────────────────────

# create a vm (tofu apply, then register its dns entry — vm must exist first so the dns playbook can find its ip)
[group('lifecycle')]
create-vm name:
    just infra-apply-target target=proxmox_virtual_environment_vm.{{name}}
    cd config && venv/bin/ansible-playbook playbooks/manage_dns_entries.yml --limit {{name}}

# destroy a vm (deregister its dns entry first, then tofu destroy — once destroyed it vanishes from the dynamic inventory)
[group('lifecycle')]
destroy-vm name:
    cd config && venv/bin/ansible-playbook playbooks/manage_dns_entries.yml --limit {{name}} -e dns_state=absent
    just infra-destroy-target target=proxmox_virtual_environment_vm.{{name}}

