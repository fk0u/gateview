import SwiftUI

/// Immersive macOS-style interactive Dock with hover magnification and DockDoor-inspired
/// live Window Preview popover supporting Focus, Minimize, Close, and Quit directly from the preview.
struct DockView: View {
    @ObservedObject var dock: DockWindowService
    @ObservedObject var windows: WindowManager
    let theme: Theme

    @State private var hoveredPID: pid_t?
    @State private var hoveredIndex: Int?
    @State private var isOverPreview = false
    @State private var dismissTask: Task<Void, Never>?

    private var previewApp: DockAppItem? {
        guard let pid = hoveredPID else { return nil }
        return dock.apps.first { $0.pid == pid }
    }

    var body: some View {
        VStack(spacing: 10) {
            if let app = previewApp {
                previewPopover(for: app)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
                    .onHover { over in
                        isOverPreview = over
                        if over { dismissTask?.cancel() } else { scheduleDismiss() }
                    }
                    .background(GeometryReader { geo in
                        Color.clear.preference(key: HitRegionsKey.self, value: ["dockPreview": geo.frame(in: .global)])
                    })
            }

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(dock.apps.prefix(14).enumerated()), id: \.element.id) { index, app in
                    dockAppButton(app, index: index)
                }

                if !dock.apps.isEmpty {
                    Divider()
                        .frame(height: 28)
                        .overlay(.white.opacity(0.2))
                        .padding(.horizontal, 2)
                }

                quickActionButton(symbol: "chevron.up.square", active: windows.expanded == "notch", help: "Toggle Notch") {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        windows.expanded = windows.expanded == "notch" ? nil : "notch"
                    }
                }
                quickActionButton(symbol: "note.text", active: windows.expanded == "notes", help: "Notes") {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        windows.expanded = windows.expanded == "notes" ? nil : "notes"
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .background(Color.black.opacity(0.62))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.45), radius: 26, y: 12)
            .background(GeometryReader { geo in
                Color.clear.preference(key: HitRegionsKey.self, value: ["dock": geo.frame(in: .global)])
            })
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: hoveredPID)
    }

    private func dockAppButton(_ app: DockAppItem, index: Int) -> some View {
        let scale = magnificationScale(for: index)
        let lift = (scale - 1) * 20
        return Button {
            dock.focus(app: app, window: app.windows.first)
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(nsImage: dock.icon(for: app.pid))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 42, height: 42)
                        .opacity(app.isHidden ? 0.55 : 1)
                        .shadow(color: app.isActive ? .white.opacity(0.25) : .black.opacity(0.35), radius: app.isActive ? 8 : 4, y: 3)

                    if app.windows.count > 1 {
                        Text("\(app.windows.count)")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.black.opacity(0.75), in: Capsule())
                            .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
                    }
                }
                Capsule()
                    .fill(app.isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.white.opacity(0.55)))
                    .frame(width: app.isActive ? 14 : 4, height: 4)
            }
            .scaleEffect(scale, anchor: .bottom)
            .offset(y: -lift)
            .animation(.spring(response: 0.22, dampingFraction: 0.78), value: hoveredIndex)
        }
        .buttonStyle(.plain)
        .onHover { over in
            if over {
                dismissTask?.cancel()
                hoveredIndex = index
                hoveredPID = app.pid
                dock.refresh()
                for win in app.windows.prefix(4) {
                    dock.loadPreview(for: win)
                }
            } else {
                if hoveredIndex == index { hoveredIndex = nil }
                scheduleDismiss()
            }
        }
    }

    private func quickActionButton(symbol: String, active: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(active ? 0.2 : 0.09))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(active ? AnyShapeStyle(.tint) : AnyShapeStyle(.white.opacity(0.16)), lineWidth: 1)
                    )
                    .overlay(Image(systemName: symbol).font(.system(size: 16, weight: .medium)))
                    .frame(width: 40, height: 40)
                Capsule()
                    .fill(active ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear))
                    .frame(width: active ? 10 : 4, height: 4)
            }
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func previewPopover(for app: DockAppItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(nsImage: dock.icon(for: app.pid))
                    .resizable()
                    .frame(width: 18, height: 18)
                Text(app.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Button {
                    dock.quit(app: app)
                    hoveredPID = nil
                } label: {
                    Label("Quit", systemImage: "power")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.red.opacity(0.28), in: Capsule())
                        .overlay(Capsule().strokeBorder(.red.opacity(0.45), lineWidth: 0.75))
                }
                .buttonStyle(.plain)
                .help("Quit \(app.name)")
            }

            if app.windows.isEmpty {
                HStack(spacing: 10) {
                    Image(nsImage: dock.icon(for: app.pid))
                        .resizable()
                        .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.isHidden ? "Hidden" : "No visible window")
                            .font(.system(size: 12, weight: .medium))
                        Text("Click to bring \(app.name) to front")
                            .font(.system(size: 10.5))
                            .opacity(0.65)
                    }
                    Spacer()
                }
                .padding(10)
                .frame(width: 250)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onTapGesture {
                    dock.focus(app: app)
                    hoveredPID = nil
                }
            } else {
                HStack(spacing: 10) {
                    ForEach(app.windows.prefix(3)) { win in
                        windowPreviewCard(app: app, win: win)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.84))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.55), radius: 28, y: 10)
    }

    private func windowPreviewCard(app: DockAppItem, win: DockAppWindow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(win.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button {
                    dock.minimize(app: app, window: win)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 18, height: 18)
                        .background(.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Minimize window")

                Button {
                    dock.close(app: app, window: win)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 18, height: 18)
                        .background(.red.opacity(0.45), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Close window")
            }

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.06))
                if let thumb = dock.previews[win.id] {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 210, height: 124)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    VStack(spacing: 6) {
                        Image(nsImage: dock.icon(for: app.pid))
                            .resizable()
                            .frame(width: 36, height: 36)
                        Text("\(Int(win.bounds.width))×\(Int(win.bounds.height))")
                            .font(.system(size: 10))
                            .opacity(0.55)
                            .monospacedDigit()
                    }
                }
            }
            .frame(width: 210, height: 124)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.75))
            .contentShape(Rectangle())
            .onTapGesture {
                dock.focus(app: app, window: win)
                hoveredPID = nil
            }
        }
        .padding(8)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func magnificationScale(for index: Int) -> CGFloat {
        guard let hovered = hoveredIndex else { return 1.0 }
        let dist = abs(hovered - index)
        switch dist {
        case 0: return 1.38
        case 1: return 1.18
        case 2: return 1.06
        default: return 1.0
        }
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled, !isOverPreview, hoveredIndex == nil else { return }
            hoveredPID = nil
        }
    }
}
