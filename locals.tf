data "yandex_client_config" "client" {}

locals {
  folder_id = data.yandex_client_config.client.folder_id
  # Единый внешний IP: резерв в Yandex VPC → ingress-nginx LoadBalancer и A-записи в ip-dns.tf
  ingress_public_ip = yandex_vpc_address.addr.external_ipv4_address[0].address
}
