# pfuetze-infra

Homelab infrastructure for a single Proxmox node (`chuebel`) and the VMs running on it. Three tools, one entrypoint:

```
infra/    OpenTofu  — VM lifecycle (create/resize/destroy, hardware, cloud-init)
images/   Packer    — base VM image templates
config/   Ansible   — all configuration (Proxmox node + VMs + firewall DNS)
Justfile            — single entrypoint for every operation; run `just` to list targets
```

## Contents

- [1. Setting up this repo](#1-setting-up-this-repo)
  - [Tools](#tools)
  - [Secrets](#secrets)
  - [OpenTofu](#opentofu)
  - [Packer](#packer)
  - [Ansible](#ansible)
- [2. Setting up the Proxmox node (Ansible)](#2-setting-up-the-proxmox-node-ansible)
- [3. Building VM images (Packer)](#3-building-vm-images-packer)
- [4. Creating and destroying VMs (OpenTofu + Ansible)](#4-creating-and-destroying-vms-opentofu--ansible)
  - [How a VM is declared](#how-a-vm-is-declared)
  - [Creating a new VM](#creating-a-new-vm)
  - [Snapshots](#snapshots)
  - [Reconciling DNS for everything](#reconciling-dns-for-everything)

## 1. Setting up this repo

### Tools

Install (e.g. via `brew`): `just`, `opentofu`, `packer`, `tflint`. `ansible` runs from a
project-local venv (see below), so only `python3` needs to be present globally.

### Secrets

```
cp .env.example .env
```

Fill in the two values — both are the password for the `gigu@pam` Proxmox API user:
- `PROXMOX_VE_PASSWORD` — used by OpenTofu's `bpg/proxmox` provider
- `PKR_VAR_proxmox_password` — used by Packer

`just` loads `.env` automatically before every target (`set dotenv-load := true` in the
`Justfile`). `.env` is gitignored — never commit it.

You'll also need:
- `~/.ssh/id_rsa` — the SSH key used for **root** access to `chuebel` (node provisioning,
  referenced from `config/inventory/hosts`)
- `config/vault-password` — the Ansible Vault password file (gitignored).

`keys/gigu.pub` is already committed — it's the **public** key OpenTofu hands to cloud-init
so the `gigu` user can log into every VM it creates.

### OpenTofu

```
just infra-init
```

Initialises the `bpg/proxmox` provider. State is local (`infra/terraform.tfstate`, gitignored).

### Packer

```
just images-init
```

Initialises the `proxmox-iso` builder plugin for `images/debian-base-13`.

### Ansible

Ansible runs from a project-local venv at `config/venv`:

```
just config-init
```

Bootstraps the venv, Python deps, and Galaxy roles/collections — see the recipe in the
`Justfile` for the exact steps. Safe to re-run.

At this point `just --list` should show every target grouped by tool (`images`, `infra`,
`config`, `snapshots`, `lifecycle`) — you're ready to go.

## 2. Setting up the Proxmox node (Ansible)

`chuebel` itself — packages, NTP, the LVM-thin storage pool, and the Proxmox VE
install/cluster/ACL config (via the `lae.proxmox` Galaxy role) — is owned by Ansible, entry
point `config/proxmox.yml`:

```
just config-proxmox
```

This is **idempotent and safe to re-run**: the node is already live in this exact
configuration (Ansible adopted existing state rather than reinstalling anything), so a normal
run converges with only the couple of expected items (apt repo housekeeping, the
`proxmoxlib.js` subscription-nag patch reasserting itself). To preview without changing
anything:

```
cd config && venv/bin/ansible-playbook proxmox.yml --check --diff
```

A clean `--check --diff` (no unexpected diff) is the sign the node hasn't drifted from what's
declared here.

**Node networking is handled separately and deliberately** — `config/playbooks/networking.yml`
rewrites `/etc/network/interfaces`, which can sever the SSH connection to the node mid-apply if
something's wrong. It is intentionally **not** wired into `proxmox.yml`/`site.yml`. Run it only
when the network topology actually changes, with console/out-of-band access to `chuebel`
confirmed first:

```
just config-networking
```

## 3. Building VM images (Packer)

VMs are cloned from a Proxmox template that Packer builds from a Debian netinst ISO using the
`proxmox-iso` builder. The current template lives in `images/debian-base-13/`.

```
just images-validate          # sanity-check the template + var file
just image                    # build it (default target: debian-base-13)
```

`just image` runs `packer build` against the temporary VM, installs Debian via the preseed
file (`http/preseed.cfg`, served from a raw GitHub URL — see the comment in
`debian-base-13.pkrvars.hcl` for why and what needs to change before this can run from CI),
applies the baseline config (network management left entirely to cloud-init — no DHCP leak),
and converts the result into a Proxmox **template**.

Non-secret build settings (`proxmox_username`, `vm_id`, `iso_url`/`iso_checksum`,
`preseed_url`) live in the committed `*.pkrvars.hcl`; only `PKR_VAR_proxmox_password` comes
from `.env`.

**Result:** a Proxmox template named `debian-base-13` - the clone source every VM definition in `infra/` points at via
`local.template_id` in `infra/locals.tf`. Building a new image version means bumping that
local once the new template is in place; existing VMs aren't touched.

## 4. Creating and destroying VMs (OpenTofu + Ansible)

### How a VM is declared

Every VM gets its own `.tf` file directly in `infra/` (flat structure, shared values in
`infra/locals.tf`) — e.g. [`infra/test01.tf`](infra/test01.tf) is the reference example to copy
when defining a new one. Each VM:
- clones from `local.template_id` (the Packer-built template, see §3)
- gets its static IP/gateway/DNS and the `gigu` user + SSH key via the `initialization`
  (cloud-init) block — no custom snippet files, no in-VM config needed for this to work
- is imported into state with `tofu import`, **never** destroyed-and-recreated to pick up
  spec changes

### Creating a new VM

Always go through `just create-vm`/`destroy-vm` — never `infra-apply-target`/
`infra-destroy-target` directly for a VM — because they also (de)register its DNS entry on
`stinkfisch` in the order that actually works (create registers DNS *after* the VM exists;
destroy deregisters it *before* the VM is destroyed, since DNS is looked up live from the VM
and would otherwise be orphaned). The recipes are thin sequencers — if one half fails, the
output tells you which, so you can fix and re-run just that piece.

1. Copy an existing `.tf` (e.g. `infra/test01.tf`) to `infra/<name>.tf`; adjust `name`,
   `vm_id` (next free one), `tags`, and the static `ip_config` address (next free IP in
   `10.130.30.x/24`)
2. `just infra-plan` — review: should propose creating *only* the new VM. Last checkpoint
   before anything is touched
3. `just create-vm <name>` — **produces:** a running VM cloned from the template, reachable
   at its static IP (`ssh gigu@<ip>`), plus a DNS entry on `stinkfisch`
   (`<name>.srv.pfuetze.xyz` resolves forward and reverse) and an auto-discovered entry in
   the dynamic inventory (`ansible-inventory --host <name>`)
4. Spot-check: VM shows as running in the Proxmox UI, `ssh gigu@<ip>` works, and
   `dig <name>.srv.pfuetze.xyz` resolves

To retire one: `just destroy-vm <name>` (deregisters DNS, then destroys the VM), then delete
its `.tf` file.

### Snapshots

Standalone, fully reversible operations against any existing VM (`api_validate_certs: false`
is required for `chuebel`'s self-signed API cert — already wired into `group_vars/vm/vars.yml`
and all three playbooks):

```
just snapshot-create   <name> <snapshot-name>
just snapshot-rollback <name> <snapshot-name>   # also restarts the VM
just snapshot-remove   <name> <snapshot-name>
```

### Reconciling DNS for everything

```
just config-dns-reconcile
```

Idempotent — creates any missing DNS entries for VMs that don't have one yet, leaves existing
ones untouched. Useful after importing a VM that predates this tooling, or to spot-check that
nothing's drifted.
