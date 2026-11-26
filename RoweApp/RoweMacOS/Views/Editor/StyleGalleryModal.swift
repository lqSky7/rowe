import SwiftUI
import RoweCore

struct StyleGalleryModal: View {
    let selectedThemeId: String
    var onSelect: (ThemePreset) -> Void
    var onClose: () -> Void

    @State private var query: String = ""

    private var filteredPresets: [ThemePreset] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return ThemePreset.builtInPresets }
        return ThemePreset.builtInPresets.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Style Gallery")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button {
                    HapticsManager.shared.tap()
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider().opacity(0.3)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))

            Text("ROWE'S STYLES")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 18) {
                    ForEach(filteredPresets) { preset in
                        let isSelected = preset.id == selectedThemeId
                        Button {
                            HapticsManager.shared.tap()
                            onSelect(preset)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                ZStack {
                                    presetBackdrop(preset)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .strokeBorder(isSelected ? Color.primary : Color.clear, lineWidth: 2)
                                        )

                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(preset.style.documentColorHex.map(Color.init(hex:)) ?? Color.white)
                                        .frame(width: 82, height: 112)
                                        .shadow(color: .black.opacity(0.14), radius: 6, y: 3)
                                        .overlay(alignment: .topLeading) {
                                            Text(preset.name)
                                                .font(.system(size: 10.5, weight: .bold, design: preset.style.fontFamily == .serif ? .serif : .default))
                                                .foregroundStyle(preset.style.textColorHex.map(Color.init(hex:)) ?? Color(hex: "#1F2225"))
                                                .padding(8)
                                        }
                                }
                                .frame(height: 168)

                                Text(preset.name)
                                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                                    .foregroundStyle(.primary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .padding(20)
        .frame(width: 560, height: 600)
        .roweGlassRoundedRect(radius: 20)
    }

    @ViewBuilder
    private func presetBackdrop(_ preset: ThemePreset) -> some View {
        if let cover = preset.style.coverImageName {
            CraftCoverArtwork(artworkName: cover)
        } else if preset.style.backdropColorsHex.count >= 2 {
            LinearGradient(
                colors: preset.style.backdropColorsHex.map(Color.init(hex:)),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            Color.primary.opacity(0.08)
        }
    }
}
