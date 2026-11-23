#!/bin/zsh
# Выкладка Бупеня для Windows и Linux: scripts/build.sh → архивы и манифесты windows.json /
# linux.json ({version, url, sha256, size, notes}) в публичный бакет hyax-public/installers/bypen/
# (ключи ~/.hyax-s3.env, boto3 ~/.hyax-venv). Проверка обновлений в клиенте — app.go checkUpdate.
#   BYPEN_VERSION=0.1.21 scripts/publish.sh "что нового"
set -eu
cd "$(dirname "$0")/.."
NOTES=${1:-}
PY=~/.hyax-venv/bin/python
[[ -x $PY ]] || { echo "нет ~/.hyax-venv с boto3"; exit 1; }
[[ -f ~/.hyax-s3.env ]] || { echo "нет ~/.hyax-s3.env"; exit 1; }
N=$(git rev-list --count HEAD)
V="${BYPEN_VERSION:-0.1.$N}"
export BYPEN_VERSION=$V
zsh scripts/build.sh
set -a; source ~/.hyax-s3.env; set +a
$PY - "$V" "$NOTES" <<'PYEOF'
import hashlib, json, os, sys
import boto3
ver, notes = sys.argv[1], sys.argv[2]
bucket, prefix = "hyax-public", "installers/bypen/"
base = f"https://storage.yandexcloud.net/{bucket}/{prefix}"
c = boto3.client("s3", endpoint_url=os.environ["S3_ENDPOINT_URL"], region_name=os.environ.get("S3_REGION", "ru-central1"),
                 aws_access_key_id=os.environ["S3_ACCESS_KEY_ID"], aws_secret_access_key=os.environ["S3_SECRET_ACCESS_KEY"])
for plat, src, ext, ctype in (("windows", "dist/bypen-windows-x64.zip", "zip", "application/zip"),
                              ("linux", "dist/bypen-linux-x64.tar.gz", "tar.gz", "application/gzip")):
    data = open(src, "rb").read()
    sha = hashlib.sha256(data).hexdigest()
    key = f"{prefix}bypen-{plat}-x64-{ver}.{ext}"
    c.put_object(Bucket=bucket, Key=key, Body=data, ContentType=ctype, ACL="public-read",
                 CacheControl="public, max-age=31536000", Metadata={"sha256": sha})
    # постоянная ссылка для первой установки
    c.put_object(Bucket=bucket, Key=f"{prefix}bypen-{plat}-x64.{ext}", Body=data, ContentType=ctype,
                 ACL="public-read", CacheControl="public, max-age=600")
    manifest = {"version": ver, "url": base + os.path.basename(key), "sha256": sha, "size": len(data), "notes": notes}
    c.put_object(Bucket=bucket, Key=f"{prefix}{plat}.json", Body=json.dumps(manifest, ensure_ascii=False, indent=1).encode(),
                 ContentType="application/json; charset=utf-8", ACL="public-read", CacheControl="no-cache")
    print(f"↑ {key} {len(data)//1024//1024} МБ, манифест {base}{plat}.json → {ver}")
PYEOF
