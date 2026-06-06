resource "proxmox_virtual_environment_vm" "bina01" {
  name      = "bina01"
  node_name = local.proxmox_node
  vm_id     = 102
  tags      = ["debian", "docker"]
  on_boot   = true

  agent {
    enabled = true
    timeout = "15m"
    trim    = false
    type    = "virtio"
  }

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
        address = "10.130.30.102/24"
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