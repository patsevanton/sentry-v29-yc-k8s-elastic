resource "yandex_iam_service_account" "sa_s3_sentry" {
  folder_id   = local.folder_id
  name        = "sa-s3-sentry"
  description = "Service account for Sentry S3 filestore"
}

resource "yandex_resourcemanager_folder_iam_member" "sa_s3_sentry_storage_editor" {
  folder_id = local.folder_id
  role      = "storage.editor"
  member    = "serviceAccount:${yandex_iam_service_account.sa_s3_sentry.id}"
}

resource "yandex_iam_service_account_static_access_key" "sa_s3_sentry_key" {
  service_account_id = yandex_iam_service_account.sa_s3_sentry.id
  description        = "Static access key for Sentry filestore in Object Storage"
}

resource "yandex_storage_bucket" "sentry_filestore" {
  access_key = yandex_iam_service_account_static_access_key.sa_s3_sentry_key.access_key
  secret_key = yandex_iam_service_account_static_access_key.sa_s3_sentry_key.secret_key
  bucket     = "sentry-filestore-${local.folder_id}"
  depends_on = [yandex_resourcemanager_folder_iam_member.sa_s3_sentry_storage_editor]
}

output "sentry_s3_access_key" {
  value     = yandex_iam_service_account_static_access_key.sa_s3_sentry_key.access_key
  sensitive = true
}

output "sentry_s3_secret_key" {
  value     = yandex_iam_service_account_static_access_key.sa_s3_sentry_key.secret_key
  sensitive = true
}

output "sentry_s3_bucket_name" {
  value = yandex_storage_bucket.sentry_filestore.bucket
}
