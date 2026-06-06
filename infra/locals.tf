locals {
  proxmox_node   = "chuebel"
  template_id    = 9002
  ssh_public_key = file("${path.root}/../keys/gigu.pub")
}