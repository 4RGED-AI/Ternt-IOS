import Foundation
import FoundationModels

struct AILine: Identifiable, Hashable {
    var id = UUID()
    var text: String
    var mine: Bool
}

@MainActor
final class HouseholdBrain {
    func reply(_ message: String, earlier: [AILine], home: PortalHome) async -> String {
        switch SystemLanguageModel.default.availability {
        case .available:
            break
        case .unavailable(.deviceNotEligible):
            return "This iPhone can't run Apple Intelligence, so I can't answer yet."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in Settings, then ask again."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence is still downloading. Ask again in a few minutes."
        @unknown default:
            return "Apple Intelligence isn't ready on this iPhone yet."
        }

        let transcript = earlier.map { ($0.mine ? "Manager: " : "Trytern: ") + $0.text }
            .joined(separator: "\n")
        let prompt = transcript.isEmpty ? message : transcript + "\nManager: " + message
        let session = LanguageModelSession(instructions: instructions(for: home))
        do {
            let response = try await session.respond(to: prompt)
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? "I don't have an answer for that." : text
        } catch {
            return "I couldn't answer that. Try again."
        }
    }

    private func instructions(for home: PortalHome) -> String {
        let people = home.workers.map { "\($0.name) (\($0.kind?.rawValue ?? $0.detail))" }.joined(separator: ", ")
        let tasks = home.tasks.map { task in
            let who = task.worker.isEmpty ? "unassigned" : task.worker
            return "\(task.title) · \(task.detail) · \(who)"
        }.joined(separator: "; ")
        return """
        You are Trytern, the assistant for a household manager in India. \
        Answer in short, plain sentences. Use only the household below. \
        Do not invent people, rooms, or tasks. \
        Home: \(home.name). Helpers: \(people.isEmpty ? "none yet" : people). \
        Tasks: \(tasks.isEmpty ? "none yet" : tasks).
        """
    }
}
