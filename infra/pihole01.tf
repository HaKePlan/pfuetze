resource "proxmox_virtual_environment_vm" "pihole01" {
  name      = "pihole01"
  node_name = local.proxmox_node
  vm_id     = 101

  cpu {
    cores = 2
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = "vm_storage"
    size         = 8
    interface    = "scsi0"
  }

  network_device {
    bridge = "vmbr300"
  }
}
