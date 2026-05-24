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

variable "sentry_hooks_active_deadline_seconds" {
  description = "Helm hooks activeDeadlineSeconds for long-running jobs (db-init/snuba-migrate)"
  type        = number
  default     = 7200
}

variable "sentry_values_output_path" {
  description = "Path to generated values_sentry.yaml file used by Helm"
  type        = string
  default     = "values_sentry.yaml"
}

variable "sentry_incluster_kafka_enabled" {
  description = "Use in-chart Kafka instead of external managed Kafka"
  type        = bool
  default     = false
}

variable "managed_kafka_name" {
  description = "Managed Kafka cluster name"
  type        = string
  default     = "sentry-kafka-managed"
}

variable "managed_kafka_version" {
  description = "Managed Kafka version (KRaft generation)"
  type        = string
  default     = "4.0"
}

variable "managed_kafka_brokers_count" {
  description = "Number of brokers per zone in managed Kafka"
  type        = number
  default     = 1
}

variable "managed_kafka_assign_public_ip" {
  description = "Assign public IP addresses to managed Kafka brokers"
  type        = bool
  default     = false
}

variable "managed_kafka_resource_preset_id" {
  description = "Managed Kafka host resource preset"
  type        = string
  default     = "s2.micro"
}

variable "managed_kafka_disk_type_id" {
  description = "Managed Kafka disk type"
  type        = string
  default     = "network-ssd"
}

variable "managed_kafka_disk_size" {
  description = "Managed Kafka disk size in GiB"
  type        = number
  default     = 32
}

variable "managed_kafka_port" {
  description = "Managed Kafka broker port used by Sentry externalKafka settings"
  type        = number
  default     = 9092
}

variable "managed_kafka_user" {
  description = "Managed Kafka username for Sentry"
  type        = string
  default     = "sentry"
}

variable "managed_kafka_user_password" {
  description = "Managed Kafka password for Sentry (if empty, Terraform generates random)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "managed_kafka_sasl_mechanism" {
  description = "SASL mechanism for Sentry externalKafka"
  type        = string
  default     = "SCRAM-SHA-512"
}

variable "managed_kafka_security_protocol" {
  description = "Kafka security protocol for Sentry externalKafka"
  type        = string
  default     = "SASL_PLAINTEXT"
}

variable "managed_kafka_auto_create_topics_enable" {
  description = "Enable broker auto topic creation in managed Kafka"
  type        = bool
  default     = true
}

variable "external_kafka_provisioning_enabled" {
  description = "Enable Sentry Helm externalKafka topic provisioning job"
  type        = bool
  default     = true
}

variable "external_kafka_provisioning_replication_factor" {
  description = "Replication factor for Sentry externalKafka provisioning"
  type        = number
  default     = 3
}

variable "external_kafka_provisioning_num_partitions" {
  description = "Default partitions for Sentry externalKafka provisioning"
  type        = number
  default     = 3
}

# ---------------------------------------------------------------------------
# Yandex Managed PostgreSQL
# ---------------------------------------------------------------------------

variable "managed_pg_name" {
  description = "Managed PostgreSQL cluster name"
  type        = string
  default     = "sentry-pg-managed"
}

variable "managed_pg_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "17"
}

variable "managed_pg_resource_preset_id" {
  description = "Managed PostgreSQL host resource preset"
  type        = string
  default     = "s2.micro"
}

variable "managed_pg_disk_type_id" {
  description = "Managed PostgreSQL disk type"
  type        = string
  default     = "network-ssd"
}

variable "managed_pg_disk_size" {
  description = "Managed PostgreSQL disk size in GiB"
  type        = number
  default     = 32
}

variable "managed_pg_user" {
  description = "Managed PostgreSQL username for Sentry"
  type        = string
  default     = "sentry"
}

variable "managed_pg_user_password" {
  description = "Managed PostgreSQL password for Sentry (if empty, Terraform generates random)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "managed_pg_database" {
  description = "Managed PostgreSQL database name for Sentry"
  type        = string
  default     = "sentry"
}

variable "managed_pg_conn_limit" {
  description = "Managed PostgreSQL connection limit for Sentry user"
  type        = number
  default     = 200
}

# ---------------------------------------------------------------------------
# Yandex Managed Redis
# ---------------------------------------------------------------------------

variable "managed_redis_name" {
  description = "Managed Redis cluster name"
  type        = string
  default     = "sentry-redis-managed"
}

variable "managed_redis_version" {
  description = "Redis version"
  type        = string
  default     = "9.1-valkey"
}

variable "managed_redis_resource_preset_id" {
  description = "Managed Redis host resource preset"
  type        = string
  default     = "s2.micro"
}

variable "managed_redis_disk_type_id" {
  description = "Managed Redis disk type"
  type        = string
  default     = "network-ssd"
}

variable "managed_redis_disk_size" {
  description = "Managed Redis disk size in GiB"
  type        = number
  default     = 16
}

variable "managed_redis_user" {
  description = "Managed Redis username for Sentry"
  type        = string
  default     = "sentry"
}

variable "managed_redis_password" {
  description = "Managed Redis password for Sentry (if empty, Terraform generates random)"
  type        = string
  default     = ""
  sensitive   = true
}
