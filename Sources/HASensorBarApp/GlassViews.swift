import SwiftUI
import AppKit
import HASensorBarCore

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct GlassBackground: View {
    var style: GlassStyle = .balanced
    var body: some View {
        ZStack {
            VisualEffect()
            Rectangle().fill(.ultraThinMaterial)
            Rectangle().fill(Color(nsColor: .windowBackgroundColor).opacity(style == .solid ? 0.78 : style == .balanced ? 0.24 : 0.04))
            LinearGradient(colors: [.white.opacity(0.13), .clear, .cyan.opacity(0.025)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

struct GlassCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(
                LinearGradient(colors: [.white.opacity(0.38), .white.opacity(0.08)],
                               startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
            .shadow(color: .black.opacity(0.045), radius: 10, x: 0, y: 4)
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    var active = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                .foregroundStyle(active ? Color.teal : .secondary)
                .frame(width: 29, height: 29)
                .background(active ? Color.teal.opacity(0.12) : Color.primary.opacity(0.035),
                            in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).help(help).accessibilityLabel(help)
    }
}

struct Pill: View {
    let text: String
    var tint: Color = .secondary
    var body: some View {
        Text(text).font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .foregroundStyle(tint).background(tint.opacity(0.09), in: Capsule())
    }
}

struct FieldRow: View {
    let field: SensorField
    let value: FieldValue
    var tint: Color {
        guard let fraction = value.remainingFraction else { return .secondary }
        if fraction > 0.5 { return .teal }
        return fraction >= 0.2 ? .orange : Color(red: 0.95, green: 0.36, blue: 0.33)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(field.title).font(.system(size: 12)).foregroundStyle(.secondary)
                if field.direction == .used, value.remainingFraction != nil {
                    Text("used").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                Spacer(minLength: 8)
                if case .unavailable = value {
                    Text("—").font(.system(size: 13, weight: .medium)).foregroundStyle(.tertiary)
                        .accessibilityLabel("Unavailable")
                } else if case .date(_, true) = value {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(value.display(now: context.date)).font(.system(size: 12, weight: .medium)).monospacedDigit()
                    }
                } else {
                    Text(value.display()).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(value.remainingFraction == nil ? Color.primary : tint)
                        .lineLimit(2).textSelection(.enabled)
                }
            }
            if let fraction = value.remainingFraction {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.055))
                        Capsule().fill(LinearGradient(colors: [tint.opacity(0.7), tint],
                                                       startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(0, geometry.size.width * fraction))
                    }
                }.frame(height: 5)
                    .accessibilityLabel("\(field.title), \(Int(fraction * 100)) percent remaining")
            }
        }
        .help("\(field.binding.entityID) · \(field.binding.valuePath.string)")
    }
}

struct SensorCardView: View {
    let card: SensorCard
    let entities: [String: HAEntity]
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 10) {
                    Image(systemName: card.symbol).font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.teal).frame(width: 33, height: 33)
                        .background(.teal.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                    Text(card.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                    Spacer(minLength: 0)
                    if !card.tag.isEmpty { Pill(text: card.tag) }
                }
                ForEach([card.fiveHour, card.sevenDay].compactMap { $0 }) { field in
                    FieldRow(field: field, value: FieldResolver.resolve(field, entities: entities))
                }
                if !card.extras.isEmpty {
                    Rectangle().fill(Color.primary.opacity(0.055)).frame(height: 1)
                    ForEach(card.extras) { field in
                        FieldRow(field: field, value: FieldResolver.resolve(field, entities: entities))
                    }
                }
                if let reset = card.reset {
                    FieldRow(field: reset, value: FieldResolver.resolve(reset, entities: entities))
                }
                if card.fields.isEmpty {
                    Text("Add sensor bindings in Settings.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
