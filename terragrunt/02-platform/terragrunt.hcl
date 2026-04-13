include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

dependency "network_vpn" {
  config_path = "../01-network-vpn"
  mock_outputs = {
    network_id    = "mock-network-id"
    subnet_a_id   = "mock-subnet-a-id"
    subnet_b_id   = "mock-subnet-b-id"
    subnet_d_id   = "mock-subnet-d-id"
    subnet_a_zone = "ru-central1-a"
    subnet_b_zone = "ru-central1-b"
    subnet_d_zone = "ru-central1-d"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

terraform {
  source = "../../modules/02-platform"
}

inputs = {
  folder_id                                = include.root.locals.folder_id
  create_network                           = false
  managed_clickhouse_grant_create_workload = true
  # Project default: distributed external ClickHouse over native TLS.
  external_clickhouse_single_node          = false
  external_clickhouse_tcp_port             = 9440
  external_clickhouse_http_port            = 8443
  sentry_values_output_path                = "${get_terragrunt_dir()}/values_sentry.yaml"

  network_id    = dependency.network_vpn.outputs.network_id
  subnet_a_id   = dependency.network_vpn.outputs.subnet_a_id
  subnet_b_id   = dependency.network_vpn.outputs.subnet_b_id
  subnet_d_id   = dependency.network_vpn.outputs.subnet_d_id
  subnet_a_zone = dependency.network_vpn.outputs.subnet_a_zone
  subnet_b_zone = dependency.network_vpn.outputs.subnet_b_zone
  subnet_d_zone = dependency.network_vpn.outputs.subnet_d_zone
}
