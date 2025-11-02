//
//  CourtRowView.swift
//  zacks_tennis
//
//  球场列表行视图
//

import SwiftUI

struct CourtRowView: View {
    let court: Court

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(court.name)
                    .font(.headline)

                if court.isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                        .font(.caption)
                }
            }

            Text(court.address)
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Label("\(court.courtCount)片", systemImage: "square.grid.3x3")
                Text("·")
                Text(court.surfaceType)
                Text("·")
                Text(court.priceRange)
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}
