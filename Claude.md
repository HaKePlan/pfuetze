# pfuetze — Homelab Infrastructure Repo

## What this repo is

This is a homelab infrastructure monorepo. It manages a single Proxmox node (`chuebel`),
all VMs running on it, and the network firewall (OPNsense on a PC Engines APU4).

The repo is being built incrementally alongside two existing repos that are being retired:
- `HaKePlan/ansible-proxmox` — Proxmox node setup and VM lifecycle (Ansible only today) -> path to the repo on the machine from here ../ansible-proxmox
- `HaKePlan/ansible-home` — VM service configuration (Ansible only today) -> path to the repo on the machine from here ../ansible-home

Do not modify or reference those old repos. All new work goes here.

## Repo structure

```
pfuetze/
├── infra/       # OpenTofu — VM and infrastructure lifecycle
├── images/      # Packer — base VM image templates
├── config/      # Ansible — all configuration (Proxmox node + VMs + firewall)
└── Justfile     # single entrypoint for all operations
```

## Toolchain

- **OpenTofu** (not Terraform) for infrastructure lifecycle. Use `tofu` commands, not `terraform`.
- **Packer** for base image building. Proxmox builder (`proxmox-iso` or `proxmox-clone`).
- **Ansible** for configuration. Use FQCNs (e.g. `ansible.builtin.copy`, not just `copy`).
- **Justfile** as the single entrypoint. Keep targets: `infra`, `images`, `config`, `config-infra`, `config-services`, `all`.

## Infrastructure facts

**Proxmox node:** `chuebel` at `10.130.10.10`. SSH access as `root` (node provisioning). Proxmox API user `gigu@pam` (VM management — Packer, OpenTofu). SSH key `~/.ssh/id_rsa`.

**VMs (all Debian, managed by Proxmox):**
| Name | VMID | IP | Bridge | Purpose |
|---|---|---|---|---|
| `bina01` | 102 | 10.130.30.102/24 | vmbr300 | PostgreSQL + Python data scripts |
| `timemachine01` | 104 | 10.130.30.111/24 | vmbr300 | Time Machine (Samba) |
| `pihole01` | 101 | 10.130.30.10/24 | vmbr300 | Pi-hole DNS (Docker) |
| `dyndns01` | 103 | 10.130.30.112/24 | vmbr300 | Dynamic DNS updater |
| `test01` | 100 | 10.130.30.101/24 | vmbr300 | Test/scratch VM |

**Proxmox templates:**
| Name | VMID | Notes |
|---|---|---|
| `debian-base-13` | 9002 | Current Packer output — used by OpenTofu as clone source |
| `debian12-template` | 9001 | Legacy template — do not use |

**Firewall:** IPFire (`stinkfisch`) at `10.130.2.1` — being replaced by OPNsense. Do not configure IPFire. OPNsense config will be added later under `config/playbooks/network.yml` using the `ansibleguy.opnsense` collection.

**Network:** Multiple VLANs. `vmbr300` is the main VM bridge. Proxmox networking config lives in `config/playbooks/networking.yml` using Jinja2 templates.

**DNS:** Unbound runs inside a VM. DNS entries for VMs are managed via Ansible (`tasks/manage_dns_entries.yml`). OpenTofu does not manage DNS.

## Ansible conventions

- `config/ansible.cfg` is the single config file. `vault_password_file = ./vault-password` (gitignored).
- Inventory: `config/inventory/hosts` for static hosts (chuebel, stinkfisch), `config/inventory/proxmox.yml` for dynamic Proxmox inventory.
- Dynamic inventory uses `community.proxmox.proxmox` plugin. VMs are grouped by their Proxmox tags.
- Vault files follow the existing pattern: `vault.yml` alongside `vars.yml` in `host_vars/<host>/`.
- `config/site.yml` imports `infra.yml` then `services.yml`.
- `config/infra.yml` covers Proxmox node and networking.
- `config/services.yml` covers all VM service configuration.

## OpenTofu conventions

- Provider: `bpg/proxmox` (not the older `telmate` provider).
- State: local for now (`infra/terraform.tfstate`), gitignored.
- Structure: flat — all `.tf` files directly in `infra/`. One file per VM. Shared values in `infra/locals.tf`.
- SSH public key for cloud-init lives in `keys/gigu.pub` (committed to repo).
- VM definitions map directly from the `kvm:` blocks in the old `host_vars`. Each VM gets its own `.tf` file in `infra/`.
- Existing VMs are imported via `tofu import`, never destroyed and recreated.

## Packer conventions

- Templates live in `images/<image-name>/<image-name>.pkr.hcl`.
- Target: Proxmox (`proxmox-iso` builder).
- `*.pkrvars.hcl` files are committed — they contain non-secret values only (username, ISO URL, VMID).
- Secrets (passwords, tokens) go in `.env` as `PKR_VAR_<variable_name>` — Packer reads these automatically.
- Built images become Proxmox VM templates that OpenTofu references by template ID.
- Current auth: `gigu@pam` username + password via `PKR_VAR_proxmox_password`. Migrate to API token when adding CI/CD.

## Secrets

- All tool secrets go in `.env` (gitignored). Copy `.env.example` to get started.
- Ansible: Vault files encrypted with `ansible-vault`. Key at `./vault-password` (gitignored, lives on local machine).
- OpenTofu: endpoint and username are hardcoded in `infra/providers.tf` (not secrets). Only `PROXMOX_VE_PASSWORD` comes from `.env`.
- Packer: non-secret vars in committed `*.pkrvars.hcl`; password in `.env` as `PKR_VAR_proxmox_password`.
- Never commit secrets. Never hardcode credentials in any file.

## Justfile convention

The Justfile is the single entrypoint and must always reflect what actually exists. Do not add targets for phases or tools that haven't been implemented yet. Update the Justfile in the same step as the work it exposes.

Current Justfile targets: `default` (lists available targets), `image` (build Packer template, default: `debian-base-13`), `images-init`, `images-validate`, `infra-init`, `infra-plan`, `infra-apply`.

## Migration status

Track which parts have been migrated. Update this section as work progresses.

- [x] **Phase 0** — Repo skeleton and Justfile: `infra/`, `config/`, `images/` created; Justfile has `default` + `image` + `images-validate` targets
- [x] **Phase 1** — Packer: Debian 13 base image template complete (`images/debian-base-13/debian-base-13.pkr.hcl`, `http/preseed.cfg`, `*.pkrvars.hcl`); builds to Proxmox template VMID 9002 named `debian-base-13`; run with `just image`
- [ ] **Phase 2** — OpenTofu: VM lifecycle. Replaces `manage_vms.yml` + `configure_single_vm.yml` + `decommission_vm.yml` from `ansible-proxmox`. Snapshot playbooks (`create_snapshot.yml`, `rollback_snapshot.yml`, `remove_snapshot.yml`) migrate to `config/playbooks/` in Phase 3 — they are not replaced by OpenTofu.
  - Cloud-init: use `bpg/proxmox` native `initialization` block — `user_account` (username `gigu` + SSH key), `ip_config` (static IP). No custom snippet file. Root is locked by Packer template; Ansible connects as `gigu` and escalates via `sudo su -`.
  - All VMs clone from template VMID 9002. Each VM has its own `.tf` file in `infra/`. Existing VMs are imported, never destroyed.
  - Credentials: endpoint + username hardcoded in `infra/providers.tf`. Only `PROXMOX_VE_PASSWORD` from `.env`.
  - See `infra/phase2-tasks.md` for the step-by-step task checklist (deleted once phase is complete).
- [ ] **Phase 3** — Ansible: Proxmox node config (replaces `proxmox-ansible`).
- [ ] **Phase 4** — Ansible: VM service config (replaces `ansible-home`). Base role must: create gigu user, deploy SSH keys to root + gigu, add gigu to sudo, deploy `sshd_config.d/additional.conf` (disables root SSH + password auth).
- [ ] **Phase 5** — OPNsense config (replaces IPFire hand-crafted setup)

## What not to do

- Do not use `community.general.proxmox_kvm` for new VM management — that belongs to OpenTofu now.
- Do not create a separate venv or `ansible.cfg` per subfolder. One flat config tree under `config/`.
- Do not split playbooks by tool concern. Split by operational concern: `infra.yml` vs `services.yml`.
- Do not introduce new external roles unless necessary. Prefer local roles under `config/roles/`.