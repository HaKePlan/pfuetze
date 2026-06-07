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
- **Justfile** as the single entrypoint. Targets are organized into named groups (`images`, `infra`, `config`, `snapshots`, `lifecycle`) — see "Justfile convention" below for the current list.

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

**Firewall:** IPFire (`stinkfisch`) at `10.130.2.1` — runs DNS (Unbound), firewall, and routing. Slated for eventual replacement by OPNsense (Phase 5), but that may be a year or more out — treat `stinkfisch` as durable, long-term infrastructure, not as something about to disappear. "Do not configure IPFire" means: do not build new firewall/routing tooling for it (that work belongs to OPNsense once Phase 5 lands). It does NOT mean avoid managing DNS records on its Unbound instance — that is ongoing, permanent Ansible work (see DNS below). OPNsense config will be added later under `config/playbooks/network.yml` using the `ansibleguy.opnsense` collection.

**Network:** Multiple VLANs. `vmbr300` is the main VM bridge. Proxmox networking config lives in `config/playbooks/networking.yml` using Jinja2 templates. This playbook is intentionally NOT imported into `proxmox.yml`/`site.yml` — rewriting `/etc/network/interfaces` remotely can sever the SSH connection to the node, so it must stay a deliberate, manually-triggered operation (`just config-networking`), run only when the network topology actually changes, never as part of routine convergence.

**DNS:** Unbound runs on `stinkfisch` (IPFire), config at `/etc/unbound/local.d`. DNS entries for VMs are managed via Ansible (`tasks/manage_dns_entries.yml`, migrating to `config/playbooks/` in Phase 3 with VM IPs derived from the dynamic Proxmox inventory rather than duplicated in host_vars). OpenTofu does not manage DNS. When Phase 5 eventually moves DNS off `stinkfisch`, re-pointing is a one-variable change (`dns_server` in `group_vars/all.yml`).

## Ansible conventions

- `config/ansible.cfg` is the single config file. `vault_password_file = ./vault-password` (gitignored).
- Inventory: `config/inventory/hosts` for static hosts (chuebel, stinkfisch), `config/inventory/proxmox.yml` for dynamic Proxmox inventory.
- Dynamic inventory uses `community.proxmox.proxmox` plugin. VMs are grouped by their Proxmox tags.
- Vault files follow the existing pattern: `vault.yml` alongside `vars.yml` in `host_vars/<host>/`.
- `config/site.yml` imports `proxmox.yml` then `services.yml`.
- `config/proxmox.yml` covers Proxmox node and networking.
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

Current Justfile targets, grouped as in the file itself (`just --list` is the live source of truth):
- `default` — lists available targets
- **images**: `image`, `images-init`, `images-validate`
- **infra**: `infra-init`, `infra-lint`, `infra-plan`, `infra-apply`, `infra-apply-target`, `infra-destroy-target`
- **config**: `config-init`, `config-lint`, `config-proxmox`, `config-networking`, `config-dns-reconcile`
- **snapshots**: `snapshot-create`, `snapshot-rollback`, `snapshot-remove`
- **lifecycle**: `create-vm`, `destroy-vm`

## Migration status

Track which parts have been migrated. Update this section as work progresses.

- [x] **Phase 0** — Repo skeleton and Justfile: `infra/`, `config/`, `images/` created; Justfile has `default` + `image` + `images-validate` targets
- [x] **Phase 1** — Packer: Debian 13 base image template complete (`images/debian-base-13/debian-base-13.pkr.hcl`, `http/preseed.cfg`, `*.pkrvars.hcl`); builds to Proxmox template VMID 9002 named `debian-base-13`; run with `just image`
- [x] **Phase 2** — OpenTofu: VM lifecycle. Replaces `manage_vms.yml` + `configure_single_vm.yml` + `decommission_vm.yml` from `ansible-proxmox`. Snapshot playbooks (`create_snapshot.yml`, `rollback_snapshot.yml`, `remove_snapshot.yml`) migrate to `config/playbooks/` in Phase 3 — they are not replaced by OpenTofu.
  - Cloud-init: use `bpg/proxmox` native `initialization` block — `user_account` (username `gigu` + SSH key), `ip_config` (static IP), `dns`. No custom snippet file. Root is locked by Packer template; Ansible connects as `gigu` and escalates via `sudo su -`.
  - All VMs have their own `.tf` file in `infra/`. Existing VMs were imported via `tofu import`. New VMs clone from template VMID 9002 (`scsi_hardware = "virtio-scsi-single"`, `disk.iothread = true`).
  - All VM resources require: `agent`, `initialization`, `serial_device`, `operating_system {}`, `lifecycle { ignore_changes = [operating_system] }`.
  - Packer fix: `/etc/network/interfaces` set to loopback + `source /etc/network/interfaces.d/*` so cloud-init is the sole network manager (no DHCP leak).
  - Credentials: endpoint + username hardcoded in `infra/providers.tf`. Only `PROXMOX_VE_PASSWORD` from `.env`.
- [x] **Phase 3** — Ansible: Proxmox node config (replaces `proxmox-ansible`). `chuebel` fully managed via `config/proxmox.yml` / `just config-proxmox`, idempotently confirmed live (`--check --diff` shows zero drift). Snapshot lifecycle and DNS record playbooks operable and verified, including a full `test02` create → snapshot → destroy run through the real `create-vm`/`destroy-vm` recipes. `ansible-proxmox` can now be retired.
- [ ] **Phase 4** — Ansible: VM service config (replaces `ansible-home`). Base role must: create gigu user, deploy SSH keys to root + gigu, add gigu to sudo, deploy `sshd_config.d/additional.conf` (disables root SSH + password auth).
  - **Parked for Phase 4 — DNS for non-Proxmox hosts:** `manage_dns_entries.yml` is currently VM-only — it derives IP/bridge/domain from live Proxmox facts (`proxmox_netN`/`proxmox_ipconfigN` → `network_domains`), which is what makes multi-homed VMs work. Hosts Ansible will manage but that aren't Proxmox guests (e.g. a Raspberry Pi — own group in the static inventory, static `ansible_host`, no Proxmox bridge to derive a domain from) currently need their `.conf` files hand-created in `/etc/unbound/local.d`. Revisit then: likely needs its own playbook (parallel to `proxmox.yml` for the Proxmox node) plus an explicit `dns_domain`-style host_var, rather than extending the VM-specific playbook. Goal: stop hand-creating those entries.
  - **Parked idea — `dns_state` → `dns_registration`:** replace the `present`/`absent` extra-var switch (`-e dns_state=absent`, used by `destroy-vm`) with one declarative `dns_registration: bool` host_var (default `true`): `true` ensures the entry exists (today's behavior), `false` both skips creation *and* removes an existing entry — so `destroy-vm` would pass `-e dns_registration=false` instead. One variable drives convergence both ways and doubles as a per-host DNS opt-out. Worth doing together with the item above since both touch the same playbook.
- [ ] **Phase 5** — OPNsense config (replaces IPFire hand-crafted setup)

## Before adding CI/CD

These must be solved before any pipeline work:

- **OpenTofu remote state** — currently `infra/terraform.tfstate` is local and gitignored. Losing it requires reimporting all VMs. Needs an S3-compatible backend (MinIO self-hosted or similar) before CI/CD.
- **Packer + OpenTofu secrets** — currently in `.env` (gitignored, local only). Needs a pipeline-compatible secrets solution (e.g. Vault, GitHub Actions secrets) before automating `just image` or `just infra-apply`.
- **Packer preseed.cfg network access** — during a Packer build, the temporary Proxmox VM fetches `preseed.cfg` via HTTP from the machine running Packer (`{{ .HTTPIP }}:{{ .HTTPPort }}`). This only works if the build machine is reachable from `vmbr300` (10.130.30.x/24). A remote CI runner outside the home network cannot serve this file. Needs a solution before automating `just image` — options include hosting `preseed.cfg` on an internal web server (e.g. pihole01) or embedding it directly in a custom ISO.
- **Packer auth** — currently `gigu@pam` username + password. Migrate to API token before CI/CD (noted in Packer conventions above).

## What not to do

- Do not use `community.general.proxmox_kvm` for new VM management — that belongs to OpenTofu now.
- Do not create a separate venv or `ansible.cfg` per subfolder. One flat config tree under `config/`.
- Do not split playbooks by tool concern. Split by operational concern: `proxmox.yml` vs `services.yml`.
- Do not introduce new external roles unless necessary. Prefer local roles under `config/roles/`.