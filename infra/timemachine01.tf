resource "proxmox_virtual_environment_vm" "timemachine01" {
  name      = "timemachine01"
  node_name = local.proxmox_node
  vm_id     = 104

  cpu {
    cores = 2
  }

  memory {
    dedicated = 4096
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
