import SwiftUI

/// Represents a tab item in the sidebar with its associated surface information.
struct SidebarTabItem: Identifiable {
    let id: UUID
    let surfaceID: UUID
    let title: String
    let tabIndex: Int
    let needsAttention: Bool  // True when terminal has been idle (waiting for input)

    init(surface: Ghostty.SurfaceView, index: Int, needsAttention: Bool = false) {
        self.id = surface.id
        self.surfaceID = surface.id
        self.title = surface.title
        self.tabIndex = index
        self.needsAttention = needsAttention
    }
}

/// The main tab sidebar view that displays tabs in a vertical column with live previews.
struct TabSidebarView: View {
    @EnvironmentObject var ghostty: Ghostty.App
    @ObservedObject var previewManager: TabPreviewManager

    /// All tab items to display in the sidebar
    let tabItems: [SidebarTabItem]

    /// Currently selected surface ID
    @Binding var selectedSurfaceID: UUID?

    /// Sidebar width
    let sidebarWidth: CGFloat

    /// Sidebar height (for calculating optimal column count)
    let sidebarHeight: CGFloat

    /// Callbacks for tab actions
    let onNewTab: () -> Void
    let onCloseTab: (UUID) -> Void
    let onSelectTab: (UUID) -> Void

    /// Fixed column count based on number of tabs
    private var columnCount: Int {
        let count = tabItems.count
        if count <= 4 {
            return 2
        } else if count <= 9 {
            return 3
        } else {
            return 4
        }
    }

    /// Calculate the optimal item height to fill available space without scrolling
    private var itemSize: CGSize {
        let cols = columnCount
        let rows = Int(ceil(Double(tabItems.count) / Double(cols)))

        let horizontalPadding: CGFloat = 8  // 4 on each side
        let verticalPadding: CGFloat = 8    // 4 on top and bottom
        let spacing: CGFloat = 6
        let titleHeight: CGFloat = 20       // Title + spacing
        let itemPadding: CGFloat = 8        // 4 on each side

        // Calculate available width per item
        let totalHSpacing = spacing * CGFloat(cols - 1)
        let availableWidth = sidebarWidth - horizontalPadding - totalHSpacing
        let itemWidth = availableWidth / CGFloat(cols)

        // Calculate available height per item
        let totalVSpacing = spacing * CGFloat(rows - 1)
        let availableHeight = sidebarHeight - verticalPadding - totalVSpacing
        let itemHeight = availableHeight / CGFloat(rows)

        // Preview height is item height minus title and padding
        let previewHeight = itemHeight - titleHeight - itemPadding
        let previewWidth = itemWidth - itemPadding

        return CGSize(width: previewWidth, height: previewHeight)
    }

    private var columns: [GridItem] {
        return Array(repeating: GridItem(.flexible(), spacing: 6), count: columnCount)
    }

    var body: some View {
        // Tab grid fills entire sidebar
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(tabItems) { item in
                TabSidebarItemView(
                    item: item,
                    preview: previewManager.previews[item.surfaceID],
                    previewSize: itemSize,
                    isSelected: item.surfaceID == selectedSurfaceID,
                    needsAttention: item.needsAttention,
                    onSelect: {
                        previewManager.clearNeedsAttention(for: item.surfaceID)
                        onSelectTab(item.surfaceID)
                    },
                    onClose: { onCloseTab(item.surfaceID) },
                    onNewTab: onNewTab
                )
            }
        }
        .padding(4)
        .frame(width: sidebarWidth, height: sidebarHeight)
        .background(
            ghostty.config.backgroundColor
                // Make sidebar 50% less transparent than terminal
                // If terminal opacity is 0.8, sidebar will be 0.9
                .opacity(ghostty.config.backgroundOpacity + (1 - ghostty.config.backgroundOpacity) * 0.5)
        )
    }
}

/// Individual tab item view with preview thumbnail, title, and hover actions.
struct TabSidebarItemView: View {
    let item: SidebarTabItem
    let preview: NSImage?
    let previewSize: CGSize
    let isSelected: Bool
    let needsAttention: Bool  // True when terminal is idle and waiting for input
    let onSelect: () -> Void
    let onClose: () -> Void
    let onNewTab: () -> Void

    @State private var isHovering = false
    @State private var isPulsing = false

    /// Whether to show the attention indicator (needs attention + not selected)
    private var showAttention: Bool {
        needsAttention && !isSelected
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Preview thumbnail with attention overlay
            ZStack {
                // Base preview image
                previewImage
                    .frame(width: previewSize.width, height: previewSize.height)
                    .clipped()
                    .cornerRadius(6)

                // Attention overlay - dark tint with bell icon
                if showAttention {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(isPulsing ? 0.5 : 0.3))
                        .frame(width: previewSize.width, height: previewSize.height)
                        .overlay(
                            Image(systemName: "bell.fill")
                                .font(.system(size: min(previewSize.width, previewSize.height) * 0.3))
                                .foregroundColor(.orange)
                                .shadow(color: .orange.opacity(0.8), radius: isPulsing ? 12 : 6)
                                .scaleEffect(isPulsing ? 1.1 : 0.9)
                        )
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isPulsing)
                }

                // Top-right badges and buttons
                VStack {
                    HStack {
                        // Attention badge (top left) - red notification dot
                        if showAttention {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 12, height: 12)
                                .shadow(color: .red.opacity(0.8), radius: isPulsing ? 6 : 2)
                                .scaleEffect(isPulsing ? 1.2 : 1.0)
                                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isPulsing)
                                .padding(4)
                        }

                        Spacer()

                        // Tab number badge (top right) - only show for tabs 1-9
                        if item.tabIndex < 9 && !isHovering {
                            Text("\(item.tabIndex + 1)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color.black.opacity(0.6))
                                )
                                .padding(4)
                        }

                        // Close button shown on hover
                        if isHovering {
                            Button(action: onClose) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.white)
                                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                            }
                            .buttonStyle(.plain)
                            .padding(4)
                        }
                    }
                    Spacer()
                }
            }

            // Tab title - orange when needs attention
            Text(displayTitle)
                .font(.caption)
                .fontWeight(showAttention ? .semibold : .regular)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundColor(showAttention ? .orange : (isSelected ? .primary : .secondary))
        }
        .padding(4)
        .background(attentionBackground)
        .overlay(selectionBorder)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu {
            Button("Close Tab", action: onClose)
            Divider()
            Button("New Tab", action: onNewTab)
        }
        .onAppear {
            updatePulsingState()
        }
        .onChange(of: showAttention) { _ in
            updatePulsingState()
        }
    }

    private func updatePulsingState() {
        if showAttention {
            withAnimation(Animation.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        } else {
            withAnimation(.none) {
                isPulsing = false
            }
        }
    }

    // MARK: - Private Views

    @ViewBuilder
    private var previewImage: some View {
        if let preview = preview {
            Image(nsImage: preview)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .overlay(
                    ProgressView()
                        .scaleEffect(0.6)
                )
        }
    }

    private var displayTitle: String {
        item.title.isEmpty ? "Terminal" : item.title
    }

    private var attentionBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(
                isSelected
                    ? Color.accentColor.opacity(0.2)
                    : (showAttention
                        ? Color.orange.opacity(isPulsing ? 0.15 : 0.05)
                        : Color.clear)
            )
            .animation(showAttention ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true) : .default, value: isPulsing)
    }

    private var selectionBorder: some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(
                isSelected
                    ? Color.accentColor
                    : (showAttention
                        ? Color.orange.opacity(isPulsing ? 1.0 : 0.6)
                        : Color.gray.opacity(0.2)),
                lineWidth: isSelected ? 2.5 : (showAttention ? 2.5 : 1.0)
            )
            .shadow(color: showAttention ? Color.orange.opacity(isPulsing ? 0.6 : 0.2) : Color.clear, radius: isPulsing ? 8 : 4)
            .animation(showAttention ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true) : .default, value: isPulsing)
    }
}

// MARK: - Preview Provider

#if DEBUG
struct TabSidebarView_Previews: PreviewProvider {
    static var previews: some View {
        // Preview requires mock data - this is just for development
        EmptyView()
    }
}
#endif
