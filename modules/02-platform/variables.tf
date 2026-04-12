variable "folder_id" {
  description = "Yandex Cloud folder ID (optional; defaults to client config)"
  type        = string
  default     = ""
}

variable "create_network" {
  description = "Create VPC and subnets in this stack. Set false when network is provisioned by stage 1."
  type        = bool
  default     = true
}

variable "network_id" {
  description = "Existing VPC network ID (required when create_network=false)"
  type        = string
  default     = ""
  validation {
    condition     = var.create_network || var.network_id != ""
    error_message = "network_id must be set when create_network=false."
  }
}

variable "subnet_a_id" {
  description = "Existing subnet ID in ru-central1-a (required when create_network=false)"
  type        = string
  default     = ""
  validation {
    condition     = var.create_network || var.subnet_a_id != ""
    error_message = "subnet_a_id must be set when create_network=false."
  }
}

variable "subnet_b_id" {
  description = "Existing subnet ID in ru-central1-b (required when create_network=false)"
  type        = string
  default     = ""
  validation {
    condition     = var.create_network || var.subnet_b_id != ""
    error_message = "subnet_b_id must be set when create_network=false."
  }
}

variable "subnet_d_id" {
  description = "Existing subnet ID in ru-central1-d (required when create_network=false)"
  type        = string
  default     = ""
  validation {
    condition     = var.create_network || var.subnet_d_id != ""
    error_message = "subnet_d_id must be set when create_network=false."
  }
}

variable "subnet_a_zone" {
  description = "Zone for subnet_a_id (required when create_network=false)"
  type        = string
  default     = "ru-central1-a"
}

variable "subnet_b_zone" {
  description = "Zone for subnet_b_id (required when create_network=false)"
  type        = string
  default     = "ru-central1-b"
}

variable "subnet_d_zone" {
  description = "Zone for subnet_d_id (required when create_network=false)"
  type        = string
  default     = "ru-central1-d"
}

variable "external_clickhouse_tcp_port" {
  description = "ClickHouse native TCP (plaintext), обычно 9000 во VPC"
  type        = number
  default     = 9000
}

variable "external_clickhouse_http_port" {
  description = "ClickHouse HTTP (plaintext), обычно 8123 во VPC"
  type        = number
  default     = 8123
}

variable "external_clickhouse_single_node" {
  description = "Set true for single-node external ClickHouse, false for replicated/distributed"
  type        = bool
  default     = true
}

variable "external_clickhouse_cluster_name" {
  description = "External ClickHouse clusterName for Snuba distributed queries"
  type        = string
  default     = "sentry-cluster"
}

variable "external_clickhouse_distributed_cluster_name" {
  description = "External ClickHouse distributedClusterName for Snuba"
  type        = string
  default     = "sentry-cluster"
}

variable "sentry_hooks_active_deadline_seconds" {
  description = "Helm hooks activeDeadlineSeconds for long-running jobs (db-init/snuba-migrate)"
  type        = number
  default     = 1800
}

variable "enable_clickhouse_dns_search" {
  description = "Add DNS search suffix when CH returns short hostnames in system.clusters"
  type        = bool
  default     = false
}

variable "clickhouse_dns_search_suffix" {
  description = "DNS search suffix for ClickHouse short hostnames (for in-cluster CH usually clickhouse.svc.cluster.local)"
  type        = string
  default     = "clickhouse.svc.cluster.local"
}

variable "sentry_values_output_path" {
  description = "Path to generated values_sentry.yaml file used by Helm"
  type        = string
  default     = "values_sentry.yaml"
}

variable "managed_clickhouse_name" {
  description = "Managed ClickHouse cluster name"
  type        = string
  default     = "sentry-clickhouse-managed"
}

variable "managed_clickhouse_version" {
  description = "Managed ClickHouse version"
  type        = string
  default     = "25.3"
}

variable "managed_clickhouse_resource_preset_id" {
  description = "Managed ClickHouse host resource preset"
  type        = string
  default     = "s2.micro"
}

variable "managed_clickhouse_disk_type_id" {
  description = "Managed ClickHouse disk type"
  type        = string
  default     = "network-ssd"
}

variable "managed_clickhouse_disk_size" {
  description = "Managed ClickHouse disk size in GiB"
  type        = number
  default     = 64
}

variable "managed_clickhouse_database" {
  description = "Managed ClickHouse database for Sentry/Snuba"
  type        = string
  default     = "sentry"
}

variable "managed_clickhouse_user" {
  description = "Managed ClickHouse user for Sentry/Snuba"
  type        = string
  default     = "sentry"
}

variable "managed_clickhouse_user_password" {
  description = "Managed ClickHouse user password for Sentry/Snuba (if empty, Terraform generates random)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "managed_clickhouse_sql_user_management_enabled" {
  description = "Enable SQL database and user management in Managed ClickHouse (sql_database_management + sql_user_management; needed for GRANT ... WORKLOAD and clickhousedbops; requires DNS/network to cluster FQDN)"
  type        = bool
  default     = true
}

variable "managed_clickhouse_admin_password" {
  description = "Admin password for SQL user management in Managed ClickHouse (if empty, Terraform generates random)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "managed_clickhouse_grant_create_workload" {
  description = "Grant CREATE/DROP WORKLOAD ON *.* to managed_clickhouse_user via clickhousedbops provider (needed by Snuba workload migrations)"
  type        = bool
  default     = false
}
