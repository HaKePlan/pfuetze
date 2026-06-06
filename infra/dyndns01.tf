resource "proxmox_virtual_environment_vm" "dyndns01" {
  name      = "dyndns01"
  node_name = local.proxmox_node
  vm_id     = 103
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
    dedicated = 2048
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
        address = "10.130.30.112/24"
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

  operating_system {}

  serial_device {
    device = "socket"
  }

  lifecycle {
    ignore_changes = [operating_system]
  }
}
