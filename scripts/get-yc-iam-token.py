#!/usr/bin/env python3
"""
Генерация IAM-токена Яндекс.Облака из авторизованного ключа сервисного аккаунта (SA Key).

Использование:
  export SA_KEY_ID="<key_id>"
  export SA_PRIVATE_KEY="$(cat private_key.pem)"
  python3 get-yc-iam-token.py

Или с файлом ключа:
  python3 get-yc-iam-token.py --key-file ~/keys/key.json

Где key.json — это результат `yc iam key create --output key.json`.
"""
import argparse
import json
import os
import time
import urllib.request
import urllib.error


def get_token_from_key_id_and_private_key(key_id: str, service_account_id: str, private_key: str) -> str:
    """Генерирует JWT и обменивает его на IAM-токен через Yandex OAuth."""
    try:
        import jwt
        from cryptography.hazmat.primitives import serialization
    except ImportError:
        print("ERROR: Установите зависимости: pip3 install PyJWT cryptography")
        exit(1)

    now = int(time.time())
    payload = {
        "aud": "https://iam.api.cloud.yandex.net/iam/v1/tokens",
        "iss": service_account_id,
        "iat": now,
        "exp": now + 3600,
    }

    try:
        token = jwt.encode(payload, private_key, algorithm="PS256", headers={"kid": key_id})
    except Exception as e:
        print(f"ERROR: Не удалось подписать JWT: {e}")
        exit(1)

    req = urllib.request.Request(
        "https://iam.api.cloud.yandex.net/iam/v1/tokens",
        data=json.dumps({"jwt": token}).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    try:
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return data["iamToken"]
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8")
        print(f"ERROR: HTTP {e.code} от IAM API: {body}")
        exit(1)


def get_token_from_json_file(path: str) -> str:
    with open(path, "r") as f:
        data = json.load(f)

    # формат от Terraform yandex_iam_service_account_key или yc iam key create
    key_id = data.get("id")
    private_key = data.get("private_key")
    service_account_id = data.get("service_account_id") or data.get("iss")

    if key_id and private_key and service_account_id:
        return get_token_from_key_id_and_private_key(key_id, service_account_id, private_key)

    print(f"ERROR: Неизвестный формат ключа в файле {path}")
    exit(1)


def main():
    parser = argparse.ArgumentParser(description="Генерация YC IAM-токена из SA Key")
    parser.add_argument("--key-file", help="Путь к JSON-файлу с SA Key")
    args = parser.parse_args()

    if args.key_file:
        token = get_token_from_json_file(args.key_file)
    else:
        key_id = os.environ.get("SA_KEY_ID")
        service_account_id = os.environ.get("SA_SERVICE_ACCOUNT_ID")
        private_key = os.environ.get("SA_PRIVATE_KEY")
        if not key_id or not private_key or not service_account_id:
            print("ERROR: Укажите --key-file или переменные окружения SA_KEY_ID, SA_SERVICE_ACCOUNT_ID и SA_PRIVATE_KEY")
            exit(1)
        token = get_token_from_key_id_and_private_key(key_id, service_account_id, private_key)

    print(token)


if __name__ == "__main__":
    main()
