include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

terraform {
  source = "../../modules/01-network-vpn"
}

inputs = {
  folder_id      = include.root.locals.folder_id
  ssh_public_key = get_env("TF_VAR_ssh_public_key", "")
}
