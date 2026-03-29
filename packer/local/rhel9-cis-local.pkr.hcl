packer {
  required_version = ">= 1.10.0"

  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = ">= 1.1.0"
    }
    ansible = {
      source  = "github.com/hashicorp/ansible"
      version = ">= 1.1.0"
    }
  }
}

locals {
  timestamp  = formatdate("YYYYMMDDhhmmss", timestamp())
  image_name = "${var.image_name_prefix}-${local.timestamp}"

  cloud_init_userdata = <<-EOF
    #cloud-config
    users:
      - name: ${var.ssh_username}
        sudo: ALL=(ALL) NOPASSWD:ALL
        lock_passwd: false
        ssh_authorized_keys:
          - ${trimspace(file(var.ssh_public_key_file))}
    EOF
}

source "qemu" "rhel9_cis_local" {
  iso_url      = var.source_image_path
  iso_checksum = "none"

  disk_image       = true
  use_backing_file = false
  disk_size        = var.disk_size
  format           = "qcow2"
  output_directory = var.output_dir
  vm_name          = "${local.image_name}.qcow2"

  headless    = true
  memory      = var.memory
  cpus        = var.cpus
  accelerator = var.accelerator

  ssh_username         = var.ssh_username
  ssh_private_key_file = var.ssh_private_key_file
  ssh_timeout          = "10m"

  cd_label = "cidata"
  cd_content = {
    "meta-data" = "instance-id: rhel9-cis-build\nlocal-hostname: rhel9-cis-build\n"
    "user-data"  = local.cloud_init_userdata
  }

  boot_wait = var.boot_wait
}

build {
  name    = "rocky9-cis-l2-local"
  sources = ["source.qemu.rhel9_cis_local"]

  provisioner "ansible" {
    playbook_file = "${path.root}/../../ansible/playbook.yml"

    galaxy_file          = "${path.root}/../../ansible/requirements.yml"
    galaxy_force_install = true

    ansible_env_vars = [
      "ANSIBLE_ROLES_PATH=${path.root}/../../ansible/roles",
      "ANSIBLE_COLLECTIONS_PATH=${path.root}/../../ansible/collections",
      "ANSIBLE_HOST_KEY_CHECKING=False",
      "ANSIBLE_SSH_ARGS=-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null",
    ]

    extra_arguments = [
      "--extra-vars", "@${path.root}/../../ansible/group_vars/all/cis.yml",
      "-v",
    ]
  }

  post-processor "manifest" {
    output     = "manifest-local.json"
    strip_path = true
  }
}
