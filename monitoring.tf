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

output "monitoring_api_key" {
  value     = yandex_iam_service_account_key.monitoring_viewer_key.private_key
  sensitive = true
}
