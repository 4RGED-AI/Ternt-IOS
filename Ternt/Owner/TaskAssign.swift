import SwiftUI

struct HelperTasksSheet: View {
    let person: PortalPerson
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var tasks: [HouseTask] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("What does \(person.name) do? Untick what isn't theirs.")
                        .font(.subheadline)
                        .foregroundStyle(palette.secondary)
                    TaskChecklist(
                        tasks: tasks,
                        toggle: { id in edit(id) { $0.on.toggle() } },
                        flip: { id in edit(id) { $0.cadence = $0.cadence.next } },
                        rename: { id, title in edit(id) { $0.title = title } },
                        add: { tasks.append(HouseTask(title: "", cadence: .daily, car: carID)) }
                    )
                }
                .padding(22)
            }
            .background(palette.canvas)
            .navigationTitle(person.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Skip") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        app.assignTasks(tasks, to: person.name)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(palette.canvas)
        .onAppear {
            guard tasks.isEmpty else { return }
            let home = app.portal.active
            let taken = Set(home.tasks.filter { !$0.worker.isEmpty }.map { $0.title.lowercased() })
            tasks = HelperTasks.make(for: person.kind, rooms: home.rooms.map(\.name), car: carID, taken: taken)
        }
    }

    private var carID: String {
        person.kind == .driver ? app.portal.active.cars.first?.id ?? "" : ""
    }

    private func edit(_ id: UUID, _ change: (inout HouseTask) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        change(&tasks[index])
    }
}
