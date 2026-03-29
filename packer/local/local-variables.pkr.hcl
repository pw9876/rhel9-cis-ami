variable "source_image_path" {
  type        = string
  description = "Path to the RHEL 9 KVM guest image (QCOW2) to use as the build source."
}

variable "ssh_public_key_file" {
  type        = string
  description = "Path to the SSH public key file to inject via cloud-init."
}

variable "ssh_private_key_file" {
  type        = string
  description = "Path to the SSH private key file Packer will use to connect."
}

variable "ssh_username" {
  type        = string
  description = "SSH username present in the cloud image."
  default     = "rocky"
}

variable "image_name_prefix" {
  type        = string
  description = "Prefix for the output image filename."
  default     = "rocky9-cis-l2-local"
}

variable "output_dir" {
  type        = string
  description = "Directory to write the finished QCOW2 image to."
  default     = "output-local"
}

variable "disk_size" {
  type        = number
  description = "Output disk size in megabytes."
  default     = 20480
}

variable "memory" {
  type        = number
  description = "RAM to allocate to the build VM, in megabytes."
  default     = 2048
}

variable "cpus" {
  type        = number
  description = "Number of vCPUs to allocate to the build VM."
  default     = 2
}

variable "accelerator" {
  type        = string
  description = "QEMU accelerator: 'kvm' on Linux, 'hvf' on macOS."
  default     = "kvm"
}

variable "boot_wait" {
  type        = string
  description = "Time to wait after VM boot before Packer attempts SSH."
  default     = "10s"
}
