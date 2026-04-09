variable "folder_id" {
  description = "Yandex Cloud folder ID (optional; defaults to client config)"
  type        = string
  default     = ""
}

variable "network_name" {
  description = "VPC network name"
  type        = string
  default     = "vpc"
}

variable "subnet_a_cidr" {
  description = "CIDR for subnet in ru-central1-a"
  type        = string
  default     = "10.0.1.0/24"
}

variable "subnet_b_cidr" {
  description = "CIDR for subnet in ru-central1-b"
  type        = string
  default     = "10.0.2.0/24"
}

variable "subnet_d_cidr" {
  description = "CIDR for subnet in ru-central1-d"
  type        = string
  default     = "10.0.3.0/24"
}

variable "vpn_zone" {
  description = "Availability zone for WireGuard VM"
  type        = string
  default     = "ru-central1-a"
}

variable "vpn_instance_name" {
  description = "WireGuard VM name"
  type        = string
  default     = "wireguard-vpn"
}

variable "vpn_subnet_id" {
  description = "Subnet ID for WireGuard VM (optional; defaults to subnet-a)"
  type        = string
  default     = ""
}

variable "ssh_public_key" {
  description = "SSH public key for VPN VM users"
  type        = string

  validation {
    condition     = trimspace(var.ssh_public_key) != ""
    error_message = "ssh_public_key must not be empty. Set TF_VAR_ssh_public_key to your public SSH key."
  }
}

variable "ssh_username" {
  description = "Preferred SSH username for connecting to VPN VM"
  type        = string
  default     = "ubuntu"
}

variable "ssh_allowed_cidr" {
  description = "CIDR allowed to SSH into VPN VM"
  type        = string
  default     = "0.0.0.0/0"
}

variable "wireguard_port" {
  description = "WireGuard UDP listen port"
  type        = number
  default     = 51820
}

variable "wireguard_server_private_cidr" {
  description = "WireGuard server interface CIDR"
  type        = string
  default     = "10.66.0.1/24"
}

variable "wireguard_client_ip" {
  description = "WireGuard client tunnel IP (without CIDR suffix)"
  type        = string
  default     = "10.66.0.2"
}

variable "wireguard_client_allowed_ips" {
  description = "Comma-separated networks routed through VPN client"
  type        = string
  default     = "10.0.0.0/16,10.66.0.0/24"
}
