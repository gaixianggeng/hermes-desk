import SwiftUI

struct WorkspaceTaskListRowView: View {
    let title: String
    let introduction: String
    let statusLine: String?
    let stateTitle: String
    let stateSymbolName: String
    let stateTint: Color
    let updatedAtText: String
    let isSelected: Bool
    let showsAttentionDot: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(stateTint.opacity(0.14))
                            .frame(width: 34, height: 34)
                        Image(systemName: stateSymbolName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(stateTint)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            if showsAttentionDot {
                                Circle()
                                    .fill(stateTint)
                                    .frame(width: 7, height: 7)
                            }
                        }

                        Text(introduction)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)

                        if let statusLine, statusLine.isEmpty == false {
                            Text(statusLine)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }

                    Spacer(minLength: 8)
                }

                HStack {
                    Text(stateTitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(stateTint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(stateTint.opacity(0.12), in: Capsule())

                    Spacer(minLength: 8)

                    Text(updatedAtText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
