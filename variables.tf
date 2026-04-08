variable "folder_id" {
  description = "Yandex Cloud folder ID (optional; defaults to client config)"
  type        = string
  default     = ""
}

variable "external_clickhouse_tcp_port" {
  description = "External ClickHouse native TCP port"
  type        = number
  default     = 9000
}

variable "external_clickhouse_http_port" {
  description = "External ClickHouse HTTP port"
  type        = number
  default     = 8123
}

variable "external_clickhouse_single_node" {
  description = "Set true for single-node external ClickHouse, false for replicated/distributed"
  type        = bool
  default     = false
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