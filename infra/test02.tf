resource "proxmox_virtual_environment_vm" "test02" {
  name      = "test02"
  node_name = local.proxmox_node

  clone {
    vm_id = local.template_id
  }

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = "vm_storage"
    size         = 5
    interface    = "scsi0"
    file_format  = "raw"
    discard      = "on"
    iothread     = true
  }

  initialization {
    ip_config {
      ipv4 {
        address = "10.130.30.199/24"
        gateway = "10.130.30.1"
      }
    }
    user_account {
      username = "gigu"
      keys     = [local.ssh_public_key]
    }
  }

  network_device {
    bridge = "vmbr300"
    model  = "virtio"
  }
}
