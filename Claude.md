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

**Proxmox node:** `chuebel` at `10.130.10.10`, accessed as `root` via SSH key `~/.ssh/id_rsa`.

**VMs (all Debian, managed by Proxmox):**
| Name | IP | Bridge | Purpose |
|---|---|---|---|
| `bina01` | 10.130.30.102/24 | vmbr300 | PostgreSQL + Python data scripts |
| `timemachine01` | 10.130.30.111/24 | vmbr300 | Time Machine (Samba) |
| `pihole01` | dynamic | vmbr300 | Pi-hole DNS (Docker) |
| `dyndns01` | dynamic | — | Dynamic DNS updater |
| `test01` | dynamic | — | Test/scratch VM |

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
- Sensitive vars (Proxmox API credentials) in `infra/terraform.tfvars`, gitignored.
- VM definitions map directly from the `kvm:` blocks in the old `host_vars`. Each VM gets its own `.tf` file under `infra/vms/`.
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
- OpenTofu: `bpg/proxmox` reads `PROXMOX_VE_USERNAME`, `PROXMOX_VE_PASSWORD`, `PROXMOX_VE_ENDPOINT` natively from env — no `terraform.tfvars` needed for Proxmox credentials.
- Packer: non-secret vars in committed `*.pkrvars.hcl`; password in `.env` as `PKR_VAR_proxmox_password`.
- Never commit secrets. Never hardcode credentials in any file.

## Justfile convention

The Justfile is the single entrypoint and must always reflect what actually exists. Do not add targets for phases or tools that haven't been implemented yet. Update the Justfile in the same step as the work it exposes.

Current Justfile targets: `default` (lists available targets), `images` (build Packer templates).

## Migration status

Track which parts have been migrated. Update this section as work progresses.

- [x] **Phase 0** — Repo skeleton and Justfile: `infra/`, `config/`, `images/` created; Justfile has `default` + `images` targets
- [x] **Phase 1** — Packer: Debian base image template complete (`debian-base.pkr.hcl`, `http/preseed.cfg`, `*.pkrvars.hcl.example`); run with `just images`
- [ ] **Phase 2** — OpenTofu: VM lifecycle (replaces `manage_vms.yml`). Requirements: cloud-init must create `gigu` user + inject root SSH key so Ansible can connect on first boot.
- [ ] **Phase 3** — Ansible: Proxmox node config (replaces `proxmox-ansible`).
- [ ] **Phase 4** — Ansible: VM service config (replaces `ansible-home`). Base role must: create gigu user, deploy SSH keys to root + gigu, add gigu to sudo, deploy `sshd_config.d/additional.conf` (disables root SSH + password auth).
- [ ] **Phase 5** — OPNsense config (replaces IPFire hand-crafted setup)

## What not to do

- Do not use `community.general.proxmox_kvm` for new VM management — that belongs to OpenTofu now.
- Do not create a separate venv or `ansible.cfg` per subfolder. One flat config tree under `config/`.
- Do not split playbooks by tool concern. Split by operational concern: `infra.yml` vs `services.yml`.
- Do not introduce new external roles unless necessary. Prefer local roles under `config/roles/`.