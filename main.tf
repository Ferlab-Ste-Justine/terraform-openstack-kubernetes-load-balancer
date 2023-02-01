data "template_cloudinit_config" "user_data" {
  gzip = false
  base64_encode = false
  part {
    content_type = "text/cloud-config"
    content = templatefile(
      "${path.module}/files/user_data.yaml.tpl", 
      {
        node_name = var.name
        chrony = var.chrony
        tunnel = var.tunnel
        ssh_host_key_rsa = var.ssh_host_key_rsa
        ssh_host_key_ecdsa = var.ssh_host_key_ecdsa
        haproxy_config = templatefile(
          "${path.module}/files/lb-haproxy.cfg",
          {
            kubernetes = var.kubernetes
            tunnel = var.tunnel
          }
        )
      }
    )
  }
}

resource "openstack_compute_instance_v2" "k8_load_balancer" {
  name            = var.name
  image_id        = var.image_id
  flavor_id       = var.flavor_id
  key_pair        = var.keypair_name
  user_data = data.template_cloudinit_config.user_data.rendered

  network {
    port = var.network_port.id
  }

  scheduler_hints {
    group = var.server_group.id
  }

  lifecycle {
    ignore_changes = [
      user_data,
    ]
  }
}