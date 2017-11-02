variable "pool" {
  type = "string"
  description = "pool to be used to store all the volumes"
}

variable "base_volume_id" {
  type = "string"
  description = "id of the base volume to use"
}

variable "caasp_admin_memory" {
  type = "string"
  description = "The amount of RAM for a admin node"
}

variable "caasp_admin_vcpu" {
  type = "string"
  description = "The amount of virtual CPUs for a admin node"
}

variable "caasp_domain_name" {
  type        = "string"
  description = "The default domain name"
}

variable "network_id" {
  type = "string"
  description = "The ID of the libvirt network to use"
}

variable "caasp_net_network" {
  type        = "string"
  description = "Network used by the caasp cluster"
}

variable "kubic_salt_dir" {
  type = "string"
  description = "Path to the directory where https://github.com/kubic-project/salt/ has been cloned into"
}

variable "kubic_velum_dir" {
  type = "string"
  description = "Path to the directory where https://github.com/kubic-project/velum has been cloned into"
}

variable "devel_scripts_dir" {
  type = "string"
  description = "Path to the directory where the development scripts are located"
}

variable "docker_images_dir" {
  type = "string"
  description = "Path to the directory where the development docker images are located"
}

variable "modified_container_manifests_dir" {
  type = "string"
  description = "Path to the directory where the modified container manifests are located"
}
