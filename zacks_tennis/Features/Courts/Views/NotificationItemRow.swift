//
//  NotificationItemRow.swift
//  zacks_tennis
//
//  提醒列表行视图
//

import SwiftUI

struct NotificationItemRow: View {
    let item: NotificationItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.title)
                    .font(.headline)

                Spacer()

                Toggle("", isOn: .constant(item.isEnabled))
                    .labelsHidden()
            }

            if let court = item.court {
                Text(court.name)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            HStack {
                Label(item.timeSlotsText, systemImage: "clock")
                Text("·")
                Text(item.daysOfWeekText)
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}
