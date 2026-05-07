resource "yandex_iam_service_account" "monitoring_viewer" {
  folder_id   = local.folder_id
  name        = "monitoring-viewer-sa"
  description = "Service account for Yandex Monitoring"
}

resource "yandex_resourcemanager_folder_iam_member" "monitoring_viewer_role" {
  folder_id = local.folder_id
  role      = "monitoring.viewer"
  member    = "serviceAccount:${yandex_iam_service_account.monitoring_viewer.id}"
}

resource "yandex_iam_service_account_key" "monitoring_viewer_key" {
  service_account_id = yandex_iam_service_account.monitoring_viewer.id
}

resource "yandex_iam_service_account_api_key" "monitoring_api_key" {
  service_account_id = yandex_iam_service_account.monitoring_viewer.id
  description        = "API key for Yandex Monitoring bearer token"
}

output "folder_id" {
  value = local.folder_id
}

output "monitoring_sa_key_id" {
  value     = yandex_iam_service_account_key.monitoring_viewer_key.id
  sensitive = false
}

output "monitoring_sa_service_account_id" {
  value     = yandex_iam_service_account.monitoring_viewer.id
  sensitive = false
}

output "monitoring_sa_private_key" {
  value     = yandex_iam_service_account_key.monitoring_viewer_key.private_key
  sensitive = true
}

output "monitoring_api_key" {
  value     = yandex_iam_service_account_api_key.monitoring_api_key.secret_key
  sensitive = true
}

locals {
  vmstaticscrape_kafka_config = templatefile("${path.module}/k8s/vmstaticscrape-yc-managed-kafka.yaml.tpl", {
    folder_id = local.folder_id
  })
}

resource "local_file" "write_vmstaticscrape_kafka_config" {
  content  = local.vmstaticscrape_kafka_config
  filename = "${path.module}/k8s/vmstaticscrape-yc-managed-kafka.yaml"
}

locals {
  secret_yc_monitoring_api_key = templatefile("${path.module}/k8s/secret-yc-monitoring-api-key.yaml.tpl", {
    monitoring_api_key = yandex_iam_service_account_api_key.monitoring_api_key.secret_key
  })
}

resource "local_file" "write_secret_yc_monitoring_api_key" {
  content  = local.secret_yc_monitoring_api_key
  filename = "${path.module}/k8s/secret-yc-monitoring-api-key.yaml"
}
