resource "libvirt_volume" "admin" {
  name           = "caasp_admin.qcow2"
  pool           = "${var.pool}"
  base_volume_id = "${var.base_volume_id}"
}

resource "libvirt_cloudinit" "admin" {
  name      = "caasp_admin_cloud_init.iso"
  pool      = "${var.pool}"
  user_data = "${file("cloud-init/admin.cfg")}"
}
