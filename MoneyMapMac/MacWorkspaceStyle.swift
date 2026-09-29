import SwiftUI

/// Three distinct surfaces: a quiet canvas, raised content, and softly tinted emphasis.
private struct MacWorkspaceSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    var tint: Color?
    var radius: CGFloat

    func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: radius)
                .fill(scheme == .dark ? Color(white: 0.17) : .white)
                .overlay {
                    if let tint {
                        RoundedRectangle(cornerRadius: radius)
                            .fill(tint.opacity(contrast == .increased ? 0.22 : scheme == .dark ? 0.16 : 0.08))
                    }
                }
                .shadow(color: .black.opacity(scheme == .dark ? 0.18 : 0.045), radius: 10, y: 3)
        }
    }
}

private struct MacWorkspaceCanvas: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content.background(scheme == .dark ? Color(red: 0.095, green: 0.105, blue: 0.12) : Color(red: 0.94, green: 0.95, blue: 0.97))
    }
}

extension View {
    func macWorkspaceSurface(tint: Color? = nil, radius: CGFloat = 16) -> some View {
        modifier(MacWorkspaceSurface(tint: tint, radius: radius))
    }
    func macWorkspaceCanvas() -> some View { modifier(MacWorkspaceCanvas()) }
}

struct MacWorkspaceGroupStyle: GroupBoxStyle {
    var tint: Color? = nil
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            configuration.label.font(.headline)
            configuration.content.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(14).macWorkspaceSurface(tint: tint)
    }
}
