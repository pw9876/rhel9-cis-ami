packer {
  required_version = ">= 1.10.0"

  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = ">= 1.3.0"
    }
    ansible = {
      source  = "github.com/hashicorp/ansible"
      version = ">= 1.1.0"
    }
  }
}

locals {
  timestamp = formatdate("YYYYMMDDhhmmss", timestamp())
  ami_name  = "${var.ami_name_prefix}-${local.timestamp}"

  base_tags = {
    Name        = local.ami_name
    OS          = "RHEL9"
    CISLevel    = "2"
    ManagedBy   = "packer"
    BuildDate   = formatdate("YYYY-MM-DD", timestamp())
  }

  all_tags = merge(local.base_tags, var.tags)
}

data "amazon-ami" "rhel9" {
  region = var.aws_region

  filters = {
    name                = "RHEL-9.*_HVM-*-x86_64-*-Hourly2-GP3"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
    architecture        = "x86_64"
    state               = "available"
  }

  owners      = ["309956199498"]
  most_recent = true
}

source "amazon-ebs" "rhel9_cis" {
  region        = var.aws_region
  instance_type = var.instance_type

  source_ami = data.amazon-ami.rhel9.id

  ssh_username = "ec2-user"
  ssh_timeout  = "10m"

  ami_name        = local.ami_name
  ami_description = "CIS Level 2 hardened RHEL 9 AMI built by Packer"

  ami_regions = var.ami_regions

  dynamic "ami_block_device_mappings" {
    for_each = var.kms_key_id != "" ? [1] : []
    content {
      device_name           = "/dev/sda1"
      volume_size           = 20
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
      kms_key_id            = var.kms_key_id
    }
  }

  dynamic "ami_block_device_mappings" {
    for_each = var.kms_key_id == "" ? [1] : []
    content {
      device_name           = "/dev/sda1"
      volume_size           = 20
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
    }
  }

  dynamic "vpc_filter" {
    for_each = var.vpc_id == "" ? [1] : []
    content {
      filters = {
        "isDefault" = "true"
      }
    }
  }

  vpc_id    = var.vpc_id != "" ? var.vpc_id : null
  subnet_id = var.subnet_id != "" ? var.subnet_id : null

  associate_public_ip_address = var.associate_public_ip

  run_tags          = local.all_tags
  run_volume_tags   = local.all_tags
  snapshot_tags     = local.all_tags
  tags              = local.all_tags

  # Ensure the instance is fully stopped before creating the AMI
  shutdown_behavior = "stop"
}

build {
  name    = "rhel9-cis-l2"
  sources = ["source.amazon-ebs.rhel9_cis"]

  provisioner "ansible" {
    playbook_file = "${path.root}/../ansible/playbook.yml"

    galaxy_file             = "${path.root}/../ansible/requirements.yml"
    galaxy_force_install    = true

    ansible_env_vars = [
      "ANSIBLE_ROLES_PATH=${path.root}/../ansible/roles",
      "ANSIBLE_COLLECTIONS_PATH=${path.root}/../ansible/collections",
      "ANSIBLE_HOST_KEY_CHECKING=False",
      "ANSIBLE_SSH_ARGS=-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null",
    ]

    extra_arguments = [
      "--extra-vars", "@${path.root}/../ansible/group_vars/all/cis.yml",
      "-v",
    ]
  }

  post-processor "manifest" {
    output     = "manifest.json"
    strip_path = true
  }
}
