#!/bin/zsh
# Выкладка Бупеня для мака с самообновлением: подписанная универсальная сборка → заверение
# Apple (notarytool, профиль связки ключей hyax) → скрепка → архив и манифест mac.json в
# публичный бакет hyax-public/installers/bypen/ (ключи ~/.hyax-s3.env, boto3 ~/.hyax-venv).
#   DEVELOPER_DIR=/Volumes/Ext/Applications/Xcode.app/Contents/Developer scripts/publish-mac.sh "что нового"
set -eu
cd "$(dirname "$0")/.."
ROOT=$(cd .. && pwd)
NOTES=${1:-}
PY=~/.hyax-venv/bin/python
[[ -x $PY ]] || { echo "нет ~/.hyax-venv с boto3"; exit 1; }
[[ -f ~/.hyax-s3.env ]] || { echo "нет ~/.hyax-s3.env"; exit 1; }
N=$(git rev-list --count HEAD)
V="0.1.$N"
export BYPEN_BUILD=$N BYPEN_VERSION=$V
APP="$ROOT/desktop/dist/mac/Bypen.app"
ZIP="$ROOT/desktop/dist/bypen-mac-$V.zip"
# BYPEN_SKIP_BUILD=1 — взять уже собранную build-mac.sh сборку этого же номера
if [[ ${BYPEN_SKIP_BUILD:-} == 1 ]]; then
  [[ -f $ZIP ]] || { echo "нет $ZIP — сначала scripts/build-mac.sh"; exit 1; }
  [[ $(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP/Contents/Info.plist") == "$N" ]] || { echo "в $APP не сборка $N"; exit 1; }
else
  zsh scripts/build-mac.sh
fi
echo "заверение у Apple…"
xcrun notarytool submit "$ZIP" --keychain-profile "${NOTARY_PROFILE:-hyax}" --wait
xcrun stapler staple "$APP"
spctl -a -t exec "$APP"
# архив заново — уже со скрепкой внутри
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
set -a; source ~/.hyax-s3.env; set +a
$PY - "$N" "$V" "$NOTES" "$ZIP" <<'PYEOF'
import hashlib, json, os, sys
import boto3
build, ver, notes, path = int(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
bucket, prefix = "hyax-public", "installers/bypen/"
base = f"https://storage.yandexcloud.net/{bucket}/{prefix}"
c = boto3.client("s3", endpoint_url=os.environ["S3_ENDPOINT_URL"], region_name=os.environ.get("S3_REGION", "ru-central1"),
                 aws_access_key_id=os.environ["S3_ACCESS_KEY_ID"], aws_secret_access_key=os.environ["S3_SECRET_ACCESS_KEY"])
data = open(path, "rb").read()
sha = hashlib.sha256(data).hexdigest()
key = f"{prefix}bypen-mac-{ver}.zip"
c.put_object(Bucket=bucket, Key=key, Body=data, ContentType="application/zip", ACL="public-read",
             CacheControl="public, max-age=31536000", Metadata={"sha256": sha})
# постоянная ссылка для первой установки
c.put_object(Bucket=bucket, Key=prefix + "bypen-mac.zip", Body=data, ContentType="application/zip", ACL="public-read", CacheControl="public, max-age=600")
manifest = {"version": ver, "build": build, "url": base + os.path.basename(key), "sha256": sha, "size": len(data), "notes": notes}
c.put_object(Bucket=bucket, Key=prefix + "mac.json", Body=json.dumps(manifest, ensure_ascii=False, indent=1).encode(),
             ContentType="application/json; charset=utf-8", ACL="public-read", CacheControl="no-cache")
print(f"↑ {key} {len(data)//1024//1024} МБ")
print("манифест:", base + "mac.json", "→", build, ver)
PYEOF
