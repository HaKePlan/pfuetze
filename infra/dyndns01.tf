resource "proxmox_virtual_environment_vm" "dyndns01" {
  name      = "dyndns01"
  node_name = local.proxmox_node
  vm_id     = 103

  cpu {
    cores = 2
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = "vm_storage"
    size         = 5
    interface    = "scsi0"
  }

  network_device {
    bridge = "vmbr300"
  }
}
