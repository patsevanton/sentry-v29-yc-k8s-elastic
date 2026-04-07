# S3-совместимое хранилище (Yandex Object Storage) для файлового бэкенда Sentry.
#
# Sentry хранит debug-символы, source maps и другие артефакты в filestore.
# По умолчанию чарт использует локальную ФС (/var/lib/sentry/files) с PVC (RWO).
# RWO-том доступен только одному поду (web); taskworker-ы при assemble debug-файлов
# не находят blob-ы → FileNotFoundError, загрузка DIF/source maps завершается
# «internal server error». S3-бэкенд доступен всем подам одновременно, решая
# эту проблему без NFS или RWX-тома.
#
# После terraform apply файл values_sentry.yaml генерируется автоматически
# из шаблона values_sentry.yaml.tpl (см. templatefile.tf).

resource "yandex_iam_service_account" "sa_s3_sentry" {
  folder_id   = local.folder_id
  name        = "sa-s3-sentry"
  description = "Сервисный аккаунт для Sentry S3 filestore (Object Storage)"
}

resource "yandex_resourcemanager_folder_iam_member" "sa_s3_sentry_storage_editor" {
  folder_id = local.folder_id
  role      = "storage.editor"
  member    = "serviceAccount:${yandex_iam_service_account.sa_s3_sentry.id}"
}

resource "yandex_iam_service_account_static_access_key" "sa_s3_sentry_key" {
  service_account_id = yandex_iam_service_account.sa_s3_sentry.id
  description        = "Static access key для Sentry filestore в Object Storage"
}

resource "yandex_storage_bucket" "sentry_filestore" {
  access_key = yandex_iam_service_account_static_access_key.sa_s3_sentry_key.access_key
  secret_key = yandex_iam_service_account_static_access_key.sa_s3_sentry_key.secret_key
  bucket     = "sentry-filestore-${local.folder_id}"

  depends_on = [
    yandex_resourcemanager_folder_iam_member.sa_s3_sentry_storage_editor
  ]
}

output "sentry_s3_access_key" {
  description = "S3 access key для filestore.s3.accessKey в values Sentry"
  value       = yandex_iam_service_account_static_access_key.sa_s3_sentry_key.access_key
  sensitive   = true
}

output "sentry_s3_secret_key" {
  description = "S3 secret key для filestore.s3.secretKey в values Sentry"
  value       = yandex_iam_service_account_static_access_key.sa_s3_sentry_key.secret_key
  sensitive   = true
}

output "sentry_s3_bucket_name" {
  description = "Имя S3-бакета для filestore.s3.bucketName в values Sentry"
  value       = yandex_storage_bucket.sentry_filestore.bucket
}
