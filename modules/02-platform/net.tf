resource "yandex_vpc_network" "sentry" {
  count     = var.create_network ? 1 : 0
  name      = "vpc"
  folder_id = local.folder_id
}

resource "yandex_vpc_subnet" "sentry-a" {
  count          = var.create_network ? 1 : 0
  folder_id      = local.folder_id
  v4_cidr_blocks = ["10.0.1.0/24"]
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.sentry[0].id
}

resource "yandex_vpc_subnet" "sentry-b" {
  count          = var.create_network ? 1 : 0
  folder_id      = local.folder_id
  v4_cidr_blocks = ["10.0.2.0/24"]
  zone           = "ru-central1-b"
  network_id     = yandex_vpc_network.sentry[0].id
}

resource "yandex_vpc_subnet" "sentry-d" {
  count          = var.create_network ? 1 : 0
  folder_id      = local.folder_id
  v4_cidr_blocks = ["10.0.3.0/24"]
  zone           = "ru-central1-d"
  network_id     = yandex_vpc_network.sentry[0].id
}
