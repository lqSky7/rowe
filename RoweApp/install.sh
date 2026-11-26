#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
APP_NAME="Rowe"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
INSTALL_DIR="/Applications"
BUILD_ONLY=false

for arg in "$@"; do
    case "$arg" in
        --build-only) BUILD_ONLY=true ;;
        --install-dir=*) INSTALL_DIR="${arg#*=}" ;;
        -h|--help)
            echo "Usage: ./install.sh [--build-only] [--install-dir=/Applications]"
            exit 0
            ;;
    esac
done

# Select an SDK that works cleanly with the active Swift toolchain.
# CommandLineTools on macOS 27 ships MacOSX26.x SDK alongside MacOSX27.x without Xcode's SwiftUIMacros plugin.
select_sdk() {
    if [[ -n "${ROWE_SDK:-}" && -d "$ROWE_SDK" ]]; then
        echo "$ROWE_SDK"
        return
    fi

    local default_sdk
    default_sdk="$(xcrun --show-sdk-path)"
    local dev_dir
    dev_dir="$(xcode-select -p)"

    if [[ "$dev_dir" == *"/CommandLineTools"* ]]; then
        local sdk26
        sdk26="$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26*.sdk 2>/dev/null | sort -V | tail -n 1 || true)"
        if [[ -n "$sdk26" && -d "$sdk26" ]]; then
            echo "$sdk26"
            return
        fi
    fi

    echo "$default_sdk"
}

SDK="$(select_sdk)"
ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macosx15.0"

echo "==> Building $APP_NAME ($TARGET)"
echo "    SDK: $SDK"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/core" \
         "$APP_BUNDLE/Contents/MacOS" \
         "$APP_BUNDLE/Contents/Frameworks" \
         "$APP_BUNDLE/Contents/Resources"

CORE_SOURCES=()
while IFS= read -r file; do
    CORE_SOURCES+=("$file")
done < <(find "$SCRIPT_DIR/RoweCore/Sources" -name '*.swift' | sort)

APP_SOURCES=()
while IFS= read -r file; do
    APP_SOURCES+=("$file")
done < <(find "$SCRIPT_DIR/RoweMacOS" "$SCRIPT_DIR/RoweShared" -name '*.swift' | sort)

echo "==> Compiling RoweCore (${#CORE_SOURCES[@]} files)..."
swiftc \
    -parse-as-library \
    -O \
    -whole-module-optimization \
    -swift-version 6 \
    -target "$TARGET" \
    -sdk "$SDK" \
    -module-name RoweCore \
    -emit-module \
    -emit-module-path "$BUILD_DIR/core/RoweCore.swiftmodule" \
    -emit-library \
    -Xlinker -install_name -Xlinker "@rpath/libRoweCore.dylib" \
    -o "$BUILD_DIR/core/libRoweCore.dylib" \
    "${CORE_SOURCES[@]}"

echo "==> Compiling RoweMacOS (${#APP_SOURCES[@]} files)..."
swiftc \
    -parse-as-library \
    -O \
    -whole-module-optimization \
    -swift-version 6 \
    -target "$TARGET" \
    -sdk "$SDK" \
    -module-name Rowe \
    -I "$BUILD_DIR/core" \
    -L "$BUILD_DIR/core" \
    -lRoweCore \
    -framework SwiftUI \
    -framework AppKit \
    -framework Metal \
    -framework MetalKit \
    -framework QuartzCore \
    -framework UniformTypeIdentifiers \
    -Xlinker -rpath -Xlinker "@executable_path/../Frameworks" \
    -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" \
    "${APP_SOURCES[@]}"

cp "$BUILD_DIR/core/libRoweCore.dylib" "$APP_BUNDLE/Contents/Frameworks/libRoweCore.dylib"

# Generate AppIcon.icns from smoothed Rowe vector geometry + bundle Rowe.icon (Tahoe Light/Dark/Clear/Tinted)
echo "==> Generating AppIcon.icns..."
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"

cat > "$BUILD_DIR/gen_icon.swift" <<'SWIFT'
import AppKit
import CoreGraphics

let outDir = CommandLine.arguments[1]

func renderIcon(px: Int, to path: String) {
    let size = CGFloat(px)
    guard let ctx = CGContext(
        data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return }

    // Flip to top-left origin so SVG coordinates map directly
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: 1, y: -1)

    let inset = size * 0.08
    let box = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = box.width * 0.225
    let squircle = CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let colors = [
        CGColor(red: 0.988, green: 0.984, blue: 0.972, alpha: 1),
        CGColor(red: 0.910, green: 0.890, blue: 0.847, alpha: 1)
    ] as CFArray
    if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
        ctx.drawLinearGradient(grad, start: CGPoint(x: box.minX, y: box.minY), end: CGPoint(x: box.maxX, y: box.maxY), options: [])
    }
    ctx.restoreGState()

    ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.09))
    ctx.setLineWidth(max(1.0, size * 0.008))
    ctx.addPath(squircle)
    ctx.strokePath()

    // Draw smoothed Rowe ribbon paths
    let pad = box.width * 0.11
    let inner = box.insetBy(dx: pad, dy: pad)
    let scale = min(inner.width / 1000.0, inner.height / 750.0)
    let dx = inner.midX - 500.0 * scale
    let dy = inner.midY - 375.0 * scale
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: dx + x * scale, y: dy + y * scale) }

    let glyph = CGMutablePath()
    glyph.move(to: pt(18, 292))
    glyph.addCurve(to: pt(62, 278), control1: pt(34, 282), control2: pt(48, 278))
    glyph.addCurve(to: pt(198, 382), control1: pt(114, 278), control2: pt(134, 382))
    glyph.addCurve(to: pt(446, 300), control1: pt(268, 382), control2: pt(356, 336))
    glyph.addCurve(to: pt(690, 232), control1: pt(536, 264), control2: pt(628, 232))
    glyph.addCurve(to: pt(780, 318), control1: pt(744, 232), control2: pt(780, 268))
    glyph.addCurve(to: pt(650, 460), control1: pt(780, 376), control2: pt(728, 424))
    glyph.addCurve(to: pt(286, 558), control1: pt(534, 514), control2: pt(392, 558))
    glyph.addCurve(to: pt(236, 510), control1: pt(252, 558), control2: pt(236, 538))
    glyph.addCurve(to: pt(478, 408), control1: pt(236, 456), control2: pt(354, 408))
    glyph.addCurve(to: pt(882, 490), control1: pt(628, 408), control2: pt(764, 490))
    glyph.addCurve(to: pt(984, 458), control1: pt(928, 490), control2: pt(960, 472))

    glyph.move(to: pt(400, 180))
    glyph.addCurve(to: pt(600, 342), control1: pt(454, 184), control2: pt(594, 246))
    glyph.addCurve(to: pt(484, 445), control1: pt(605, 402), control2: pt(548, 442))
    glyph.addCurve(to: pt(296, 276), control1: pt(414, 448), control2: pt(302, 374))
    glyph.addCurve(to: pt(400, 180), control1: pt(291, 212), control2: pt(344, 176))
    glyph.closeSubpath()

    ctx.setStrokeColor(CGColor(red: 0.10, green: 0.106, blue: 0.118, alpha: 1))
    ctx.setLineWidth(max(1.4, size * 0.028))
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.addPath(glyph)
    ctx.strokePath()

    if let cgImg = ctx.makeImage() {
        let rep = NSBitmapImageRep(cgImage: cgImg)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }
}

let specs: [(String, Int)] = [
    ("icp4", 16), ("icp5", 32), ("icp6", 64),
    ("ic07", 128), ("ic08", 256), ("ic09", 512), ("ic10", 1024),
    ("ic11", 32), ("ic12", 64), ("ic13", 256), ("ic14", 512)
]

var body = Data()
for (osType, px) in specs {
    let pngPath = "\(outDir)/\(osType)_\(px).png"
    renderIcon(px: px, to: pngPath)
    if let pngData = try? Data(contentsOf: URL(fileURLWithPath: pngPath)) {
        body.append(contentsOf: osType.utf8)
        var chunkLen = UInt32(8 + pngData.count).bigEndian
        body.append(Data(bytes: &chunkLen, count: 4))
        body.append(pngData)
    }
}

var icns = Data("icns".utf8)
var totalLen = UInt32(8 + body.count).bigEndian
icns.append(Data(bytes: &totalLen, count: 4))
icns.append(body)
try icns.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
SWIFT

swiftc -sdk "$SDK" -target "$TARGET" -framework AppKit -framework CoreGraphics "$BUILD_DIR/gen_icon.swift" -o "$BUILD_DIR/gen_icon"
"$BUILD_DIR/gen_icon" "$ICONSET_DIR" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

if [[ -d "$SCRIPT_DIR/RoweMacOS/Resources/Rowe.icon" ]]; then
    cp -R "$SCRIPT_DIR/RoweMacOS/Resources/Rowe.icon" "$APP_BUNDLE/Contents/Resources/Rowe.icon"
fi

if [[ -d "$SCRIPT_DIR/RoweMacOS/Resources/Wallpapers" ]]; then
    cp -R "$SCRIPT_DIR/RoweMacOS/Resources/Wallpapers" "$APP_BUNDLE/Contents/Resources/Wallpapers"
fi

if [[ -d "$SCRIPT_DIR/RoweMacOS/Resources/Shaders" ]]; then
    cp -R "$SCRIPT_DIR/RoweMacOS/Resources/Shaders" "$APP_BUNDLE/Contents/Resources/Shaders"
fi

cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>Rowe</string>
    <key>CFBundleExecutable</key>
    <string>Rowe</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>Rowe</string>
    <key>CFBundleIdentifier</key>
    <string>com.rowe.macos</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Rowe</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Rowe Personal Workspace</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

echo "==> Signing $APP_NAME.app (ad-hoc)..."
codesign --force --sign - "$APP_BUNDLE/Contents/Frameworks/libRoweCore.dylib"
codesign --force --deep --sign - "$APP_BUNDLE"

echo "==> Built: $APP_BUNDLE"

if [[ "$BUILD_ONLY" == true ]]; then
    exit 0
fi

TARGET_APP="$INSTALL_DIR/$APP_NAME.app"
echo "==> Installing to $TARGET_APP..."

if [[ -w "$INSTALL_DIR" ]]; then
    rm -rf "$TARGET_APP"
    cp -R "$APP_BUNDLE" "$TARGET_APP"
else
    echo "    Requires administrator permission for $INSTALL_DIR"
    sudo rm -rf "$TARGET_APP"
    sudo cp -R "$APP_BUNDLE" "$TARGET_APP"
fi

echo "==> Installed successfully! Launch with: open \"$TARGET_APP\""
