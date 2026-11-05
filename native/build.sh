#!/bin/zsh
set -eu
cd "${0:A:h}/.."
bundle="$PWD/.local/MosaicoMusicHelper.app"
mkdir -p "$bundle/Contents/MacOS" .local/swift-cache
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>local.wuhao.mosaico-music-helper</string><key>CFBundleName</key><string>Mosaico 音乐助手</string><key>CFBundleExecutable</key><string>MusicHelper</string><key>CFBundlePackageType</key><string>APPL</string><key>NSBluetoothAlwaysUsageDescription</key><string>扫描和连接你选择的蓝牙音箱，用于音乐播放。</string><key>NSSpeechRecognitionUsageDescription</key><string>在本机将 ESP32 麦克风录到的歌名转换为搜索文字。</string><key>NSMicrophoneUsageDescription</key><string>仅在你主动发起语音搜歌时使用麦克风。</string><key>LSUIElement</key><true/></dict></plist>
PLIST
/usr/bin/swiftc -module-cache-path "$PWD/.local/swift-cache" native/MusicHelper.swift -o "$bundle/Contents/MacOS/MusicHelper"
/usr/bin/codesign --force --sign - --identifier local.wuhao.mosaico-music-helper "$bundle" >/dev/null
echo "已构建当前 Mac 的音频与蓝牙助手"
