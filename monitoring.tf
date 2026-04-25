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

output "folder_id" {
  value = local.folder_id
}

# ВНИМАНИЕ: Это НЕ IAM-токен, а авторизованный ключ (RSA private key).
# VMAgent не умеет сам генерировать IAM-токен из него.
# Для получения IAM-токена используйте: scripts/get-yc-iam-token.py
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

locals {
  vmstaticscrape_kafka_config = templatefile("${path.module}/k8s/vmstaticscrape-yc-managed-kafka.yaml.tpl", {
    folder_id = local.folder_id
  })
}

resource "local_file" "write_vmstaticscrape_kafka_config" {
  content  = local.vmstaticscrape_kafka_config
  filename = "${path.module}/k8s/vmstaticscrape-yc-managed-kafka.yaml"
}
