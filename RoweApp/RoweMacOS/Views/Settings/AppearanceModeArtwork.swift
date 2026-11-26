import SwiftUI
import RoweCore

struct AppearanceModeArtwork: View {
    let mode: AppearanceMode

    var body: some View {
        switch mode {
        case .light:
            miniWorkspaceArt(isDark: false)
        case .dark:
            miniWorkspaceArt(isDark: true)
        case .system:
            GeometryReader { geo in
                ZStack {
                    miniWorkspaceArt(isDark: false)
                    miniWorkspaceArt(isDark: true)
                        .mask(
                            HStack(spacing: 0) {
                                Color.clear.frame(width: geo.size.width / 2)
                                Color.black
                            }
                        )
                }
            }
        }
    }

    private func miniWorkspaceArt(isDark: Bool) -> some View {
        ZStack {
            LinearGradient(
                colors: isDark
                    ? [Color(hex: "#58657A"), Color(hex: "#2B3240")]
                    : [Color(hex: "#E8CDA8"), Color(hex: "#D5B18B")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 2.5) {
                        Circle().fill(Color.primary.opacity(0.25)).frame(width: 3.5, height: 3.5)
                        Circle().fill(Color.primary.opacity(0.25)).frame(width: 3.5, height: 3.5)
                        Circle().fill(Color.primary.opacity(0.25)).frame(width: 3.5, height: 3.5)
                    }
                    Spacer().frame(height: 4)
                    RoundedRectangle(cornerRadius: 1.5).fill(isDark ? Color.white.opacity(0.25) : Color.black.opacity(0.18)).frame(width: 18, height: 3)
                    RoundedRectangle(cornerRadius: 1.5).fill(isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.10)).frame(width: 22, height: 2.5)
                    RoundedRectangle(cornerRadius: 1.5).fill(isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.10)).frame(width: 16, height: 2.5)
                    Spacer()
                }
                .padding(6)
                .frame(width: 34)
                .background(isDark ? Color(hex: "#23262D") : Color(hex: "#F2EFE9"))

                VStack(alignment: .leading, spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(isDark ? Color.white.opacity(0.75) : Color.black.opacity(0.7)).frame(width: 34, height: 4)
                    RoundedRectangle(cornerRadius: 1.5).fill(isDark ? Color.white.opacity(0.25) : Color.black.opacity(0.22)).frame(width: 54, height: 2.5)
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 1.5).fill(Color.accentColor).frame(width: 5, height: 5)
                        RoundedRectangle(cornerRadius: 1.5).fill(isDark ? Color.white.opacity(0.35) : Color.black.opacity(0.28)).frame(width: 38, height: 2.5)
                    }
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 1.5).stroke(isDark ? Color.white.opacity(0.35) : Color.black.opacity(0.3), lineWidth: 0.7).frame(width: 5, height: 5)
                        RoundedRectangle(cornerRadius: 1.5).fill(isDark ? Color.white.opacity(0.28) : Color.black.opacity(0.22)).frame(width: 46, height: 2.5)
                    }
                    Spacer()
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isDark ? Color(hex: "#191B1F") : Color.white)

                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(isDark ? Color.white.opacity(0.18) : Color.black.opacity(0.12)).frame(height: 10)
                    RoundedRectangle(cornerRadius: 1.5).fill(isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)).frame(height: 18)
                    Spacer()
                }
                .padding(5)
                .frame(width: 24)
                .background(isDark ? Color(hex: "#22252C") : Color(hex: "#ECE9E2"))
            }
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 0)
        }
    }
}
