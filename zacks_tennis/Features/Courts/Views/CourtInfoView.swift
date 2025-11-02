//
//  CourtInfoView.swift
//  zacks_tennis
//
//  网球场信息视图 - 显示各城市网球场列表和预定方式
//

import SwiftUI
import SwiftData

struct CourtInfoView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var courts: [Court]

    @State private var selectedCity: String = "北京"
    @State private var searchText: String = ""
    @State private var selectedView: ViewType = .courts

    let cities = ["北京", "上海", "广州", "深圳", "成都", "杭州"]

    enum ViewType: String, CaseIterable {
        case courts = "场地"
        case notifications = "提醒"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 顶部切换控件
                Picker("选择视图", selection: $selectedView) {
                    ForEach(ViewType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                // 根据选择显示不同内容
                if selectedView == .courts {
                    // 城市选择器
                    cityPicker

                    // 网球场列表
                    if filteredCourts.isEmpty {
                        emptyStateView
                    } else {
                        courtList
                    }
                } else {
                    // 提醒中心
                    NotificationCenterView()
                }
            }
            .navigationTitle("场地")
            .searchable(text: $searchText, prompt: "搜索球场")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        addSampleCourts()
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                }
            }
        }
    }

    // MARK: - City Picker

    private var cityPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(cities, id: \.self) { city in
                    Button {
                        selectedCity = city
                    } label: {
                        Text(city)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(selectedCity == city ? Color.green : Color(.systemGray6))
                            .foregroundColor(selectedCity == city ? .white : .primary)
                            .cornerRadius(20)
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Court List

    private var courtList: some View {
        List(filteredCourts) { court in
            NavigationLink(destination: CourtDetailView(court: court)) {
                CourtRowView(court: court)
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "tennis.racket")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("暂无球场信息")
                .font(.title3)
                .fontWeight(.semibold)

            Text("点击右上角 + 号添加示例数据")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Computed Properties

    private var filteredCourts: [Court] {
        courts.filter { court in
            court.city == selectedCity &&
            (searchText.isEmpty || court.name.localizedCaseInsensitiveContains(searchText))
        }
    }

    // MARK: - Helper Methods

    private func addSampleCourts() {
        let sampleCourt = Court(
            name: "东方网球中心",
            city: selectedCity,
            address: "朝阳区东三环北路甲2号",
            courtDescription: "北京市最大的综合性网球场馆之一",
            courtCount: 12,
            surfaceType: "硬地",
            isIndoor: false,
            bookingMethod: "微信小程序",
            priceRange: "¥100-300/小时",
            openingHours: "06:00-22:00",
            facilities: ["灯光", "停车场", "淋浴", "商店"]
        )

        modelContext.insert(sampleCourt)
        try? modelContext.save()
    }
}

// MARK: - Preview

#Preview {
    CourtInfoView()
        .modelContainer(for: [Court.self], inMemory: true)
}
