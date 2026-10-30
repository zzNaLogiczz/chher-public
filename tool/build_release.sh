#!/usr/bin/env bash
# 构建正式通用包，保留 ARM64、ARMv7 和 x86_64，供全部客户端统一更新。
#
# 用法（在仓库根目录执行）：
#   tool/build_release.sh 1.0.4
#   tool/build_release.sh 1.0.4 --universal # 兼容旧命令，结果相同
#
# 输出 build/release/<版本>/chher-<版本>.apk；symbols/ 中的符号用于崩溃解析。
# CHH_UPDATE_ENDPOINTS 可覆盖内置更新地址（逗号分隔）。
set -euo pipefail
cd "$(dirname "$0")/.."

usage() { sed -n '2,8p' "$0"; exit 2; }
[[ $# -ge 1 && $# -le 2 ]] || usage
[[ $# -lt 2 || $2 == --universal ]] || usage
NAME=$1
[[ $NAME =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || { echo "版本号格式应为 主.次.修订，例如 1.0.4" >&2; exit 2; }
(( BASH_REMATCH[2] < 100 && BASH_REMATCH[3] < 100 )) || { echo "次版本和修订号都必须小于 100" >&2; exit 2; }
CODE=$(( BASH_REMATCH[1] * 10000 + BASH_REMATCH[2] * 100 + BASH_REMATCH[3] ))
[[ -f android/key.properties ]] || { echo "缺少 android/key.properties，无法用正式签名打包" >&2; exit 1; }

OUT=build/release/$NAME
mkdir -p "$OUT/symbols"
STAMP=$(date +%Y%m%d%H%M)
AAPT2=$(ls -d "${ANDROID_HOME:-$HOME/Library/Android/sdk}"/build-tools/*/aapt2 | tail -1)
DEFINES=(--dart-define=app_version="$NAME" --dart-define=build_stamp="$STAMP")
[[ -n ${CHH_UPDATE_ENDPOINTS:-} ]] && DEFINES+=(--dart-define=CHH_UPDATE_ENDPOINTS="$CHH_UPDATE_ENDPOINTS")

flutter build apk --release --target-platform android-arm,android-arm64,android-x64 \
  --build-name="$NAME" --build-number="$CODE" --split-debug-info="$OUT/symbols" "${DEFINES[@]}"
APK=$OUT/chher-$NAME.apk
cp build/app/outputs/flutter-apk/app-release.apk "$APK"
BADGING=$("$AAPT2" dump badging "$APK")
VC=$(sed -n "s/.*versionCode='\([0-9]*\)'.*/\1/p" <<< "$BADGING" | head -1)
[[ $VC == "$CODE" ]] || { echo "实际 versionCode ${VC}，应为 ${CODE}" >&2; exit 1; }
ABIS=$(sed -n 's/^native-code: //p' <<< "$BADGING")
for ABI in arm64-v8a armeabi-v7a x86_64; do
  [[ $ABIS == *"'$ABI'"* ]] || { echo "通用包缺少 ${ABI}，请勿发布" >&2; exit 1; }
done

echo "已生成正式通用包（versionCode ${CODE}）："
ls -lh "$APK" | awk '{print "  " $5 "  " $NF}'
echo "在「Chher 发布台」中只选择 ${APK}，即可供全部支持的手机更新。"
