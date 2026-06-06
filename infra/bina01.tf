resource "proxmox_virtual_environment_vm" "bina01" {
  name      = "bina01"
  node_name = local.proxmox_node
  vm_id     = 102

  cpu {
    cores = 4
  }

  memory {
    dedicated = 8192
  }

  disk {
    datastore_id = "vm_storage"
    size         = 150
    interface    = "scsi0"
  }

  network_device {
    bridge = "vmbr300"
  }
}
