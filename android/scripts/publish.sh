#!/bin/zsh
# Выкладка APK «Бупень» для самообновления: собрать release, положить APK по архитектурам
# и манифест android.json в публичный бакет hyax-public/installers/bypen/ (тот же, что у
# установщиков мессенджера; ключи — ~/.hyax-s3.env, boto3 — ~/.hyax-venv, как у ~/hyax-deploy-s3.sh).
#   scripts/publish.sh "что нового"      # текст попадёт в карточку обновления
set -eu
cd "$(dirname "$0")/.."
NOTES=${1:-}
PY=~/.hyax-venv/bin/python
[[ -x $PY ]] || { echo "нет ~/.hyax-venv с boto3"; exit 1; }
[[ -f ~/.hyax-s3.env ]] || { echo "нет ~/.hyax-s3.env"; exit 1; }
export JAVA_HOME=$(/usr/libexec/java_home -v 21)
./gradlew --no-daemon -q assembleRelease
CODE=$(git rev-list --count HEAD)
set -a; source ~/.hyax-s3.env; set +a
$PY - "$CODE" "0.1.$CODE" "$NOTES" <<'PYEOF'
import hashlib, json, os, sys
import boto3
code, name, notes = int(sys.argv[1]), sys.argv[2], sys.argv[3]
bucket, prefix = "hyax-public", "installers/bypen/"
base = f"https://storage.yandexcloud.net/{bucket}/{prefix}"
c = boto3.client("s3", endpoint_url=os.environ["S3_ENDPOINT_URL"], region_name=os.environ.get("S3_REGION", "ru-central1"),
                 aws_access_key_id=os.environ["S3_ACCESS_KEY_ID"], aws_secret_access_key=os.environ["S3_SECRET_ACCESS_KEY"])
abis = {}
for abi in ("arm64-v8a", "armeabi-v7a", "x86_64"):
    path = f"app/build/outputs/apk/release/app-{abi}-release.apk"
    data = open(path, "rb").read()
    sha = hashlib.sha256(data).hexdigest()
    key = f"{prefix}bypen-{abi}-{code}.apk"
    c.put_object(Bucket=bucket, Key=key, Body=data, ContentType="application/vnd.android.package-archive", ACL="public-read",
                 CacheControl="public, max-age=31536000", Metadata={"sha256": sha})
    abis[abi] = {"url": base + os.path.basename(key), "sha256": sha, "size": len(data)}
    print(f"↑ {key} {len(data)//1024//1024} МБ")
# bypen.apk без номера — постоянная ссылка на arm64 для сайта
arm = open("app/build/outputs/apk/release/app-arm64-v8a-release.apk", "rb").read()
c.put_object(Bucket=bucket, Key=prefix + "bypen.apk", Body=arm, ContentType="application/vnd.android.package-archive", ACL="public-read", CacheControl="public, max-age=600")
manifest = {"versionCode": code, "versionName": name, "url": abis["arm64-v8a"]["url"], "sha256": abis["arm64-v8a"]["sha256"], "notes": notes, "abis": abis}
c.put_object(Bucket=bucket, Key=prefix + "android.json", Body=json.dumps(manifest, ensure_ascii=False, indent=1).encode(), ContentType="application/json; charset=utf-8", ACL="public-read", CacheControl="no-cache")
print("манифест:", base + "android.json", "→", code, name)
PYEOF
