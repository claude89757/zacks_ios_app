//
//  SuggestionButton.swift
//  zacks_tennis
//
//  建议按钮视图
//

import SwiftUI

struct SuggestionButton: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(text)
                    .font(.subheadline)
                Spacer()
                Image(systemName: "arrow.right.circle")
            }
            .padding()
            .background(Color(.systemGray6))
            .foregroundColor(.primary)
            .cornerRadius(10)
        }
    }
}
