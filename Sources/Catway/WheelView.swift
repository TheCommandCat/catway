import AppKit
import SwiftUI

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published var spaces: [WorkspaceModel]
    @Published var gestureOrigin: CGPoint = .zero
    @Published var visualCenter: CGPoint = .zero

    init(spaces: [WorkspaceModel]) {
        self.spaces = spaces
    }
}

struct AppGlyph: View {
    let appName: String
    let size: CGFloat

    private var icon: NSImage? {
        NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == appName })?.icon
    }

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.22)
                        .fill(.white.opacity(0.14))
                    Text(String(appName.prefix(1)).uppercased())
                        .font(.system(size: size * 0.45, weight: .bold))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct WorkspaceWheelNode: View {
    let workspace: WorkspaceModel
    let size: CGFloat
    let isSelected: Bool
    let isCurrent: Bool
    let select: () -> Void

    private var iconSize: CGFloat { size > 95 ? 27 : 22 }

    var body: some View {
        Button(action: select) {
            VStack(spacing: size > 95 ? 7 : 4) {
                Text(workspace.displayLabel)
                    .font(.system(size: size > 95 ? 29 : 23, weight: .heavy, design: .rounded))

                HStack(spacing: 4) {
                    ForEach(Array(workspace.apps.prefix(size > 95 ? 3 : 2)), id: \.self) { app in
                        AppGlyph(appName: app, size: iconSize)
                    }
                }

                if size > 90 {
                    Text(workspace.apps.first ?? "Workspace")
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(.white.opacity(0.64))
                }
            }
            .frame(width: size, height: size)
            .background(Circle().fill(isSelected ? Color.white.opacity(0.22) : Color.black.opacity(0.52)))
            .overlay(
                Circle().stroke(
                    isSelected ? Color.white : (isCurrent ? Color.cyan.opacity(0.95) : Color.white.opacity(0.18)),
                    lineWidth: isSelected ? 3.5 : (isCurrent ? 2.5 : 1)
                )
            )
            .shadow(color: isSelected ? .cyan.opacity(0.5) : .black.opacity(0.28), radius: isSelected ? 16 : 8)
            .scaleEffect(isSelected ? 1.08 : 1)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: isSelected)
        .accessibilityLabel("Workspace \(workspace.displayLabel), \(workspace.windowCount) windows")
    }
}

struct WorkspaceWheelView: View {
    @ObservedObject var store: WorkspaceStore
    let select: (WorkspaceModel) -> Void
    let dismiss: () -> Void

    @State private var selectedID: Int?

    private func updateDirectionalSelection(at location: CGPoint) {
        let index = RadialLayout.nearestIndex(
            pointer: location,
            gestureOrigin: store.gestureOrigin,
            visualCenter: store.visualCenter,
            count: store.spaces.count
        )
        let nextID = index.map { store.spaces[$0].id }
        guard nextID != selectedID else { return }
        withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
            selectedID = nextID
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let count = store.spaces.count
            let radius = min(CGFloat(188), min(geometry.size.width, geometry.size.height) * 0.21)
            let nodeSize = RadialLayout.nodeSize(for: count)
            let selectedWorkspace = store.spaces.first(where: { $0.id == selectedID })
            let headerY = max(CGFloat(78), geometry.safeAreaInsets.top + 34)

            ZStack {
                Rectangle()
                    .fill(Color.black.opacity(0.035))
                    .ignoresSafeArea()

                Circle()
                    .stroke(Color.white.opacity(0.11), style: StrokeStyle(lineWidth: 2, dash: [4, 9]))
                    .frame(width: radius * 2, height: radius * 2)
                    .position(store.visualCenter)

                if let selectedWorkspace,
                   let selectedOffset = store.spaces.firstIndex(where: { $0.id == selectedWorkspace.id }) {
                    let selectedAngle = RadialLayout.angle(for: selectedOffset, count: count)
                    Path { path in
                        path.move(to: store.visualCenter)
                        path.addLine(to: CGPoint(
                            x: store.visualCenter.x + cos(selectedAngle) * (radius - nodeSize * 0.48),
                            y: store.visualCenter.y + sin(selectedAngle) * (radius - nodeSize * 0.48)
                        ))
                    }
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.05), .cyan.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                }

                ForEach(Array(store.spaces.enumerated()), id: \.element.id) { offset, workspace in
                    let nodeAngle = RadialLayout.angle(for: offset, count: count)
                    let selected = selectedID == workspace.id
                    let outward = selected ? CGFloat(8) : 0

                    WorkspaceWheelNode(
                        workspace: workspace,
                        size: nodeSize,
                        isSelected: selected,
                        isCurrent: workspace.isFocused,
                        select: { select(workspace) }
                    )
                    .position(
                        x: store.visualCenter.x + cos(nodeAngle) * (radius + outward),
                        y: store.visualCenter.y + sin(nodeAngle) * (radius + outward)
                    )
                }

                Button(action: dismiss) {
                    VStack(spacing: 7) {
                        Text("STAY")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                        Text("Click to stay")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    .frame(width: 84, height: 84)
                    .background(Circle().fill(Color.black.opacity(0.56)))
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.35), radius: 18)
                }
                .buttonStyle(.plain)
                .position(store.visualCenter)

                VStack(spacing: 5) {
                    Text("CATWAY")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .tracking(1.8)
                    Text("\(count) active workspaces · point · click · Esc closes")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .position(x: geometry.size.width / 2, y: headerY)
            }
            .foregroundStyle(.white)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                if case let .active(location) = phase {
                    updateDirectionalSelection(at: location)
                }
            }
            .onTapGesture {
                if let workspace = store.spaces.first(where: { $0.id == selectedID }) {
                    select(workspace)
                } else {
                    dismiss()
                }
            }
            .onExitCommand(perform: dismiss)
            .onChange(of: store.gestureOrigin) { _ in
                selectedID = nil
            }
        }
    }
}
