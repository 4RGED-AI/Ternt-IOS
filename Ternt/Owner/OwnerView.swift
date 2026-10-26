import SwiftUI

struct OwnerView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    var body: some View {
        TabView {
            Tab("Today", systemImage: "sun.horizon") { TodayTab() }
            Tab("House", systemImage: "house") { HouseTab() }
            Tab("People", systemImage: "person.2") { PeopleTab() }
            Tab("Complex", systemImage: "building.2") { ComplexTab() }
        }
        .tint(palette.ink)
    }
}

private struct TodayTab: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    var body: some View {
        let home = app.portal.active
        let review = home.tasks.filter(\.review)
        let today = home.tasks.filter { !$0.review }
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(greeting)
                        .font(.largeTitle.weight(.semibold))
                    Text(home.community)
                        .font(.body)
                        .foregroundStyle(palette.secondary)
                    homeMenu
                    HStack(spacing: 10) {
                        stat("\(today.count)", "On today")
                        stat("\(home.people.count)", "People")
                        stat("\(review.count)", "To review")
                    }
                    section("On today") {
                        if today.isEmpty {
                            Text("Nothing scheduled today.")
                                .foregroundStyle(palette.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                        } else {
                            ForEach(today) { task in
                                row(task.title, task.detail)
                            }
                        }
                    }
                    if !review.isEmpty {
                        section("To review") {
                            ForEach(review) { task in
                                row(task.title, task.detail)
                            }
                        }
                    }
                }
                .padding(22)
            }
            .background(palette.canvas)
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private var homeMenu: some View {
        Menu {
            ForEach(app.portal.homes) { home in
                Button(home.name) { app.selectHome(home.id) }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.portal.active.name).font(.body.weight(.semibold))
                    Text(app.portal.active.line).font(.caption).foregroundStyle(palette.secondary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.caption)
            }
            .padding(16)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func stat(_ value: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title2.weight(.semibold))
            Text(title).font(.caption).foregroundStyle(palette.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            VStack(spacing: 0) { content() }
                .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func row(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.body.weight(.medium))
            Text(detail).font(.caption).foregroundStyle(palette.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }
}

private struct HouseTab: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    var body: some View {
        let home = app.portal.active
        NavigationStack {
            List(home.rooms, id: \.self) { room in
                Text(room)
            }
            .navigationTitle(home.name)
            .background(palette.canvas)
        }
    }
}

private struct PeopleTab: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    var body: some View {
        NavigationStack {
            List(app.portal.active.people) { person in
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.name).font(.body.weight(.medium))
                    Text(person.detail).font(.caption).foregroundStyle(palette.secondary)
                    if !person.phone.isEmpty {
                        Text(person.phone).font(.caption).foregroundStyle(palette.tertiary)
                    }
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("People")
        }
    }
}

private struct ComplexTab: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    var body: some View {
        let home = app.portal.active
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                Text(home.community).font(.title2.weight(.semibold))
                Text("\(home.area), \(home.city)")
                    .foregroundStyle(palette.secondary)
                Text(home.line).foregroundStyle(palette.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
            .background(palette.canvas)
            .navigationTitle("Complex")
        }
    }
}

struct WorkerView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Preview")
                    .font(.largeTitle.weight(.semibold))
                Text("Two visits")
                    .font(.title3)
                Text("The worker side stays a preview until a home shares work.")
                    .foregroundStyle(palette.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
            .background(palette.canvas)
        }
    }
}
