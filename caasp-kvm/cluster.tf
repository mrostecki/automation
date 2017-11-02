#####################
# libvirt variables #
#####################

variable "libvirt_uri" {
  default     = "qemu:///system"
  description = "libvirt connection url - default to localhost"
}

variable "pool" {
  default     = "default"
  description = "pool to be used to store all the volumes"
}

#####################
# Cluster variables #
#####################

variable "caasp_img_source_url" {
  type        = "string"
  default     = "channel://devel"
  description = "CaaSP image to use for KVM - you can use 'http://', 'file://' or 'channel://' formatted addresses. 'http' and 'file' point to remote http, and local images on disk, while 'channel' refers to the release channel from IBS. e.g. 'channel://devel' will download the latest image from the devel channel. Currently supported channels are: devel, staging_a, staging_b, and release"
}

variable "caasp_admin_memory" {
  default     = 4096
  description = "The amount of RAM for a admin node"
}

variable "caasp_admin_vcpu" {
  default     = 4
  description = "The amount of virtual CPUs for a admin node"
}

variable "caasp_master_count" {
  default     = 1
  description = "Number of masters to be created"
}

variable "caasp_master_memory" {
  default     = 2048
  description = "The amount of RAM for a master"
}

variable "caasp_master_vcpu" {
  default     = 2
  description = "The amount of virtual CPUs for a master"
}

variable "caasp_worker_count" {
  default     = 2
  description = "Number of workers to be created"
}

variable "caasp_worker_memory" {
  default     = 2048
  description = "The amount of RAM for a worker"
}

variable "caasp_worker_vcpu" {
  default     = 2
  description = "The amount of virtual CPUs for a worker"
}

variable "caasp_domain_name" {
  type        = "string"
  default     = "devenv.caasp.suse.net"
  description = "The default domain name"
}

variable "caasp_net_mode" {
  type        = "string"
  default     = "nat"
  description = "Network mode used by the caasp cluster"
}

variable "caasp_net_network" {
  type        = "string"
  default     = "10.17.0.0/22"
  description = "Network used by the caasp cluster"
}

####################
# DevEnv variables #
####################

variable "kubic_salt_dir" {
  type = "string"
  description = "Path to the directory where https://github.com/kubic-project/salt/ has been cloned into"
}

variable "kubic_velum_dir" {
  type = "string"
  description = "Path to the directory where https://github.com/kubic-project/velum has been cloned into"
}

#######################
# Cluster declaration #
#######################

provider "libvirt" {
  uri = "${var.libvirt_uri}"
}

# This is the CaaSP kvm image that has been created by IBS
resource "libvirt_volume" "caasp_img" {
  name   = "${basename(var.caasp_img_source_url)}"
  source = "../downloads/kvm-${basename(var.caasp_img_source_url)}"
  pool   = "${var.pool}"
}

##############
# Networking #
##############
resource "libvirt_network" "network" {
    name      = "caasp-net"
    mode      = "${var.caasp_net_mode}"
    domain    = "${var.caasp_domain_name}"
    addresses = ["${var.caasp_net_network}"]
}

##############
# Admin node #
##############

module "admin" {
  source                           = "./tf-modules/admin-node"
  pool                             = "${var.pool}"
  base_volume_id                   = "${libvirt_volume.caasp_img.id}"
  caasp_admin_memory               = "${var.caasp_admin_memory}"
  caasp_admin_vcpu                 = "${var.caasp_admin_vcpu}"
  caasp_domain_name                = "${var.caasp_domain_name}"
  network_id                       = "${libvirt_network.network.id}"
  caasp_net_network                = "${var.caasp_net_network}"
  kubic_velum_dir                  = "${var.kubic_velum_dir}"
  kubic_salt_dir                   = "${var.kubic_salt_dir}"
  docker_images_dir                = "${path.module}/resources/docker-images"
  modified_container_manifests_dir = "${path.module}/injected-caasp-container-manifests"
  devel_scripts_dir                = "${path.module}/resources/scripts"
}

output "ip_admin" {
  value = "${module.admin.ip}"
}

###################
# Cluster masters #
###################

resource "libvirt_volume" "master" {
  name           = "caasp_master_${count.index}.qcow2"
  pool           = "${var.pool}"
  base_volume_id = "${libvirt_volume.caasp_img.id}"
  count          = "${var.caasp_master_count}"
}

data "template_file" "master_cloud_init_user_data" {
  # needed when 0 master nodes are defined
  count    = "${var.caasp_master_count}"
  template = "${file("cloud-init/master.cfg.tpl")}"

  vars {
    admin_ip = "${module.admin.ip}"
  }

  depends_on = ["module.admin"]
}

resource "libvirt_cloudinit" "master" {
  # needed when 0 master nodes are defined
  count     = "${var.caasp_master_count}"
  name      = "caasp_master_cloud_init_${count.index}.iso"
  pool      = "${var.pool}"
  user_data = "${element(data.template_file.master_cloud_init_user_data.*.rendered, count.index)}"
}

resource "libvirt_domain" "master" {
  count      = "${var.caasp_master_count}"
  name       = "caasp_master_${count.index}"
  memory     = "${var.caasp_master_memory}"
  vcpu       = "${var.caasp_master_vcpu}"
  cloudinit  = "${element(libvirt_cloudinit.master.*.id, count.index)}"
  metadata   = "caasp-master-${count.index}.${var.caasp_domain_name},master,${count.index}"
  depends_on = ["module.admin"]

  disk {
    volume_id = "${element(libvirt_volume.master.*.id, count.index)}"
  }

  network_interface {
    network_id     = "${libvirt_network.network.id}"
    hostname       = "caasp-master-${count.index}"
    addresses      = ["${cidrhost("${var.caasp_net_network}", 512 + count.index)}"]
    wait_for_lease = 1
  }

  graphics {
    type        = "vnc"
    listen_type = "address"
  }

  connection {
    type     = "ssh"
    user     = "root"
    password = "linux"
  }

  # This ensures the VM is booted and SSH'able
  provisioner "remote-exec" {
    inline = [
      "sleep 1"
    ]
  }
}

output "masters" {
  value = ["${libvirt_domain.master.*.network_interface.0.addresses.0}"]
}

###################
# Cluster workers #
###################

resource "libvirt_volume" "worker" {
  name           = "caasp_worker_${count.index}.qcow2"
  pool           = "${var.pool}"
  base_volume_id = "${libvirt_volume.caasp_img.id}"
  count          = "${var.caasp_worker_count}"
}

data "template_file" "worker_cloud_init_user_data" {
  # needed when 0 worker nodes are defined
  count    = "${var.caasp_worker_count}"
  template = "${file("cloud-init/worker.cfg.tpl")}"

  vars {
    admin_ip = "${module.admin.ip}"
  }

  depends_on = ["module.admin"]
}

resource "libvirt_cloudinit" "worker" {
  # needed when 0 worker nodes are defined
  count     = "${var.caasp_worker_count}"
  name      = "caasp_worker_cloud_init_${count.index}.iso"
  pool      = "${var.pool}"
  user_data = "${element(data.template_file.worker_cloud_init_user_data.*.rendered, count.index)}"
}

resource "libvirt_domain" "worker" {
  count      = "${var.caasp_worker_count}"
  name       = "caasp_worker_${count.index}"
  memory     = "${var.caasp_worker_memory}"
  vcpu       = "${var.caasp_worker_vcpu}"
  cloudinit  = "${element(libvirt_cloudinit.worker.*.id, count.index)}"
  metadata   = "caasp-worker-${count.index}.${var.caasp_domain_name},worker,${count.index}"
  depends_on = ["module.admin"]

  disk {
    volume_id = "${element(libvirt_volume.worker.*.id, count.index)}"
  }

  network_interface {
    network_id     = "${libvirt_network.network.id}"
    hostname       = "caasp-worker-${count.index}"
    addresses      = ["${cidrhost("${var.caasp_net_network}", 768 + count.index)}"]
    wait_for_lease = 1
  }

  graphics {
    type        = "vnc"
    listen_type = "address"
  }

  connection {
    type     = "ssh"
    user     = "root"
    password = "linux"
  }

  # This ensures the VM is booted and SSH'able
  provisioner "remote-exec" {
    inline = [
      "sleep 1"
    ]
  }
}

output "workers" {
  value = ["${libvirt_domain.worker.*.network_interface.0.addresses.0}"]
}
