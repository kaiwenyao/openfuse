import SwiftUI

enum SidebarDestination: String, CaseIterable, Identifiable {
    case home
    case library
    case files

    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return "首页"
        case .library: return "媒体库"
        case .files: return "文件"
        }
    }
    var icon: String {
        switch self {
        case .home: return "house"
        case .library: return "rectangle.stack"
        case .files: return "folder"
        }
    }
}

/// Browsing shell: a collapsible macOS sidebar shared by Home, Library, Files
/// and every source browser. The player deliberately bypasses this shell.
struct MainShellView<Content: View>: View {
    @EnvironmentObject private var model: AppModel
    @State private var collapsed = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 0) {
            if !collapsed {
                sidebar
                    .frame(width: 220)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                Divider().overlay(Theme.stroke)
            }
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topLeading) {
                    if collapsed {
                        Button { withAnimation(.easeInOut(duration: 0.18)) { collapsed = false } } label: {
                            Image(systemName: "sidebar.left")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 32, height: 32)
                                .background(Theme.panel, in: Circle())
                                .overlay(Circle().stroke(Theme.stroke, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .padding(12)
                        .help("展开侧边栏")
                    }
                }
        }
        .background(Theme.background.ignoresSafeArea())
        .sheet(isPresented: $model.showAddSource) {
            AddSourceSheet().environmentObject(model)
        }
        .sheet(isPresented: $model.showSettings) {
            SettingsView().environmentObject(model)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(LinearGradient(colors: [Theme.accent, Color(red: 0.45, green: 0.42, blue: 0.95)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.background)
                }
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text("OpenFuse").font(.system(size: 16, weight: .semibold))
                    Text("Mac").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Button { withAnimation(.easeInOut(duration: 0.18)) { collapsed = true } } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                }
                .buttonStyle(.plain)
                .help("收起侧边栏")
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 14)

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                TextField("搜索媒体库", text: $model.librarySearch)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit {
                        model.sidebarDestination = .library
                        model.route = .home
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.bottom, 14)
            Text("搜索范围：已扫描的媒体库")
                .font(.system(size: 9.5))
                .foregroundStyle(Theme.secondary.opacity(0.75))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            ForEach(SidebarDestination.allCases) { destination in
                Button {
                    model.sidebarDestination = destination
                    model.route = .home
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: destination.icon)
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 18)
                        Text(destination.title).font(.system(size: 13, weight: .medium))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        model.sidebarDestination == destination && model.route == .home
                            ? Theme.accent.opacity(0.15) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .foregroundStyle(model.sidebarDestination == destination ? Theme.accent : Theme.text)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
            }

            Spacer()

            Button { model.showAddSource = true } label: {
                Label("添加来源", systemImage: "plus.circle")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.secondary)
            .padding(.horizontal, 10)
            .padding(.bottom, 4)

            Button { model.showSettings = true } label: {
                Label("设置", systemImage: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.secondary)
            .padding(.horizontal, 10)
            .padding(.bottom, 16)
        }
        .background(Theme.panel.opacity(0.6))
    }
}
