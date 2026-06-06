# Proxmox username. Password is never written to disk — pass it as:
#   PKR_VAR_proxmox_password=xxx  (in .env)
proxmox_username = "gigu@pam"
vm_id            = 9002

# ISO URL and sha256 checksum.
# Get both from: https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/
# (grab the checksum from the SHA256SUMS file next to the ISO)
iso_url      = "https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-13.5.0-amd64-netinst.iso"
iso_checksum = "sha256:95838884f5ea6c82421dfe6baaa5a639dbbe6756c1e380f9fe7a7cb0c1949d2a"

# Override default preseed URL (Packer built-in HTTP server) with GitHub raw URL.
# Is used for day 0 operations; at one point, we will switch to internal store in the network
preseed_url = "https://raw.githubusercontent.com/HaKePlan/pfuetze/main/images/debian-base-13/http/preseed.cfg"
