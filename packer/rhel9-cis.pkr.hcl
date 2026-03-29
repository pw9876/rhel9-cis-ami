packer {
  required_version = ">= 1.10.0"

  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = ">= 1.3.0"
    }
  }
}

locals {
  timestamp = formatdate("YYYYMMDDhhmmss", timestamp())
  ami_name  = "${var.ami_name_prefix}-${local.timestamp}"

  base_tags = {
    Name      = local.ami_name
    OS        = "Rocky9"
    CISLevel  = "2"
    ManagedBy = "packer"
    BuildDate = formatdate("YYYY-MM-DD", timestamp())
  }

  all_tags = merge(local.base_tags, var.tags)
}

data "amazon-ami" "rocky9" {
  region = var.aws_region

  filters = {
    name                = "Rocky-9-EC2-Base-9.*-x86_64*"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
    architecture        = "x86_64"
    state               = "available"
  }

  owners      = ["792107900819"]
  most_recent = true
}

source "amazon-ebs" "rocky9_cis" {
  region        = var.aws_region
  instance_type = var.instance_type

  source_ami = data.amazon-ami.rocky9.id

  ssh_username = "rocky"
  ssh_timeout  = "10m"

  ami_name        = local.ami_name
  ami_description = "CIS Level 2 hardened Rocky Linux 9 AMI built by Packer"

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

  run_tags        = local.all_tags
  run_volume_tags = local.all_tags
  snapshot_tags   = local.all_tags
  tags            = local.all_tags

  # Ensure the instance is fully stopped before creating the AMI
  shutdown_behavior = "stop"
}

build {
  name    = "rocky9-cis-l2"
  sources = ["source.amazon-ebs.rocky9_cis"]

  provisioner "shell" {
    script          = "${path.root}/../scripts/harden.sh"
    execute_command = "sudo bash '{{.Path}}'"
  }

  post-processor "manifest" {
    output     = "manifest.json"
    strip_path = true
  }
}
