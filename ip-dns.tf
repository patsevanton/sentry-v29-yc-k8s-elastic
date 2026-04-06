resource "yandex_vpc_address" "addr" {
  name      = "sentry-pip"
  folder_id = local.folder_id

  external_ipv4_address {
    zone_id = yandex_vpc_subnet.sentry-a.zone
  }
}

resource "yandex_dns_zone" "apatsev-org-ru" {
  name      = "apatsev-org-ru-zone"
  folder_id = local.folder_id

  zone   = "apatsev.org.ru."
  public = true

  private_networks = [yandex_vpc_network.sentry.id]
}

resource "yandex_dns_recordset" "sentry" {
  zone_id = yandex_dns_zone.apatsev-org-ru.id
  name    = "sentry.apatsev.org.ru."
  type    = "A"
  ttl     = 200
  data    = [local.ingress_public_ip]
}

resource "yandex_dns_recordset" "grafana" {
  zone_id = yandex_dns_zone.apatsev-org-ru.id
  name    = "grafana.apatsev.org.ru."
  type    = "A"
  ttl     = 200
  data    = [local.ingress_public_ip]
}

resource "yandex_dns_recordset" "vmsingle" {
  zone_id = yandex_dns_zone.apatsev-org-ru.id
  name    = "vmsingle.apatsev.org.ru."
  type    = "A"
  ttl     = 200
  data    = [local.ingress_public_ip]
}
