//
//  CourtDetailView.swift
//  zacks_tennis
//
//  球场详情视图
//

import SwiftUI

struct CourtDetailView: View {
    let court: Court

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(court.courtDescription)
                    .padding()

                // 预定按钮区域
                Button {
                    // 跳转到预定页面或微信小程序
                } label: {
                    Label("立即预定", systemImage: "calendar")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
            }
        }
        .navigationTitle(court.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
