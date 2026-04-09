output "network_id" {
  value = yandex_vpc_network.sentry.id
}

output "subnet_a_id" {
  value = yandex_vpc_subnet.sentry-a.id
}

output "subnet_b_id" {
  value = yandex_vpc_subnet.sentry-b.id
}

output "subnet_d_id" {
  value = yandex_vpc_subnet.sentry-d.id
}

output "subnet_a_zone" {
  value = yandex_vpc_subnet.sentry-a.zone
}

output "subnet_b_zone" {
  value = yandex_vpc_subnet.sentry-b.zone
}

output "subnet_d_zone" {
  value = yandex_vpc_subnet.sentry-d.zone
}

output "vpn_public_ip" {
  value = yandex_compute_instance.wireguard.network_interface[0].nat_ip_address
}

output "vpn_private_ip" {
  value = yandex_compute_instance.wireguard.network_interface[0].ip_address
}

output "wireguard_client_config_fetch_command" {
  description = "Command to fetch generated client config from the VPN VM"
  value       = "ssh ubuntu@${yandex_compute_instance.wireguard.network_interface[0].nat_ip_address} 'sudo cat /root/wg-client.conf'"
}
