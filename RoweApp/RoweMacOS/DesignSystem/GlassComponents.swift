import AppKit
import SwiftUI
import RoweCore

/// Hides/shows the macOS traffic light buttons cleanly when the sidebar is collapsed.
struct RoweWindowConfigurator: NSViewRepresentable {
    let hideTrafficLights: Bool

    func makeNSView(context: Context) -> NSView {
        let view = WindowHookView()
        view.hideTrafficLights = hideTrafficLights
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let hook = nsView as? WindowHookView {
            hook.hideTrafficLights = hideTrafficLights
        }
        if let window = nsView.window {
            configure(window, hideTrafficLights: hideTrafficLights)
        }
    }

    private func configure(_ window: NSWindow, hideTrafficLights: Bool) {
        let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        for type in buttons {
            guard let btn = window.standardWindowButton(type) else { continue }
            btn.isHidden = hideTrafficLights
        }
    }

    private final class WindowHookView: NSView {
        var hideTrafficLights: Bool = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(type)?.isHidden = hideTrafficLights
            }
        }
    }
}

/// Wraps macOS 26's native `NSGlassEffectView` for custom popups and menus,
/// falling back cleanly to `NSVisualEffectView` on macOS 15.
struct RoweNativeGlassBackdrop: NSViewRepresentable {
    let cornerRadius: CGFloat
    let isClear: Bool

    init(cornerRadius: CGFloat = 14, isClear: Bool = false) {
        self.cornerRadius = cornerRadius
        self.isClear = isClear
    }

    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.style = isClear ? .clear : .regular
            return glass
        } else {
            let fx = NSVisualEffectView()
            fx.material = isClear ? .hudWindow : .popover
            fx.blendingMode = .withinWindow
            fx.state = .active
            fx.wantsLayer = true
            fx.layer?.cornerRadius = cornerRadius
            fx.layer?.cornerCurve = .continuous
            return fx
        }
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if #available(macOS 26.0, *), let glass = nsView as? NSGlassEffectView {
            glass.cornerRadius = cornerRadius
            glass.style = isClear ? .clear : .regular
        } else {
            nsView.layer?.cornerRadius = cornerRadius
        }
    }
}

/// Applies native macOS 26+ Liquid Glass when available, falling back cleanly
/// to translucent material + subtle specular rim on macOS 15.
struct LiquidGlassSurfaceModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let interactive: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.55), .white.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
                )
                .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
        }
    }
}

extension View {
    func roweGlass<S: InsettableShape>(in shape: S, interactive: Bool = true) -> some View {
        modifier(LiquidGlassSurfaceModifier(shape: shape, interactive: interactive))
    }

    func roweGlassCapsule(interactive: Bool = true) -> some View {
        roweGlass(in: Capsule(), interactive: interactive)
    }

    func roweGlassRoundedRect(radius: CGFloat = 16, interactive: Bool = true) -> some View {
        roweGlass(in: RoundedRectangle(cornerRadius: radius, style: .continuous), interactive: interactive)
    }

    /// Standard interactive Liquid Glass bar for all text inputs & search fields.
    func roweGlassInput(cornerRadius: CGFloat = 11) -> some View {
        self
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .roweGlassRoundedRect(radius: cornerRadius, interactive: true)
    }
}

/// Native macOS 26 Liquid Glass lens segmented control (`GlassEffectContainer` + `glassEffectID`)
/// with instant press-and-hold lift (`minimumDistance: 0` + `.clear.interactive()` + scale)
/// and smooth drag-scrubbing.
struct LiquidGlassSegmentedControl<Item: Hashable>: View {
    enum SegmentContent {
        case title(String)
        case symbol(String, accessibilityLabel: String?)
    }

    let items: [Item]
    @Binding var selection: Item
    let height: CGFloat
    let contentForItem: (Item) -> SegmentContent

    @Namespace private var lensNamespace
    @State private var isHolding = false

    init(
        items: [Item],
        selection: Binding<Item>,
        height: CGFloat = 32,
        title: @escaping (Item) -> String
    ) {
        self.items = items
        self._selection = selection
        self.height = height
        self.contentForItem = { .title(title($0)) }
    }

    init(
        items: [Item],
        selection: Binding<Item>,
        height: CGFloat = 32,
        systemImage: @escaping (Item) -> String,
        accessibilityLabel: ((Item) -> String)? = nil
    ) {
        self.items = items
        self._selection = selection
        self.height = height
        self.contentForItem = { .symbol(systemImage($0), accessibilityLabel: accessibilityLabel?($0)) }
    }

    var body: some View {
        if #available(macOS 26.0, *) {
            GeometryReader { geo in
                let segmentWidth = max(1, (geo.size.width - 6) / CGFloat(max(1, items.count)))
                GlassEffectContainer(spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            let isSelected = item == selection
                            segmentLabel(for: item, isSelected: isSelected)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(Capsule())
                                .background {
                                    if isSelected {
                                        Capsule()
                                            .fill(.clear)
                                            .glassEffect(
                                                isHolding ? .clear.interactive() : .regular.interactive(),
                                                in: Capsule()
                                            )
                                            .glassEffectID("liquidLens", in: lensNamespace)
                                            .scaleEffect(isHolding ? 1.12 : 1.0)
                                            .shadow(color: .black.opacity(isHolding ? 0.25 : 0), radius: 8, y: 2)
                                            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isHolding)
                                    }
                                }
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAction {
                                    guard selection != item else { return }
                                    HapticsManager.shared.tap()
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.76)) {
                                        selection = item
                                    }
                                }
                        }
                    }
                    .padding(3)
                    .frame(height: height)
                    .glassEffect(.regular, in: Capsule())
                }
                .contentShape(Capsule())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isHolding { isHolding = true }
                            let rawIdx = Int(((value.location.x - 3) / segmentWidth).rounded(.down))
                            let clampedIdx = min(max(0, rawIdx), items.count - 1)
                            let target = items[clampedIdx]
                            if target != selection {
                                HapticsManager.shared.tap()
                                withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.80)) {
                                    selection = target
                                }
                            }
                        }
                        .onEnded { _ in
                            isHolding = false
                        }
                )
            }
            .frame(height: height)
        } else {
            Picker("", selection: $selection) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    segmentLabel(for: item, isSelected: item == selection).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(height: height)
        }
    }

    @ViewBuilder
    private func segmentLabel(for item: Item, isSelected: Bool) -> some View {
        switch contentForItem(item) {
        case .title(let text):
            Text(text)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
        case .symbol(let name, let accLabel):
            Image(systemName: name)
                .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .accessibilityLabel(accLabel ?? name)
        }
    }
}

struct GlassCircleButton: View {
    let systemImage: String
    let helpText: String
    let size: CGFloat
    let iconSize: CGFloat
    let action: () -> Void

    init(
        systemImage: String,
        helpText: String = "",
        size: CGFloat = 32,
        iconSize: CGFloat? = nil,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.helpText = helpText
        self.size = size
        self.iconSize = iconSize ?? (size >= 30 ? 13 : 11)
        self.action = action
    }

    var body: some View {
        Button {
            HapticsManager.shared.tap()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(RowePressScaleButtonStyle())
        .frame(width: size, height: size)
        .roweGlass(in: Circle(), interactive: true)
        .help(helpText)
    }
}

struct GlassPillButton: View {
    let title: String
    let systemImage: String?
    let tint: Color?
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, tint: Color? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button {
            HapticsManager.shared.tap()
            action()
        } label: {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .medium))
                }
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
            }
            .foregroundStyle(tint ?? .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill((tint ?? .clear).opacity(tint == nil ? 0 : 0.14))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(RowePressScaleButtonStyle())
        .roweGlassCapsule(interactive: true)
    }
}

/// Custom neutral Liquid Glass dropdown picker (replaces native blue-accented macOS Picker).
/// Uses NSGlassEffectView + concentric corner radii (outer 14, padding 5, inner 9).
struct RoweGlassMenuPicker<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let titleForItem: (Item) -> String
    var onSelect: ((Item) -> Void)?

    @State private var isOpen = false
    @State private var hoveredItem: Item?

    init(
        items: [Item],
        selection: Binding<Item>,
        titleForItem: @escaping (Item) -> String,
        onSelect: ((Item) -> Void)? = nil
    ) {
        self.items = items
        self._selection = selection
        self.titleForItem = titleForItem
        self.onSelect = onSelect
    }

    var body: some View {
        Button {
            HapticsManager.shared.tap()
            withAnimation(.spring(response: 0.26, dampingFraction: 0.8)) {
                isOpen.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Text(titleForItem(selection))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 5.5)
            .contentShape(Capsule())
        }
        .buttonStyle(RowePressScaleButtonStyle())
        .roweGlassCapsule(interactive: true)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(items, id: \.self) { item in
                    let isSelected = item == selection
                    let isHovered = hoveredItem == item
                    Button {
                        HapticsManager.shared.tap()
                        selection = item
                        onSelect?(item)
                        isOpen = false
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.primary)
                                .opacity(isSelected ? 1 : 0)
                                .frame(width: 14)

                            Text(titleForItem(item))
                                .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(.primary)

                            Spacer(minLength: 12)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6.5)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(isHovered || isSelected ? Color.primary.opacity(isHovered ? 0.11 : 0.06) : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        hoveredItem = hovering ? item : (hoveredItem == item ? nil : hoveredItem)
                    }
                }
            }
            .padding(5)
            .frame(minWidth: 165)
            .background(RoweNativeGlassBackdrop(cornerRadius: 14))
            .presentationBackground(.clear)
        }
    }
}

/// Custom circular Liquid Glass trigger button with a matching NSGlassEffectView action popup.
/// Solves SwiftUI `Menu` shrinking/blue-tinting circular glass buttons.
struct RoweGlassActionMenuItem: Identifiable {
    let id: String
    let title: String
    let icon: String?
    let isSelected: Bool
    let isDestructive: Bool
    let action: () -> Void

    init(
        id: String? = nil,
        title: String,
        icon: String? = nil,
        isSelected: Bool = false,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.id = id ?? title
        self.title = title
        self.icon = icon
        self.isSelected = isSelected
        self.isDestructive = isDestructive
        self.action = action
    }
}

struct RoweGlassCircleMenu: View {
    let systemImage: String
    let helpText: String
    let size: CGFloat
    let items: [RoweGlassActionMenuItem]

    @State private var isOpen = false
    @State private var hoveredId: String?

    init(
        systemImage: String,
        helpText: String = "",
        size: CGFloat = 32,
        items: [RoweGlassActionMenuItem]
    ) {
        self.systemImage = systemImage
        self.helpText = helpText
        self.size = size
        self.items = items
    }

    var body: some View {
        GlassCircleButton(systemImage: systemImage, helpText: helpText, size: size) {
            isOpen.toggle()
        }
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(items) { item in
                    let isHovered = hoveredId == item.id
                    Button {
                        HapticsManager.shared.tap()
                        isOpen = false
                        item.action()
                    } label: {
                        HStack(spacing: 8) {
                            if let icon = item.icon {
                                Image(systemName: icon)
                                    .font(.system(size: 12))
                                    .foregroundStyle(item.isDestructive ? .red : .secondary)
                                    .frame(width: 16)
                            }
                            Text(item.title)
                                .font(.system(size: 12.5, weight: item.isSelected ? .semibold : .regular))
                                .foregroundStyle(item.isDestructive ? .red : .primary)
                            Spacer(minLength: 10)
                            if item.isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(.primary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6.5)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(isHovered ? Color.primary.opacity(0.11) : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        hoveredId = hovering ? item.id : (hoveredId == item.id ? nil : hoveredId)
                    }
                }
            }
            .padding(5)
            .frame(minWidth: 180)
            .background(RoweNativeGlassBackdrop(cornerRadius: 14))
            .presentationBackground(.clear)
        }
    }
}

/// Clean right-aligned Liquid Glass stepper (replaces tiny native macOS NSStepper).
struct RoweGlassStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let displayValue: String

    var body: some View {
        HStack(spacing: 4) {
            Button {
                guard value > range.lowerBound else { return }
                HapticsManager.shared.tap()
                value -= 1
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(value > range.lowerBound ? .primary : .tertiary)
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(RowePressScaleButtonStyle())

            Text(displayValue)
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .monospacedDigit()
                .frame(minWidth: 44)

            Button {
                guard value < range.upperBound else { return }
                HapticsManager.shared.tap()
                value += 1
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(value < range.upperBound ? .primary : .tertiary)
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(RowePressScaleButtonStyle())
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .roweGlassCapsule(interactive: true)
    }
}

/// Compact `#image N` Liquid Glass chip: click to open a steady, non-jumping image preview
/// popover with one-click Copy Image support.
struct TaskImageChip: View {
    let index: Int
    let base64: String
    var onRemove: (() -> Void)? = nil

    @State private var isPreviewOpen = false
    @State private var didCopy = false

    private var nsImage: NSImage? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        return NSImage(data: data)
    }

    var body: some View {
        HStack(spacing: 4) {
            Button {
                HapticsManager.shared.tap()
                isPreviewOpen.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "photo")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("#image \(index)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let onRemove {
                Button {
                    HapticsManager.shared.tap()
                    isPreviewOpen = false
                    onRemove()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .roweGlassCapsule(interactive: true)
        .popover(isPresented: $isPreviewOpen, arrowEdge: .bottom) {
            if let img = nsImage {
                VStack(spacing: 8) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 320, maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    HStack(spacing: 8) {
                        Button {
                            HapticsManager.shared.tap()
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.writeObjects([img])
                            withAnimation(.easeInOut(duration: 0.16)) { didCopy = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { didCopy = false }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 11, weight: .semibold))
                                Text(didCopy ? "Copied" : "Copy Image")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundStyle(didCopy ? .green : .primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                        }
                        .buttonStyle(RowePressScaleButtonStyle())

                        Spacer()

                        Button("Close") {
                            isPreviewOpen = false
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(RoweNativeGlassBackdrop(cornerRadius: 14))
                .presentationBackground(.clear)
            }
        }
    }
}

enum TaskImageEncoder {
    /// Compresses an NSImage (from pasteboard or file picker) to compact base64 JPEG (max 900px).
    static func encodeToBase64(_ image: NSImage, maxDimension: CGFloat = 900) -> String? {
        let orig = image.size
        guard orig.width > 0, orig.height > 0 else { return nil }
        let scale = min(1.0, maxDimension / max(orig.width, orig.height))
        let target = NSSize(width: round(orig.width * scale), height: round(orig.height * scale))
        let resized = NSImage(size: target)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: target), from: .zero, operation: .copy, fraction: 1.0)
        resized.unlockFocus()
        guard let tiff = resized.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.78]) else {
            return nil
        }
        return jpeg.base64EncodedString()
    }
}
