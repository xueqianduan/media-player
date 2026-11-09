#!/usr/bin/env bash
# ReelBox 开发辅助脚本（在 Git Bash 里执行）
#
#   ./tool/dev.sh run       热重载调试：改代码保存后按 r 立即生效（需 USB 调试）
#   ./tool/dev.sh install   构建 arm64 release 并直接装到手机，无需手动拷贝 APK
#   ./tool/dev.sh log       只看 App 日志（排查播放/字幕/截图问题）
#   ./tool/dev.sh devices   列出已连接设备
#
# 需要先安装 Android 平台工具（默认路径见下），或通过环境变量 ADB 指定。
set -uo pipefail

ADB="${ADB:-D:/Android/Sdk/platform-tools/adb.exe}"
APP_ID="com.example.myplayer"
APK="build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"

case "${1:-run}" in
  run)
    exec flutter run
    ;;
  install)
    echo "==> 构建 arm64 release"
    flutter build apk --release --split-per-abi || exit 1
    echo "==> 安装到设备"
    "$ADB" install -r "$APK" || exit 1
    "$ADB" shell monkey -p "$APP_ID" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
    echo "==> 已安装并启动"
    ;;
  log)
    "$ADB" logcat -s flutter | grep --line-buffered "ReelBox"
    ;;
  devices)
    "$ADB" devices -l
    ;;
  *)
    echo "用法: $0 [run|install|log|devices]"
    exit 1
    ;;
esac
