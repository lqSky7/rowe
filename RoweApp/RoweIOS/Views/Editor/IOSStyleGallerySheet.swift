import SwiftUI
import RoweCore

struct IOSStyleGallerySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: WorkspaceStore
    let document: RoweDocument

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Rowe Styles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 18)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 16) {
                        ForEach(ThemePreset.builtInPresets) { preset in
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
                                            Color.primary.opacity(0.08)
                                        }

                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(preset.style.documentColorHex.map(Color.init(hex:)) ?? .white)
                                            .frame(width: 78, height: 100)
                                            .shadow(color: .black.opacity(0.16), radius: 5, y: 3)
                                            .overlay(alignment: .topLeading) {
                                                Text(preset.name)
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundStyle(preset.style.textColorHex.map(Color.init(hex:)) ?? Color(hex: "#1F2225"))
                                                    .padding(7)
                                            }
                                    }
                                    .frame(height: 140)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 2.5 : 0.75)
                                    )

                                    Text(preset.name)
                                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                                        .foregroundStyle(.primary)
                                }
                            }
                            .buttonStyle(RowePressScaleStyle())
                        }
                    }
                    .padding(.horizontal, 18)

                    Divider().padding(.horizontal, 18)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Font")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                            ForEach(FontFamily.allCases, id: \.self) { fam in
                                let active = document.style.fontFamily == fam
                                Button {
                                    IOSHaptics.shared.tap()
                                    store.updateDocumentStyle(docId: document.id) { $0.fontFamily = fam }
                                } label: {
                                    VStack(spacing: 2) {
                                        Text(fam.badgeLabel).font(.system(size: 15, weight: .semibold))
                                        Text(fam.rawValue).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(active ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 18)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Separator Style")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            sepChip("Line", style: .regular)
                            sepChip("Doodle", style: .doodle)
                            sepChip("Washi", style: .washi)
                        }
                    }
                    .padding(.horizontal, 18)
                }
                .padding(.vertical, 16)
            }
            .navigationTitle("Document Style")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func sepChip(_ label: String, style: SeparatorStyle) -> some View {
        let active = document.style.separatorStyle == style
        return Button {
            IOSHaptics.shared.tap()
            store.updateDocumentStyle(docId: document.id) { $0.separatorStyle = style }
        } label: {
            Text(label)
                .font(.system(size: 13.5, weight: active ? .semibold : .regular))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(active ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.07))
                )
        }
        .buttonStyle(.plain)
    }
}
