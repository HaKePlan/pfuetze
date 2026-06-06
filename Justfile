# pfuetze — homelab infrastructure
# Usage: just <target>
# Requires: just, opentofu, packer, ansible

set dotenv-load := true
set dotenv-filename := ".env"

# show available targets
default:
    @just --list

# ── images (packer) ──────────────────────────────────────────────────────────

# build a VM image template (default: debian-base)
images target="debian-base":
    cd images/{{target}} && packer init . && packer build -var-file={{target}}.pkrvars.hcl .
