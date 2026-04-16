data "yandex_client_config" "client" {}

locals {
  folder_id         = var.folder_id != "" ? var.folder_id : data.yandex_client_config.client.folder_id
  network_id        = var.create_network ? yandex_vpc_network.sentry[0].id : var.network_id
  subnet_a_id       = var.create_network ? yandex_vpc_subnet.sentry-a[0].id : var.subnet_a_id
  subnet_b_id       = var.create_network ? yandex_vpc_subnet.sentry-b[0].id : var.subnet_b_id
  subnet_d_id       = var.create_network ? yandex_vpc_subnet.sentry-d[0].id : var.subnet_d_id
  subnet_a_zone     = var.create_network ? yandex_vpc_subnet.sentry-a[0].zone : var.subnet_a_zone
  subnet_b_zone     = var.create_network ? yandex_vpc_subnet.sentry-b[0].zone : var.subnet_b_zone
  subnet_d_zone     = var.create_network ? yandex_vpc_subnet.sentry-d[0].zone : var.subnet_d_zone
  ingress_public_ip = yandex_vpc_address.addr.external_ipv4_address[0].address
}
