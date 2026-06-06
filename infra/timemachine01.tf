resource "proxmox_virtual_environment_vm" "timemachine01" {
  name      = "timemachine01"
  node_name = local.proxmox_node
  vm_id     = 104
  tags      = ["debian"]
  on_boot   = true

  agent {
    enabled = true
    timeout = "15m"
    trim    = false
    type    = "virtio"
  }

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

  initialization {
    datastore_id = "vm_storage"
    interface    = "ide2"
    upgrade      = true

    dns {
      domain  = local.dns_domain
      servers = local.dns_servers
    }

    ip_config {
      ipv4 {
        address = "10.130.30.111/24"
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
  }

  usb {
    host = "4-1"
    usb3 = true
  }

  operating_system {}

  serial_device {
    device = "socket"
  }

  lifecycle {
    ignore_changes = [operating_system]
  }
}