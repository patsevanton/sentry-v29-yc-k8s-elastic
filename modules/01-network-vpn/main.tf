data "yandex_client_config" "client" {}

data "yandex_compute_image" "ubuntu" {
  family = "ubuntu-2204-lts"
}

locals {
  folder_id               = var.folder_id != "" ? var.folder_id : data.yandex_client_config.client.folder_id
  vpn_subnet_id_effective = var.vpn_subnet_id != "" ? var.vpn_subnet_id : yandex_vpc_subnet.sentry-a.id
}

resource "yandex_vpc_network" "sentry" {
  name      = var.network_name
  folder_id = local.folder_id
}

resource "yandex_vpc_subnet" "sentry-a" {
  folder_id      = local.folder_id
  v4_cidr_blocks = [var.subnet_a_cidr]
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.sentry.id
}

resource "yandex_vpc_subnet" "sentry-b" {
  folder_id      = local.folder_id
  v4_cidr_blocks = [var.subnet_b_cidr]
  zone           = "ru-central1-b"
  network_id     = yandex_vpc_network.sentry.id
}

resource "yandex_vpc_subnet" "sentry-d" {
  folder_id      = local.folder_id
  v4_cidr_blocks = [var.subnet_d_cidr]
  zone           = "ru-central1-d"
  network_id     = yandex_vpc_network.sentry.id
}

resource "yandex_vpc_security_group" "wireguard" {
  name       = "wireguard-vpn-sg"
  folder_id  = local.folder_id
  network_id = yandex_vpc_network.sentry.id

  ingress {
    description    = "WireGuard UDP"
    protocol       = "UDP"
    port           = var.wireguard_port
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description    = "SSH"
    protocol       = "TCP"
    port           = 22
    v4_cidr_blocks = [var.ssh_allowed_cidr]
  }

  egress {
    description    = "Any egress"
    protocol       = "ANY"
    from_port      = 0
    to_port        = 65535
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_compute_instance" "wireguard" {
  folder_id = local.folder_id
  name      = var.vpn_instance_name
  zone      = var.vpn_zone

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.image_id
      size     = 20
      type     = "network-ssd"
    }
  }

  network_interface {
    subnet_id          = local.vpn_subnet_id_effective
    nat                = true
    security_group_ids = [yandex_vpc_security_group.wireguard.id]
  }

  metadata = {
    ssh-keys = "ubuntu:${var.ssh_public_key}"
    user-data = templatefile("${path.module}/cloud-init-wireguard.yaml.tpl", {
      wireguard_server_private_cidr = var.wireguard_server_private_cidr
      wireguard_port                = var.wireguard_port
      wireguard_client_ip           = var.wireguard_client_ip
      wireguard_client_allowed_ips  = var.wireguard_client_allowed_ips
    })
  }
}
