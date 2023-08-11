locals {
  block_devices           = var.image_source.volume_id != "" ? [{
    uuid                  = var.image_source.volume_id
    source_type           = "volume"
    boot_index            = 0
    destination_type      = "volume"
    delete_on_termination = false
  }] : []
}

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
  image_id        = var.image_source.image_id != "" ? var.image_source.image_id : null
  flavor_id       = var.flavor_id
  key_pair        = var.keypair_name
  user_data = data.template_cloudinit_config.user_data.rendered

  network {
    port = var.network_port.id
  }

  scheduler_hints {
    group = var.server_group.id
  }

  dynamic "block_device" {
    for_each = local.block_devices
    content {
      uuid                  = block_device.value["uuid"]
      source_type           = block_device.value["source_type"]
      boot_index            = block_device.value["boot_index"]
      destination_type      = block_device.value["destination_type"]
      delete_on_termination = block_device.value["delete_on_termination"]
    }
  }

  lifecycle {
    ignore_changes = [
      user_data,
    ]
  }
}