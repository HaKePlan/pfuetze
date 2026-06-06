provider "proxmox" {
  # password from env: PROXMOX_VE_PASSWORD
  username = "gigu@pam"
  endpoint = "https://10.130.10.10:8006/"
  insecure = true

  ssh {
    agent    = true
    username = "root"
  }
}
