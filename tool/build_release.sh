#!/usr/bin/env bash
# 构建正式包，输出到 build/release/<版本>/，之后拖进「Chher 发布台」发布。
#
# 用法（在仓库根目录执行）：
#   tool/build_release.sh 1.0.2             # arm64-v8a + armeabi-v7a 两个包
#   tool/build_release.sh 1.0.2 --universal # 另外再打一个通用包，用于直接分发
#
# versionCode 由版本号算出：主×10000 + 次×100 + 修订，例如 1.0.2 → 10002。
# 环境变量 CHH_UPDATE_ENDPOINTS 可覆盖打进包里的更新地址（逗号分隔），不设时用代码里的内置地址。
set -euo pipefail
cd "$(dirname "$0")/.."

usage() { sed -n '2,9p' "$0"; exit 2; }
[[ $# -ge 1 ]] || usage
NAME=$1
UNIVERSAL=0
[[ ${2:-} == --universal ]] && UNIVERSAL=1
[[ $NAME =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || { echo "版本号格式应为 主.次.修订，例如 1.0.2" >&2; exit 2; }
(( BASH_REMATCH[2] < 100 && BASH_REMATCH[3] < 100 )) || { echo "次版本和修订号都必须小于 100" >&2; exit 2; }
CODE=$(( BASH_REMATCH[1] * 10000 + BASH_REMATCH[2] * 100 + BASH_REMATCH[3] ))
[[ -f android/key.properties ]] || { echo "缺少 android/key.properties，无法用正式签名打包" >&2; exit 1; }

OUT=build/release/$NAME
mkdir -p "$OUT"
STAMP=$(date +%Y%m%d%H%M)
AAPT2=$(ls -d "${ANDROID_HOME:-$HOME/Library/Android/sdk}"/build-tools/*/aapt2 | tail -1)
DEFINES=(--dart-define=app_version="$NAME" --dart-define=build_stamp="$STAMP")
[[ -n ${CHH_UPDATE_ENDPOINTS:-} ]] && DEFINES+=(--dart-define=CHH_UPDATE_ENDPOINTS="$CHH_UPDATE_ENDPOINTS")

TARGETS=(android-arm64:arm64-v8a android-arm:armeabi-v7a)
(( UNIVERSAL )) && TARGETS+=(android-arm,android-arm64,android-x64:universal)
for PAIR in "${TARGETS[@]}"; do
  TP=${PAIR%%:*} ABI=${PAIR##*:}
  # 不用 --split-per-abi：它会给 versionCode 加架构偏移（arm64 +2000），
  # 装了这种包的手机会以为自己版本更高，再也收不到更新。按架构各构建一次，版本号保持一致。
  flutter build apk --release --target-platform "$TP" --build-name="$NAME" --build-number="$CODE" "${DEFINES[@]}"
  APK=$OUT/chher-$NAME-$ABI.apk
  [[ $ABI == universal ]] && APK=$OUT/chher-$NAME.apk
  cp build/app/outputs/flutter-apk/app-release.apk "$APK"
  VC=$("$AAPT2" dump badging "$APK" | sed -n "s/.*versionCode='\([0-9]*\)'.*/\1/p" | head -1)
  [[ $VC == "$CODE" ]] || { echo "$APK 的 versionCode 是 ${VC}，应为 ${CODE}" >&2; rm -f "$APK"; exit 1; }
done

echo
echo "已生成（versionCode ${CODE}）："
ls -lh "$OUT"/*.apk | awk '{print "  " $5 "  " $NF}'
echo "打开「Chher 发布台」，把 $OUT 里的 arm64-v8a 和 armeabi-v7a 两个包拖进“发布新版本”。"
