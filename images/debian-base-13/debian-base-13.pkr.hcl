packer {
  required_plugins {
    proxmox = {
      version = ">= 1.1.3"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

variable "proxmox_url" {
  type    = string
  default = "https://10.130.10.10:8006/api2/json"
}

variable "proxmox_username" {
  type = string
}

variable "proxmox_password" {
  type      = string
  sensitive = true
}

variable "proxmox_node" {
  type    = string
  default = "chuebel"
}

variable "vm_id" {
  type = number
}

variable "iso_url" {
  type = string
}

variable "iso_checksum" {
  type = string
}

variable "preseed_url" {
  type    = string
  default = "http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed.cfg"
}

source "proxmox-iso" "debian-base" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  password                 = var.proxmox_password
  insecure_skip_tls_verify = true
  node                     = var.proxmox_node

  vm_id   = var.vm_id
  vm_name = "debian-base-13"
  tags    = "template;debian"

  boot_iso {
    iso_url          = var.iso_url
    iso_checksum     = var.iso_checksum
    iso_storage_pool = "dir_storage"
    unmount          = true
  }

  os              = "l26"
  cpu_type        = "host"
  cores           = 2
  memory          = 2048
  scsi_controller = "virtio-scsi-pci"

  disks {
    disk_size    = "5G"
    storage_pool = "vm_storage"
    type         = "scsi"
    ssd          = true
    discard      = true
  }

  network_adapters {
    bridge   = "vmbr300"
    model    = "virtio"
    firewall = false
  }

  cloud_init              = true
  cloud_init_storage_pool = "vm_storage"

  http_directory = "http"

  boot_wait = "10s"
  boot_command = [
    "<esc><wait>",
    "auto url=${var.preseed_url} DEBIAN_FRONTEND=noninteractive net.ifnames=0 biosdevname=0 hostname=debian-base domain=local<enter>"
  ]

  ssh_username           = "root"
  ssh_password           = "packer"
  ssh_timeout            = "20m"
  ssh_handshake_attempts = 50
}

build {
  name    = "debian-base"
  sources = ["source.proxmox-iso.debian-base"]

  provisioner "shell" {
    inline = [
      "apt-get update",
      "DEBIAN_FRONTEND=noninteractive apt-get install -y cloud-init qemu-guest-agent locales",
      "echo 'de_CH.UTF-8 UTF-8' >> /etc/locale.gen && locale-gen",
      "systemctl enable qemu-guest-agent",
      "cloud-init clean",
      "truncate -s 0 /etc/machine-id",
      "rm -f /var/lib/dbus/machine-id",
      "ln -s /etc/machine-id /var/lib/dbus/machine-id",
      "rm -f /etc/ssh/ssh_host_*",
      "rm -f /etc/ssh/sshd_config.d/packer.conf",
      "passwd -l root",
      "truncate -s 0 /root/.bash_history",
      "sync",
    ]
  }
}