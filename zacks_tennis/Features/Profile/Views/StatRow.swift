//
//  StatRow.swift
//  zacks_tennis
//
//  统计数据行视图
//

import SwiftUI

struct StatRow: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)

            Text(title)

            Spacer()

            Text(value)
                .foregroundColor(.secondary)
        }
    }
}
