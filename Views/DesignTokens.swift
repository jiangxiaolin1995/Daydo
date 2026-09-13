import SwiftUI
import DaydoCore

enum DaydoStyle {
    static let blue = Color(red: 0.145, green: 0.388, blue: 0.922)
    static let colors = ["#2563EB", "#8B5CF6", "#F59E0B", "#10B981", "#EF4444", "#EC4899", "#64748B"]
    static func color(_ hex: String) -> Color {
        let value = UInt64(hex.dropFirst(), radix: 16) ?? 0x2563EB
        return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
    static func priority(_ value: Priority) -> Color {
        switch value { case .high: .red; case .medium: .orange; case .low: .blue; case .none: .secondary }
    }
    static func time(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }
}

struct EmptyTasksView: View {
    var title: String
    var message: String
    var action: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle").font(.system(size: 44, weight: .ultraLight)).foregroundStyle(.blue.opacity(0.8))
            Text(title).font(.title3.weight(.semibold))
            Text(message).foregroundStyle(.secondary)
            Button("添加任务", action: action).buttonStyle(.borderedProminent).controlSize(.large).padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
