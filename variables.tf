variable "folder_id" {
  description = "Yandex Cloud folder ID (optional; defaults to client config)"
  type        = string
  default     = ""
}


variable "sentry_incluster_kafka_enabled" {
  description = "Use in-chart Kafka instead of external managed Kafka"
  type        = bool
  default     = false
}

variable "managed_kafka_assign_public_ip" {
  description = "Assign public IP addresses to managed Kafka brokers"
  type        = bool
  default     = false
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

variable "external_kafka_provisioning_enabled" {
  description = "Enable Sentry Helm externalKafka topic provisioning job"
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Yandex Managed PostgreSQL
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# Yandex Managed Redis
# ---------------------------------------------------------------------------

variable "managed_redis_name" {
  description = "Managed Redis cluster name"
  type        = string
  default     = "sentry-redis-managed"
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
