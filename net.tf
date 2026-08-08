resource "yandex_vpc_network" "sentry" {
  name      = "vpc"
  folder_id = local.folder_id
}

resource "yandex_vpc_gateway" "sentry_nat" {
  folder_id    = local.folder_id
  name         = "sentry-nat"
  description  = "NAT gateway for private subnets egress"

  shared_egress_gateway {}
}

resource "yandex_vpc_route_table" "sentry_rt" {
  folder_id  = local.folder_id
  name       = "sentry-rt"
  network_id = yandex_vpc_network.sentry.id

  static_route {
    destination_prefix = "0.0.0.0/0"
    gateway_id         = yandex_vpc_gateway.sentry_nat.id
  }
}

resource "yandex_vpc_subnet" "sentry-a" {
  folder_id      = local.folder_id
  v4_cidr_blocks = ["10.0.1.0/24"]
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.sentry.id
  route_table_id = yandex_vpc_route_table.sentry_rt.id
}

resource "yandex_vpc_subnet" "sentry-b" {
  folder_id      = local.folder_id
  v4_cidr_blocks = ["10.0.2.0/24"]
  zone           = "ru-central1-b"
  network_id     = yandex_vpc_network.sentry.id
  route_table_id = yandex_vpc_route_table.sentry_rt.id
}

resource "yandex_vpc_subnet" "sentry-d" {
  folder_id      = local.folder_id
  v4_cidr_blocks = ["10.0.3.0/24"]
  zone           = "ru-central1-d"
  network_id     = yandex_vpc_network.sentry.id
  route_table_id = yandex_vpc_route_table.sentry_rt.id
}
