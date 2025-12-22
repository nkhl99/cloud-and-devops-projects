packer {
  required_plugins {
    googlecompute = {
      source  = "github.com/hashicorp/googlecompute"
      version = "~> 1"
    }
    ansible = {
      source  = "github.com/hashicorp/ansible"
      version = "~> 1"
    }
  }
}

variable "project_id" {
  type    = string
  default = "project1-478711" # We will move this to a var file later
}

variable "zone" {
  type    = string
  default = "us-central1-a"
}

source "googlecompute" "hardened_web" {
  project_id          = var.project_id
  source_image_family = "ubuntu-2204-lts"
  zone                = var.zone
  disk_size           = 20          # GCP Free tier allows up to 30GB, we use 20GB to be safe
  machine_type        = "e2-medium" # Faster build, cheap for short duration
  ssh_username        = "packer"

  # image_name is what shows up in your GCP Console
  image_name   = "hardened-web-v{{timestamp}}"
  image_family = "hardened-web-server"
}

build {
  sources = ["source.googlecompute.hardened_web"]

  # STEP 1: The Shell Provisioner
  # When a Linux VM boots, it runs background tasks called "cloud-init".
  # If we try to install software while cloud-init is running, we get "Locked" errors.
  # This script just says: "Wait until the OS is fully awake before we start."
  provisioner "shell" {
    inline = [
      "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do sleep 1; done",
    ]
  }

  # STEP 2: The Ansible Provisioner
  # Now that the VM is ready, we hand control over to Ansible.
  # Packer acts as the "driver", telling Ansible: "Here is the VM IP, go configure it."
  provisioner "ansible" {
    playbook_file = "./ansible/playbook.yml"
    use_proxy     = false # specific fix for GCP connection issues
    user          = "packer"
    extra_arguments = [
      "--scp-extra-args", "'-O'" # Fixes SCP errors on some newer SSH versions
    ]
  }
}