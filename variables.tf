variable "name" {
  description = "Name of the vm"
  type = string
}

variable "network_port" {
  description = "Network port to assign to the node. Should be of type openstack_networking_port_v2"
  type        = any
}

variable "server_group" {
  description = "Server group to assign to the node. Should be of type openstack_compute_servergroup_v2"
  type        = any
}

variable "image_id" {
    description = "ID of the vm image used to provision the node"
    type = string
}

variable "flavor_id" {
  description = "ID of the VM flavor"
  type = string
}

variable "keypair_name" {
  description = "Name of the keypair that will be used by admins to ssh to the node"
  type = string
}

variable "ssh_host_key_rsa" {
  type = object({
    public = string
    private = string
  })
  default = {
    public = ""
    private = ""
  }
}

variable "ssh_host_key_ecdsa" {
  type = object({
    public = string
    private = string
  })
  default = {
    public = ""
    private = ""
  }
}

variable "kubernetes" {
  type = object({
    nameserver_ips = list(string)
    domain = string
    masters = object({
      max_count = number
      api_timeout = string
      api_port = number
      max_api_connections = number
    })
    workers = object({
      max_count = number
      ingress_http_timeout = string
      ingress_http_port = number
      ingress_max_http_connections = number
      ingress_https_timeout = string
      ingress_https_port = number
      ingress_max_https_connections = number
    })
  })
}

variable "tunnel" {
  description = "Setting for restricting the bastion access via an ssh tunnel only"
  type = object({
    enabled = bool
    ssh = object({
      user = string
      authorized_key = string
    })
  })
  default = {
    enabled = false
    ssh = {
      user = ""
      authorized_key = ""
    }
  }
}

variable "chrony" {
  description = "Chrony configuration for ntp. If enabled, chrony is installed and configured, else the default image ntp settings are kept"
  type        = object({
    enabled = bool,
    //https://chrony.tuxfamily.org/doc/4.2/chrony.conf.html#server
    servers = list(object({
      url = string,
      options = list(string)
    })),
    //https://chrony.tuxfamily.org/doc/4.2/chrony.conf.html#pool
    pools = list(object({
      url = string,
      options = list(string)
    })),
    //https://chrony.tuxfamily.org/doc/4.2/chrony.conf.html#makestep
    makestep = object({
      threshold = number,
      limit = number
    })
  })
  default = {
    enabled = false
    servers = []
    pools = []
    makestep = {
      threshold = 0,
      limit = 0
    }
  }
}



variable "domain" {
  description = "Domain that should give the ips of the workers on the 'workers' subdomain and the ip of the masters on the 'masters' subdomain"
  type        = string
}

variable "nameserver_ips" {
  description = "Ips of explicit nameservers that will resolve the elasticsearch domain. Can be left empty if the implicit network servers already do this."
  type = list(string)
  default = []
}

variable "is_master" {
  description = "Whether or not the vm is a master"
  type        = bool
  default     = false
}

variable "initial_masters" {
  description = "List of host names for the initial masters to bootstrap the cluster. Should be empty when joining a pre-existing cluster"
  type        = list(string)
}

variable "tls_enabled" {
  description = "Whether es should be setup to server requests over tls"
  type = bool
  default = true
}

variable "ca" {
  description = "The ca that will sign the es certificates. Should have the following keys: key, key_algorithm, certificate"
  type = object({
    key = string
    key_algorithm = string
    certificate = string
  })
  sensitive = true
  default = {
    key = ""
    key_algorithm = ""
    certificate = ""
  }
}

variable "server_certificate" {
  description = "Parameters of the server's certificate. Should contain the following keys: organization, validity_period, early_renewal_period, key_length"
  type = object({
    organization = string
    validity_period = number
    early_renewal_period = number
  })
  default = {
    organization = "Ferlab"
    validity_period = 100*365*24
    early_renewal_period = 365*24
  }
}

