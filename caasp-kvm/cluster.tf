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
resource "libvirt_volume" "admin" {
  name           = "caasp_admin.qcow2"
  pool           = "${var.pool}"
  base_volume_id = "${libvirt_volume.caasp_img.id}"
}

resource "libvirt_cloudinit" "admin" {
  name      = "caasp_admin_cloud_init.iso"
  pool      = "${var.pool}"
  user_data = "${file("cloud-init/admin.cfg")}"
}

resource "libvirt_domain" "admin" {
  name      = "caasp_admin"
  memory    = "${var.caasp_admin_memory}"
  vcpu      = "${var.caasp_admin_vcpu}"
  metadata   = "caasp-admin.${var.caasp_domain_name},admin,${count.index}"
  cloudinit = "${libvirt_cloudinit.admin.id}"

  disk {
    volume_id = "${libvirt_volume.admin.id}"
  }

  network_interface {
    network_id     = "${libvirt_network.network.id}"
    hostname       = "caasp-admin"
    addresses      = ["${cidrhost("${var.caasp_net_network}", 256)}"]
    wait_for_lease = 1
  }

  graphics {
    type        = "vnc"
    listen_type = "address"
  }

  filesystem {
    source = "${var.kubic_salt_dir}"
    target = "salt"
    readonly = true
  }

  filesystem {
    source = "${path.module}/injected-caasp-container-manifests"
    target = "caasp-container-manifests"
    readonly = true
  }

  filesystem {
    source = "${var.kubic_velum_dir}"
    target = "velum"
    readonly = true
  }

  filesystem {
    source = "${path.module}/resources/scripts"
    target = "devel-scripts"
    readonly = true
  }

  filesystem {
    source = "${path.module}/resources/docker-images"
    target = "devel-docker-images"
    readonly = true
  }

  connection {
    type     = "ssh"
    user     = "root"
    password = "linux"
  }

  provisioner "remote-exec" {
    inline = [
      "while [[ ! -f /var/run/docker.pid ]]; do echo waiting for docker to start; sleep 1; done",
      "docker load -i /var/lib/misc/devel-docker-images/*.tar",
    ]
  }

  provisioner "remote-exec" {
    inline = [
      "for i in `ls -1 /opt/bin/autorun*.sh /opt/bin/autorun*/*.sh` ; do sh $i ; done",
    ]
  }
}

output "ip_admin" {
  value = "${libvirt_domain.admin.network_interface.0.addresses.0}"
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
    admin_ip = "${libvirt_domain.admin.network_interface.0.addresses.0}"
  }

  depends_on = ["libvirt_domain.admin"]
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
  depends_on = ["libvirt_domain.admin"]

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
    admin_ip = "${libvirt_domain.admin.network_interface.0.addresses.0}"
  }

  depends_on = ["libvirt_domain.admin"]
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
  depends_on = ["libvirt_domain.admin"]

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
