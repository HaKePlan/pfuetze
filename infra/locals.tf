locals {
  proxmox_node   = "chuebel"
  template_id    = 9002
  ssh_public_key = file("${path.root}/../keys/gigu.pub")
  dns_domain     = "srv.pfuetze.xyz"
  dns_servers    = ["10.130.2.1"]
}