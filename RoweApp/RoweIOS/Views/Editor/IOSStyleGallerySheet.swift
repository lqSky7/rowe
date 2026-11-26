import PhotosUI
import SwiftUI
import RoweCore

private enum IOSStyleSheetPage: Equatable {
    case hub
    case textColor
    case font
    case backdrop
    case paper
    case styles
    case separators
}

/// Craft-inspired floating Liquid Glass Style Hub matching the iOS reference screenshots:
/// - Hub grid: Text Color + Font, Cover + Backdrop + Paper (curled corner), Styles + Separators
/// - Backdrop subview: 4-mode icon bar, 12 color swatches + rainbow picker, Immersive / Faded effect
/// - Style Gallery subview: Search + 2-column visual style cards + bottom current-style bar
struct IOSStyleGallerySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: WorkspaceStore
    let document: RoweDocument
    @Binding var preferredHeight: CGFloat

    @State private var page: IOSStyleSheetPage = .hub
    @State private var styleSearch: String = ""
    @State private var backdropEffectFaded: Bool = false
    @State private var customColor: Color = .accentColor
    @State private var pickedCoverItem: PhotosPickerItem?
    @State private var showBackdropPhotoPicker: Bool = false

    private var reduceMotion: Bool { store.settings.reduceAnimations }

    private let paletteHexes: [String] = [
        "#F5CBA7", "#F4B400", "#4A90E2", "#1D4ED8", "#00BFA5", "#045D44",
        "#0277BD", "#FF6D00", "#D50000", "#F8BBD0", "#C5B4FF"
    ]

    private let paperHexes: [String] = [
        "#FFFFFF", "#FAF6EE", "#F5EFE6", "#EEF4F8", "#EFF5F0",
        "#1C1E26", "#151C28", "#201C1B", "#18181B", "#12142A"
    ]

    private func detentHeight(for target: IOSStyleSheetPage) -> CGFloat {
        switch target {
        case .hub: 396
        case .textColor: 224
        case .paper: 224
        case .font: 268
        case .separators: 368
        case .backdrop: 376
        case .styles: 540
        }
    }

    private func navigateTo(_ target: IOSStyleSheetPage) {
        withAnimation(IOSTheme.craftSpring(reduceMotion: reduceMotion)) {
            page = target
            preferredHeight = detentHeight(for: target)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch page {
                case .hub:
                    hubGridView
                        .transition(.roweUnblur)
                case .backdrop:
                    backdropEditorView
                        .transition(.roweUnblur)
                case .styles:
                    styleGalleryView
                        .transition(.roweUnblur)
                case .font:
                    fontPickerView
                        .transition(.roweUnblur)
                case .textColor:
                    textColorPickerView
                        .transition(.roweUnblur)
                case .paper:
                    paperPickerView
                        .transition(.roweUnblur)
                case .separators:
                    separatorsPickerView
                        .transition(.roweUnblur)
                }
            }
            .animation(IOSTheme.craftSpring(reduceMotion: reduceMotion), value: page)
        }
        .padding(.top, 14)
        .photosPicker(isPresented: $showBackdropPhotoPicker, selection: $pickedCoverItem, matching: .images)
        .onAppear { preferredHeight = detentHeight(for: page) }
        .onChange(of: pickedCoverItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self) {
                    store.updateDocumentStyle(docId: document.id) {
                        $0.customBackdropBase64 = data.base64EncodedString()
                        $0.backdropKind = .sketch
                    }
                }
            }
        }
    }

    // MARK: - 1. Main Style Hub (Matches 97B99754)

    private var hubGridView: some View {
        VStack(spacing: 12) {
            // Row 1: Text Color (1/3) + Font (2/3)
            HStack(spacing: 12) {
                Button {
                    IOSHaptics.shared.tap()
                    navigateTo(.textColor)
                } label: {
                    ZStack(alignment: .bottom) {
                        VStack {
                            Spacer()
                            Text("Text Color")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.primary.opacity(0.85))
                            Spacer()
                        }
                        // Pen nib silhouette at bottom center
                        Image(systemName: "pencil.tip")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(document.style.safeTextColorHex.map(Color.init(hex:)) ?? .primary)
                            .offset(y: 6)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 112)
                    .background(tileBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(RowePressScaleStyle())
                .frame(width: 116)

                Button {
                    IOSHaptics.shared.tap()
                    navigateTo(.font)
                } label: {
                    VStack(spacing: 4) {
                        Text(document.style.fontFamily.rawValue)
                            .font(IOSTheme.font(for: .title, family: document.style.fontFamily, isBold: true))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text("Font")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 112)
                    .background(tileBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(RowePressScaleStyle())
            }

            // Row 2: Cover + Backdrop + Paper
            HStack(spacing: 12) {
                PhotosPicker(selection: $pickedCoverItem, matching: .images) {
                    VStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.10))
                            .frame(height: 44)
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.secondary)
                            )
                            .padding(.horizontal, 12)
                        Text("Cover")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 112)
                    .background(tileBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(RowePressScaleStyle())

                Button {
                    IOSHaptics.shared.tap()
                    navigateTo(.backdrop)
                } label: {
                    VStack(spacing: 8) {
                        Text("Backdrop")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.top, 12)
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(backdropSwatchFill)
                            .frame(height: 62)
                            .padding(.horizontal, 12)
                    }
                    .frame(maxWidth: .infinity, maxHeight: 112, alignment: .top)
                    .background(tileBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(RowePressScaleStyle())

                Button {
                    IOSHaptics.shared.tap()
                    navigateTo(.paper)
                } label: {
                    ZStack(alignment: .topLeading) {
                        // Subtle ruled lines + curled corner
                        VStack(spacing: 9) {
                            ForEach(0..<6, id: \.self) { _ in
                                Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
                            }
                        }
                        .padding(.top, 30)

                        Text("Paper")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)
                            .padding(12)

                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Image(systemName: "doc.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(Color.primary.opacity(0.18))
                                    .padding(10)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 112)
                    .background(tileBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(RowePressScaleStyle())
            }

            // Row 3: Styles (2/3) + Separators (1/3)
            HStack(spacing: 12) {
                Button {
                    IOSHaptics.shared.tap()
                    navigateTo(.styles)
                } label: {
                    HStack(alignment: .top) {
                        Text("Styles")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary)
                            .padding(.top, 14)
                            .padding(.leading, 14)
                        Spacer()
                        // Stacked mini style cards
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(hex: "#F6C8B8"))
                                .frame(width: 68, height: 84)
                                .rotationEffect(.degrees(7))
                                .offset(x: 16, y: 12)
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(hex: "#D5ECFA"))
                                .frame(width: 68, height: 84)
                                .rotationEffect(.degrees(3))
                                .offset(x: 8, y: 10)
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemBackground))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
                                )
                                .overlay(alignment: .topLeading) {
                                    Text(ThemePreset.builtInPresets.first(where: { $0.id == document.style.themeId })?.name ?? "Original")
                                        .font(.system(size: 10.5, weight: .bold))
                                        .foregroundStyle(.primary)
                                        .padding(8)
                                }
                                .frame(width: 72, height: 86)
                                .offset(x: -4, y: 12)
                        }
                        .padding(.trailing, 18)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 112)
                    .background(tileBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(RowePressScaleStyle())

                Button {
                    IOSHaptics.shared.tap()
                    navigateTo(.separators)
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Separators")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)
                            .padding(.top, 14)
                            .padding(.horizontal, 12)
                        Spacer()
                        VStack(spacing: 8) {
                            Rectangle().stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                .foregroundStyle(Color.primary.opacity(0.35)).frame(height: 1)
                            Rectangle().fill(Color.primary.opacity(0.45)).frame(height: 2)
                            Rectangle().fill(Color.primary.opacity(0.65)).frame(height: 3.5)
                        }
                        .padding(.bottom, 14)
                    }
                    .frame(width: 116, height: 112)
                    .background(tileBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(RowePressScaleStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
    }

    // MARK: - 2. Backdrop Subview (Matches 9AE90BD2)

    private var backdropEditorView: some View {
        VStack(alignment: .leading, spacing: 16) {
            subviewHeader("Backdrop", showReset: true) {
                store.updateDocumentStyle(docId: document.id) {
                    $0.backdropKind = .none
                    $0.backdropColorsHex = []
                    $0.coverImageName = nil
                    $0.customBackdropBase64 = nil
                }
            }

            // Native iOS 26 Liquid Glass hold-and-slide segmented control: None | Solid | Gradient | Image
            Picker("Backdrop Mode", selection: Binding(
                get: { document.style.backdropKind },
                set: { newKind in
                    IOSHaptics.shared.toggle()
                    if newKind == .sketch {
                        showBackdropPhotoPicker = true
                    } else {
                        store.updateDocumentStyle(docId: document.id) {
                            $0.backdropKind = newKind
                            $0.coverImageName = nil
                            if newKind == .solid && $0.backdropColorsHex.isEmpty {
                                $0.backdropColorsHex = ["#F5CBA7"]
                            } else if newKind == .gradient && $0.backdropColorsHex.count < 2 {
                                $0.backdropColorsHex = ["#FAF6EE", "#E6D9C3"]
                            }
                        }
                    }
                }
            )) {
                Image(systemName: "circle.slash").tag(BackdropKind.none)
                Image(systemName: "square.inset.filled").tag(BackdropKind.solid)
                Image(systemName: "rectangle.fill.on.rectangle.fill").tag(BackdropKind.gradient)
                Image(systemName: "photo").tag(BackdropKind.sketch)
            }
            .pickerStyle(.segmented)
            .controlSize(.large)

            // 12 color swatches (2 rows x 6 cols, last is rainbow ColorPicker)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 12) {
                ForEach(paletteHexes, id: \.self) { hex in
                    let isSelected = document.style.backdropColorsHex.first?.uppercased() == hex.uppercased()
                    Button {
                        IOSHaptics.shared.tap()
                        store.updateDocumentStyle(docId: document.id) {
                            $0.backdropKind = backdropEffectFaded ? .gradient : .solid
                            $0.backdropColorsHex = backdropEffectFaded ? [hex, "#1A1C22"] : [hex]
                            $0.coverImageName = nil
                        }
                    } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 44, height: 44)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color(uiColor: .systemBackground), lineWidth: isSelected ? 3 : 0)
                                    .padding(3)
                            )
                    }
                    .buttonStyle(RowePressScaleStyle())
                }

                // Rainbow wheel custom picker
                ZStack {
                    Circle()
                        .strokeBorder(
                            AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center),
                            lineWidth: 3.5
                        )
                        .frame(width: 44, height: 44)
                    ColorPicker("", selection: $customColor, supportsOpacity: false)
                        .labelsHidden()
                        .scaleEffect(1.2)
                        .opacity(0.02)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .allowsHitTesting(false)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("EFFECT")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    effectPill("Immersive", active: !backdropEffectFaded) {
                        backdropEffectFaded = false
                        if let first = document.style.backdropColorsHex.first {
                            store.updateDocumentStyle(docId: document.id) {
                                $0.backdropKind = .solid
                                $0.backdropColorsHex = [first]
                            }
                        }
                    }
                    effectPill("Faded", active: backdropEffectFaded) {
                        backdropEffectFaded = true
                        if let first = document.style.backdropColorsHex.first {
                            store.updateDocumentStyle(docId: document.id) {
                                $0.backdropKind = .gradient
                                $0.backdropColorsHex = [first, "#1A1C22"]
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 22)
    }

    // MARK: - 3. Style Gallery Subview (Matches BD8D5493)

    private var styleGalleryView: some View {
        let presets = ThemePreset.builtInPresets.filter {
            styleSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(styleSearch)
        }
        return VStack(spacing: 12) {
            subviewHeader("Style Gallery", showReset: false) {}
                .padding(.horizontal, 18)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                TextField("Search", text: $styleSearch)
                    .font(.system(size: 15))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.08)))
            .padding(.horizontal, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("ROWE STYLES")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 18)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 16) {
                        ForEach(presets) { preset in
                            let selected = document.style.themeId == preset.id
                            Button {
                                IOSHaptics.shared.tap()
                                store.updateDocumentStyle(docId: document.id) { $0 = preset.style }
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    ZStack {
                                        if let cover = preset.style.coverImageName {
                                            IOSCoverArtwork(artworkName: cover)
                                        } else {
                                            Color(uiColor: .secondarySystemBackground)
                                        }

                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(preset.style.documentColorHex.map(Color.init(hex:)) ?? Color(uiColor: .systemBackground))
                                            .frame(width: 82, height: 108)
                                            .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                                            .overlay(alignment: .topLeading) {
                                                Text(preset.name)
                                                    .font(.system(size: 11, weight: .bold))
                                                    .foregroundStyle(preset.style.safeTextColorHex.map(Color.init(hex:)) ?? .primary)
                                                    .padding(8)
                                            }
                                    }
                                    .frame(height: 152)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 2.5 : 0.75)
                                    )

                                    Text(preset.name)
                                        .font(.system(size: 13.5, weight: selected ? .semibold : .regular))
                                        .foregroundStyle(selected ? Color.accentColor : .secondary)
                                }
                            }
                            .buttonStyle(RowePressScaleStyle())
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 20)
                }
            }
        }
    }

    // MARK: - 4. Font, Text Color, Paper, Separators Subviews

    private var fontPickerView: some View {
        VStack(alignment: .leading, spacing: 14) {
            subviewHeader("Font", showReset: false) {}
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(FontFamily.allCases, id: \.self) { fam in
                    let active = document.style.fontFamily == fam
                    Button {
                        IOSHaptics.shared.tap()
                        store.updateDocumentStyle(docId: document.id) { $0.fontFamily = fam }
                    } label: {
                        HStack {
                            Text(fam.badgeLabel)
                                .font(IOSTheme.font(for: .heading, family: fam, isBold: true))
                                .frame(width: 34)
                            Text(fam.rawValue)
                                .font(.system(size: 15, weight: active ? .semibold : .regular))
                            Spacer()
                            if active {
                                Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(active ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.06))
                        )
                    }
                    .buttonStyle(RowePressScaleStyle())
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 22)
    }

    private var textColorPickerView: some View {
        VStack(alignment: .leading, spacing: 14) {
            subviewHeader("Text Color", showReset: true) {
                store.updateDocumentStyle(docId: document.id) { $0.textColorHex = nil }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 14) {
                ForEach(BlockColor.allCases, id: \.self) { c in
                    Button {
                        IOSHaptics.shared.tap()
                        store.updateDocumentStyle(docId: document.id) {
                            $0.textColorHex = (c == .primary) ? nil : c.hex
                        }
                    } label: {
                        Circle()
                            .fill(Color(hex: c.hex))
                            .frame(width: 40, height: 40)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1))
                    }
                    .buttonStyle(RowePressScaleStyle())
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 22)
    }

    private var paperPickerView: some View {
        VStack(alignment: .leading, spacing: 14) {
            subviewHeader("Paper Color", showReset: true) {
                store.updateDocumentStyle(docId: document.id) {
                    $0.documentColorHex = nil
                    $0.textColorHex = nil
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 14) {
                ForEach(paperHexes, id: \.self) { hex in
                    let isSelected = document.style.documentColorHex?.uppercased() == hex.uppercased()
                    Button {
                        IOSHaptics.shared.tap()
                        let isLight = DocumentStyle.isHexLight(hex)
                        store.updateDocumentStyle(docId: document.id) {
                            $0.documentColorHex = hex
                            $0.textColorHex = isLight ? "#1F2225" : "#F2F3F5"
                        }
                    } label: {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(hex: hex))
                            .frame(height: 46)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.18), lineWidth: isSelected ? 2.5 : 1)
                            )
                    }
                    .buttonStyle(RowePressScaleStyle())
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 22)
    }

    private var separatorsPickerView: some View {
        VStack(alignment: .leading, spacing: 14) {
            subviewHeader("Separators", showReset: false) {}
            ForEach([SeparatorStyle.regular, .strong, .dotted, .doodle, .washi], id: \.self) { style in
                let active = document.style.separatorStyle == style
                Button {
                    IOSHaptics.shared.tap()
                    store.updateDocumentStyle(docId: document.id) { $0.separatorStyle = style }
                } label: {
                    HStack {
                        Text(style.rawValue)
                            .font(.system(size: 15, weight: active ? .semibold : .regular))
                        Spacer()
                        if active {
                            Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(active ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.06))
                    )
                }
                .buttonStyle(RowePressScaleStyle())
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 22)
    }

    // MARK: - Helpers

    private var tileBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.primary.opacity(0.075))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
            )
    }

    private var backdropSwatchFill: Color {
        if let hex = document.style.backdropColorsHex.first {
            return Color(hex: hex)
        }
        return Color.primary.opacity(0.18)
    }

    private func subviewHeader(_ title: String, showReset: Bool, onReset: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Button {
                IOSHaptics.shared.tap()
                navigateTo(.hub)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(RowePressScaleStyle())

            Text(title)
                .font(.system(size: 18, weight: .bold))

            Spacer()

            if showReset {
                Button {
                    IOSHaptics.shared.tap()
                    onReset()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(RowePressScaleStyle())
            }

            Button {
                IOSHaptics.shared.tap()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(RowePressScaleStyle())
        }
    }

    private func backdropModeButton(icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            IOSHaptics.shared.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(active ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(Capsule().fill(active ? Color.primary.opacity(0.16) : Color.clear))
        }
        .buttonStyle(RowePressScaleStyle())
    }

    private func effectPill(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            IOSHaptics.shared.tap()
            action()
        } label: {
            Text(title)
                .font(.system(size: 14.5, weight: active ? .semibold : .medium))
                .foregroundStyle(active ? Color.accentColor : .secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    Capsule()
                        .fill(active ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.07))
                )
        }
        .buttonStyle(RowePressScaleStyle())
    }
}
