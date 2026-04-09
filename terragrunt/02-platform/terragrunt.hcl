include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
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
  folder_id      = include.root.locals.folder_id
  create_network = false

  network_id    = dependency.network_vpn.outputs.network_id
  subnet_a_id   = dependency.network_vpn.outputs.subnet_a_id
  subnet_b_id   = dependency.network_vpn.outputs.subnet_b_id
  subnet_d_id   = dependency.network_vpn.outputs.subnet_d_id
  subnet_a_zone = dependency.network_vpn.outputs.subnet_a_zone
  subnet_b_zone = dependency.network_vpn.outputs.subnet_b_zone
  subnet_d_zone = dependency.network_vpn.outputs.subnet_d_zone
}
