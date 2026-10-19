import SwiftUI

/// First-launch window: a three-line guide plus a menu bar diagram drawn with SwiftUI shapes.
struct WelcomeView: View {
    let onOpenSettings: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Welcome to MenuBarCollapse")
                .font(.title2.bold())

            MenuBarDiagram()

            VStack(alignment: .leading, spacing: 8) {
                Label("Hold ⌘ and drag menu bar icons to the left of the divider.", systemImage: "1.circle.fill")
                Label("Click the chevron to hide or show them — Option-click for the menu.", systemImage: "2.circle.fill")
                Label("Shown icons re-hide automatically after the auto-hide delay.", systemImage: "3.circle.fill")
            }
            .font(.callout)

            HStack {
                Button("Open Settings…", action: onOpenSettings)
                Spacer()
                Button("Got It", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

/// An image-free sketch of the menu bar: hideable icons, the divider, the chevron and always-visible icons.
private struct MenuBarDiagram: View {
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { _ in
                    Circle().fill(Color.accentColor.opacity(0.55)).frame(width: 12, height: 12)
                }
                Capsule().fill(Color.primary).frame(width: 2, height: 16)
                ChevronShape()
                    .stroke(Color.primary, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .frame(width: 7, height: 12)
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.6)).frame(width: 12, height: 12)
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .trailing)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.15)))

            HStack {
                Spacer()
                Text("hideable").foregroundStyle(Color.accentColor)
                Text("|  divider   ‹  chevron").foregroundStyle(.secondary)
                Text("always visible").foregroundStyle(.secondary)
            }
            .font(.caption2)
            .padding(.horizontal, 4)
        }
    }
}

/// A left-pointing chevron stroke used in the diagram.
private struct ChevronShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}
