import AppKit
import SwiftUI

/// 위젯 갤러리를 쓸 수 없을 때를 위한 바탕화면 패널.
/// 위젯의 systemMedium 레이아웃을 그대로 옮겼고, 데이터 소스도 동일하다.
private let panelOrange = Color(red: 0.851, green: 0.467, blue: 0.341)

/// 사용률이 높을수록 경고색으로. 위젯의 limitTint 와 같은 기준.
private let panelCodex = Color(red: 0.063, green: 0.639, blue: 0.498)

private func panelBrand(_ id: String) -> Color { id == "codex" ? panelCodex : panelOrange }

private func panelTint(_ used: Int, brand: Color) -> Color {
    if used >= 90 { return Color(red: 0.90, green: 0.28, blue: 0.24) }
    if used >= 75 { return Color(red: 0.95, green: 0.62, blue: 0.16) }
    return brand
}

struct PanelView: View {
    let usage: Usage?
    let onRefresh: () -> Void
    @State private var now = Date()
    private let tick = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header

            if let u = usage, let ps = u.providers, !ps.isEmpty {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(ps.prefix(2)) { providerColumn($0) }
                }
            } else if let b = usage?.block, b.active {
                blockFallback(b)
            } else if usage != nil {
                Text("현재 활동 없음")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            if let u = usage {
                Divider()
                HStack(spacing: 8) {
                    ForEach([("오늘", u.today), ("7일", u.week), ("30일", u.month)], id: \.0) { label, b in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(label)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.tertiary)
                            Text(Fmt.cost(b.cost))
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                            Text(Fmt.tok(b.tok))
                                .font(.system(size: 9, design: .rounded))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                dayChart(u.days)
            } else {
                Text("집계 중…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 300)
        .onReceive(tick) { now = $0 }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(panelOrange)
            Text("사용 한도")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(panelOrange)
            Spacer()
            if let u = usage {
                Text(Fmt.time(u.generated))
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
    }

    private func providerColumn(_ p: LimitProvider) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 4) {
                Circle().fill(panelBrand(p.id)).frame(width: 6, height: 6)
                Text(p.name)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            ForEach(p.limits.prefix(3)) { l in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(l.label)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer(minLength: 2)
                        Text("\(l.remaining)%")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.quaternary)
                            Capsule().fill(panelTint(l.used, brand: panelBrand(p.id)))
                                .frame(width: max(3, g.size.width * Double(l.used) / 100))
                        }
                    }
                    .frame(height: 3)
                    if let r = l.reset {
                        Text(Fmt.resetLabel(r))
                            .font(.system(size: 8, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 한도를 못 읽었을 때만 쓰는 대체 표시. 시간 기반임을 문구로 밝힌다.
    private func blockFallback(_ b: Block) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("5시간 블록 경과")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(Fmt.cost(b.cost))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(panelOrange).frame(
                        width: max(4, g.size.width *
                            min(max((now.timeIntervalSince1970 - b.start) / max(b.end - b.start, 1), 0), 1)))
                }
            }
            .frame(height: 4)
            Text("\(Fmt.remain(b.end - now.timeIntervalSince1970)) 후 리셋")
                .font(.system(size: 9, design: .rounded))
                .foregroundStyle(.tertiary)
        }
    }

    private func dayChart(_ days: [Day]) -> some View {
        let maxV = max(days.map(\.cost).max() ?? 1, 0.01)
        return HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(days.enumerated()), id: \.element.id) { i, d in
                let isToday = i == days.count - 1
                VStack(spacing: 3) {
                    GeometryReader { g in
                        VStack {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(isToday ? AnyShapeStyle(panelOrange) : AnyShapeStyle(.quaternary))
                                .frame(height: max(2, g.size.height * (d.cost / maxV)))
                        }
                    }
                    Text(d.date)
                        .font(.system(size: 7, design: .rounded))
                        .foregroundStyle(isToday ? AnyShapeStyle(panelOrange) : AnyShapeStyle(.tertiary))
                }
            }
        }
        .frame(height: 40)
    }
}

/// 바탕화면 레벨에 떠 있는 반투명 패널. 드래그로 옮길 수 있고 위치는 저장된다.
final class PanelWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private var hosting: NSHostingView<PanelView>!

    convenience init(usage: Usage?, onRefresh: @escaping () -> Void) {
        self.init(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300),
                  styleMask: [.borderless, .fullSizeContentView],
                  backing: .buffered, defer: false)

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 16
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true

        hosting = NSHostingView(rootView: PanelView(usage: usage, onRefresh: onRefresh))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: effect.topAnchor),
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])

        contentView = effect
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        setFrameAutosaveName("CCUsagePanel")
        resize()
        if frame.origin == .zero { moveToDefault() }
    }

    func update(_ usage: Usage?, onRefresh: @escaping () -> Void) {
        hosting.rootView = PanelView(usage: usage, onRefresh: onRefresh)
        resize()
    }

    func moveToDefault() {
        guard let v = NSScreen.main?.visibleFrame else { return }
        setFrameOrigin(NSPoint(x: v.maxX - frame.width - 24, y: v.maxY - frame.height - 24))
    }

    /// 콘텐츠 높이에 맞춰 창을 줄이되 좌상단은 고정한다.
    private func resize() {
        let h = ceil(hosting.fittingSize.height)
        guard h > 1, abs(h - frame.height) > 0.5 else { return }
        let f = frame
        setFrame(NSRect(x: f.origin.x, y: f.maxY - h, width: f.width, height: h), display: true)
    }
}
