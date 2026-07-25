#!/bin/bash
# 从 SF Symbol "moon.zzz" 生成 KeepAwake App 的完整 .icns 图标集
#
# 输出:
#   build/KeepAwake.iconset/      macOS 需要的 iconset 目录（含所有分辨率）
#   build/AppIcon.icns            最终 .icns 文件
#   build/AppIcon-1024.png        主 PNG（用于 DMG / 文档）
#
# 用法:
#   bash icons.sh

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
BUILD="$HERE/build"
ICONSET="$BUILD/KeepAwake.iconset"
OUT_ICNS="$BUILD/AppIcon.icns"

# 必须尺寸（macOS App icon 标准）
SIZES=(16 32 64 128 256 512 1024)

# 单色 SF Symbol 没法直接做 macOS 标准的多分辨率图标（macOS 期望每分辨率独立 PNG）。
# 思路：用 Swift 一次性渲染 1024x1024 主图，再用 sips 缩到各尺寸（SwiftUI 抗锯齿更稳）。

mkdir -p "$ICONSET" "$BUILD"

# ---------- 1. 用 Swift 渲染 1024×1024 主图 ----------
cat > /tmp/render_icon.swift <<'SWIFT'
import AppKit
import SwiftUI

let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
// 圆角矩形背景（macOS Big Sur+ 风格）
let bgRect = NSRect(x: 0, y: 0, width: size, height: size)
let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: size * 0.225, yRadius: size * 0.225)
NSColor(red: 0.12, green: 0.13, blue: 0.18, alpha: 1.0).setFill()
bgPath.fill()

// 渐变叠加（让图标不死板）
if let grad = NSGradient(colors: [
    NSColor(red: 0.22, green: 0.24, blue: 0.32, alpha: 1.0),
    NSColor(red: 0.06, green: 0.07, blue: 0.10, alpha: 1.0)
]) {
    grad.draw(in: bgPath, angle: 270)
}

// 月亮 + 三个 zzz
let cfg = NSImage.SymbolConfiguration(pointSize: size * 0.7, weight: .medium)
if let moon = NSImage(systemSymbolName: "moon.zzz.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(cfg) {
    let tinted = moon.tinted(with: NSColor.white)
    let drawSize = moon.size
    let x = (size - drawSize.width) / 2
    let y = (size - drawSize.height) / 2 - size * 0.02
    tinted.draw(in: NSRect(x: x, y: y, width: drawSize.width, height: drawSize.height),
                from: .zero, operation: .sourceOver, fraction: 1.0)
}

img.unlockFocus()

if let tiff = img.tiffRepresentation,
   let rep = NSBitmapImageRep(data: tiff),
   let png = rep.representation(using: .png, properties: [:]) {
    try? png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}

extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let copy = self.copy() as! NSImage
        copy.lockFocus()
        color.set()
        NSRect(origin: .zero, size: copy.size).fill(using: .sourceAtop)
        copy.unlockFocus()
        return copy
    }
}
SWIFT

swiftc -O /tmp/render_icon.swift -framework AppKit -framework SwiftUI -o /tmp/render_icon
/tmp/render_icon "$BUILD/AppIcon-1024.png"
echo "✓ 生成 1024×1024 主图: $BUILD/AppIcon-1024.png"

# ---------- 2. 用 sips 缩到所有 macOS 图标尺寸 ----------
for s in "${SIZES[@]}"; do
    if [[ $s -le 64 ]]; then
        # 小图标要 @1x 和 @2x 两份
        sips -z $s $s "$BUILD/AppIcon-1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
        [[ $s -eq 16 || $s -eq 32 ]] && {
            sips -z $((s*2)) $((s*2)) "$BUILD/AppIcon-1024.png" \
                --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
        }
    else
        sips -z $s $s "$BUILD/AppIcon-1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
        # 128@2x=256, 256@2x=512, 512@2x=1024
        sips -z $((s*2)) $((s*2)) "$BUILD/AppIcon-1024.png" \
            --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
    fi
done

echo "✓ 生成 iconset: $ICONSET"
ls "$ICONSET" | sort

# ---------- 3. iconutil 打包成 .icns ----------
iconutil -c icns "$ICONSET" -o "$OUT_ICNS"
echo "✓ 生成 icns: $OUT_ICNS"
ls -lh "$OUT_ICNS"