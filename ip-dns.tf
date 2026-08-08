resource "yandex_vpc_address" "addr" {
  name      = "sentry-pip"
  folder_id = local.folder_id

  external_ipv4_address {
    zone_id = local.subnet_a_zone
  }
}

# Публичный DNS не требуется: используются sslip.io-имена вида <сервис>.<LB_IP>.sslip.io
# (sentry, grafana, vmsingle), которые резолвятся в IP балансировщика ingress-nginx.
