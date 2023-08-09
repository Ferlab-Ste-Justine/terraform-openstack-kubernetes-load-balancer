# About

This terraform module provisions a load balancer for a kubernetes cluster.

Its is a transport-level load-balancer that doesn't perform tls termination, leaving that concern to the downstream kubernetes cluster (presumably via an ingress).

The load balancer currently expects to load balance to the following services:
- The kubernetes api on the masters (port 6443 on the load balancer, customizable port on the masters)
- The http ingress on the workers (port 80 on the load balancer, customizable port on the workers)
- The https ingress on the workers (port 443 on the load balancer, customization port on the workers)

The load balancer also expects external dns servers that it will use to continuously resolve the kubernetes workers and masters ips.

It will furthermore do a basic connection check on the masters and workers for each load-balanced services and it will temporarily prune away the nodes that don't pass the check for each service.

Additionally, the load balancer supports an ssh tunneling setup where it listens only for connections on its local ip (127.0.0.1) and expects remote users to access it via ssh tcp forwarding. In this setup, the ssh permissions of the generated tunnel user are very limited and the user can only tunnel on the server's local ip (127.0.0.1) for the ports the load balancer forwards (6443, 80 and 443).

# Usage

## Input

The module takes the following variables as input:

- **name**: Name of the load balancer vm
- **network_port**: Resource of type **openstack_networking_port_v2** to assign to the vm for network connectivity.
- **server_group**: Server group to assign to the node. Should be of type **openstack_compute_servergroup_v2**.
- **image_source**: Source of the image to provision the bastion on. It takes the following keys (only one of the two fields should be used, the other one should be empty):
  - **image_id**: Id of the image to associate with a vm that has local storage
  - **volume_id**: Id of a volume containing the os to associate with the vm
- **flavor_id**: Id of the VM flavor
- **keypair_name**: Name of the keypair that will be used to ssh to the node by the admin sudo user.
- **kubernetes**: Settings for the kubernetes load balancer. Takes the following properties:
  - **nameserver_ips**: Ips of the nameservers the load balancer will use to resolve kubernetes masters and workers
  - **domain**: Domain for the kubernetes cluster. The **workers** subdomain is expected to resolve to the ips of the workers and the **masters** subdomain is expected to resolve to the ips of the masters.
  - **masters**: Object container the settings for the k8 masters. It has the following properties:
    - **max_count**: Maximum expected possible number of k8 master. Required by haproxy.
    - **api_timeout**: Amount of time a kubernetes api connection can remain idle before the load balancer times it out.
    - **api_port**: Http port of the kubernetes api on the k8 master nodes.
    - **max_api_connections**: Max number of concurrent connections to the kubernetes api the load balancer will allow before it starts refusing further connections.
  - **workers**: Object container the settings for the k8 workers. It has the following properties:
    - **max_count**: Maximum expected possible number of k8 workers. Required by haproxy.
    - **ingress_http_timeout**: Amount of time an ingress http connection can remain idle before the load balancer times it out.
    - **ingress_http_port**: Http port of the ingress on the k8 worker nodes.
    - **ingress_max_http_connections**: Max number of concurrent http connections to the ingress the load balancer will allow before it starts refusing further connections.
    - **ingress_https_timeout**: Amount of time an ingress https connection can remain idle before the load balancer times it out.
    - **ingress_https_port**: Https port of the ingress on the k8 worker nodes.
    - **ingress_max_https_connections**: Max number of concurrent https connections to the ingress the load balancer will allow before it starts refusing further connections.
- **chrony**: Optional chrony configuration for when you need a more fine-grained ntp setup on your vm. It is an object with the following fields:
  - **enabled**: If set the false (the default), chrony will not be installed and the vm ntp settings will be left to default.
  - **servers**: List of ntp servers to sync from with each entry containing two properties, **url** and **options** (see: https://chrony.tuxfamily.org/doc/4.2/chrony.conf.html#server)
  - **pools**: A list of ntp server pools to sync from with each entry containing two properties, **url** and **options** (see: https://chrony.tuxfamily.org/doc/4.2/chrony.conf.html#pool)
  - **makestep**: An object containing remedial instructions if the clock of the vm is significantly out of sync at startup. It is an object containing two properties, **threshold** and **limit** (see: https://chrony.tuxfamily.org/doc/4.2/chrony.conf.html#makestep)
- **tunnel**: Optional ssh tunneling parameter. It is an object with the following fields:
  - **enabled**: Boolean value indicating whether or not ssh tunneling is on. Defaults to false.
  - **ssh**: An object with the following fields:
    - **user**: Os user that remote users should use for ssh tunneling
    - **authorized_key**: Authorized ssh key that the user should be accessible with
- **ssh_host_key_rsa**: Predefined rsa ssh host key. Can be omitted if random value is acceptable. It is an object with the following fields:
  - **public**: Public part of the ssh key, in "authorized keys" format.
  - **private**: Private part of the ssh key, in openssh pem format.
- **ssh_host_key_ecdsa**: Predefined ecdsa ssh host key. Can be omitted if random value is acceptable. It is an object with the following fields:
  - **public**: Public part of the ssh key, in "authorized keys" format.
  - **private**: Private part of the ssh key, in openssh pem format.

## Example

```
locals {
  k8_masters_count = 3
  k8_workers_count = 3
  k8_lb_tunnel_count = 1
  k8_lb_count = 1
}

resource "openstack_compute_keypair_v2" "k8" {
  name = "myproject-k8"
}

module "k8_security_groups" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-openstack-kubernetes-security-groups.git?ref=v0.1.0"
  namespace = "myproject"
}

resource "tls_private_key" "k8_server_ssh_rsa" {
  algorithm   = "RSA"
  rsa_bits    = 4096
}

resource "tls_private_key" "k8_server_ssh_ecdsa" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P384"
}

resource "tls_private_key" "k8_tunnel_client_ssh" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P384"
}

resource "openstack_compute_servergroup_v2" "k8_masters" {
  name     = "myproject-k8-master"
  policies = ["soft-anti-affinity"]
}

resource "openstack_compute_servergroup_v2" "k8_workers" {
  name     = "myproject-k8-worker"
  policies = ["soft-anti-affinity"]
}

resource "openstack_compute_servergroup_v2" "k8_lb_tunnel" {
  name     = "myproject-k8-lb-tunnel"
  policies = ["soft-anti-affinity"]
}

resource "openstack_compute_servergroup_v2" "k8_lb" {
  name     = "myproject-k8-lb"
  policies = ["soft-anti-affinity"]
}

resource "openstack_networking_port_v2" "k8_workers" {
  count              = local.k8_masters_count
  name               = "myproject-k8-workers-${count.index + 1}"
  network_id         = module.reference_infra.networks.internal.id
  security_group_ids = [
    module.k8_security_groups.groups.worker.id,
  ]
  admin_state_up     = true
}

resource "openstack_networking_port_v2" "k8_masters" {
  count              = local.k8_workers_count
  name               = "myproject-k8-masters-${count.index + 1}"
  network_id         = module.reference_infra.networks.internal.id
  security_group_ids = [module.k8_security_groups.groups.master.id]
  admin_state_up     = true
}

resource "openstack_networking_port_v2" "k8_lb_tunnel" {
  count              = local.k8_lb_tunnel_count
  name               = "myproject-k8-lb-tunnel-${count.index + 1}"
  network_id         = module.reference_infra.networks.internal.id
  security_group_ids = [module.k8_security_groups.groups.load_balancer_tunnel.id]
  admin_state_up     = true
}

resource "openstack_networking_port_v2" "k8_lb" {
  count              = local.k8_lb_count
  name               = "myproject-k8-lb-${count.index + 1}"
  network_id         = module.reference_infra.networks.internal.id
  security_group_ids = [module.k8_security_groups.groups.load_balancer.id]
  admin_state_up     = true
}

module "k8_domain" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-openstack-zonefile.git?ref=v0.1.0"
  domain = "myproject.com"
  container = local.dns.bucket_name
  dns_server_name = "ns.myproject.com"
  a_records = concat([
    for master in openstack_networking_port_v2.k8_masters: {
      prefix = "masters"
      ip = master.all_fixed_ips.0
    }
  ],
  [
    for worker in openstack_networking_port_v2.k8_workers: {
      prefix = "workers"
      ip = worker.all_fixed_ips.0
    } 
  ])
}

module "k8_masters_vms" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-openstack-kubernetes-node.git?ref=v0.1.0"
  count = local.k8_masters_count
  name = "myproject-kubernetes-master-${count.index + 1}"
  network_port = openstack_networking_port_v2.k8_masters[count.index]
  server_group = openstack_compute_servergroup_v2.k8_masters
  image_id = data.openstack_images_image_v2.ubuntu_focal.id
  flavor_id = module.reference_infra.flavors.generic_micro.id
  keypair_name = openstack_compute_keypair_v2.k8.name
  ssh_host_key_rsa = {
    public = tls_private_key.k8_server_ssh_rsa.public_key_openssh
    private = tls_private_key.k8_server_ssh_rsa.private_key_openssh
  }
  ssh_host_key_ecdsa = {
    public = tls_private_key.k8_server_ssh_ecdsa.public_key_openssh
    private = tls_private_key.k8_server_ssh_ecdsa.private_key_openssh
  }
}

module "k8_workers_vms" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-openstack-kubernetes-node.git?ref=v0.1.0"
  count = local.k8_workers_count
  name = "myproject-kubernetes-worker-${count.index + 1}"
  network_port = openstack_networking_port_v2.k8_workers[count.index]
  server_group = openstack_compute_servergroup_v2.k8_workers
  image_id = data.openstack_images_image_v2.ubuntu_focal.id
  flavor_id = module.reference_infra.flavors.generic_medium.id
  keypair_name = openstack_compute_keypair_v2.k8.name
  ssh_host_key_rsa = {
    public = tls_private_key.k8_server_ssh_rsa.public_key_openssh
    private = tls_private_key.k8_server_ssh_rsa.private_key_openssh
  }
  ssh_host_key_ecdsa = {
    public = tls_private_key.k8_server_ssh_ecdsa.public_key_openssh
    private = tls_private_key.k8_server_ssh_ecdsa.private_key_openssh
  }
}

module "k8_lb_tunnel_vms" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-openstack-kubernetes-load-balancer.git"
  count = local.k8_lb_tunnel_count
  name = "myproject-kubernetes-lb-tunnel-${count.index + 1}"
  network_port = openstack_networking_port_v2.k8_lb_tunnel[count.index]
  server_group = openstack_compute_servergroup_v2.k8_lb_tunnel
  image_id = data.openstack_images_image_v2.ubuntu_focal.id
  flavor_id = module.reference_infra.flavors.generic_micro.id
  keypair_name = openstack_compute_keypair_v2.k8.name
  ssh_host_key_rsa = {
    public = tls_private_key.k8_server_ssh_rsa.public_key_openssh
    private = tls_private_key.k8_server_ssh_rsa.private_key_openssh
  }
  ssh_host_key_ecdsa = {
    public = tls_private_key.k8_server_ssh_ecdsa.public_key_openssh
    private = tls_private_key.k8_server_ssh_ecdsa.private_key_openssh
  }
  tunnel = {
    enabled = true
    ssh = {
      user = "tunnel"
      authorized_key = tls_private_key.k8_tunnel_client_ssh.public_key_openssh
    }
  }
  kubernetes = {
    nameserver_ips = local.dns.nameserver_ips
    domain = "myproject.com"
    masters = {
      max_count = 7
      api_timeout = "5m"
      api_port = 6443
      max_api_connections = 200
    }
    workers = {
      max_count = 100
      ingress_http_timeout = "5m"
      ingress_http_port = 30000
      ingress_max_http_connections = 200
      ingress_https_timeout = "5m"
      ingress_https_port = 30001
      ingress_max_https_connections = 2000
    }
  }
}

module "k8_lb_vms" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-openstack-kubernetes-load-balancer.git"
  count = local.k8_lb_count
  name = "myproject-kubernetes-lb-${count.index + 1}"
  network_port = openstack_networking_port_v2.k8_lb[count.index]
  server_group = openstack_compute_servergroup_v2.k8_lb
  image_id = data.openstack_images_image_v2.ubuntu_focal.id
  flavor_id = module.reference_infra.flavors.generic_micro.id
  keypair_name = openstack_compute_keypair_v2.k8.name
  ssh_host_key_rsa = {
    public = tls_private_key.k8_server_ssh_rsa.public_key_openssh
    private = tls_private_key.k8_server_ssh_rsa.private_key_openssh
  }
  ssh_host_key_ecdsa = {
    public = tls_private_key.k8_server_ssh_ecdsa.public_key_openssh
    private = tls_private_key.k8_server_ssh_ecdsa.private_key_openssh
  }
  kubernetes = {
    nameserver_ips = local.dns.nameserver_ips
    domain = "myproject.com"
    masters = {
      max_count = 7
      api_timeout = "5m"
      api_port = 6443
      max_api_connections = 200
    }
    workers = {
      max_count = 100
      ingress_http_timeout = "5m"
      ingress_http_port = 30000
      ingress_max_http_connections = 200
      ingress_https_timeout = "5m"
      ingress_https_port = 30001
      ingress_max_https_connections = 2000
    }
  }
}
```