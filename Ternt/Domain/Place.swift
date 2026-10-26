import Foundation

struct DialCode: Identifiable, Hashable {
    var name: String
    var dial: String
    var length: Int
    var id: String { "\(name)-\(dial)" }
}

enum DialCodes {
    static let all: [DialCode] = [
        DialCode(name: "India", dial: "+91", length: 10),
        DialCode(name: "United Arab Emirates", dial: "+971", length: 9),
        DialCode(name: "United States", dial: "+1", length: 10),
        DialCode(name: "United Kingdom", dial: "+44", length: 10),
        DialCode(name: "Singapore", dial: "+65", length: 8),
        DialCode(name: "Saudi Arabia", dial: "+966", length: 9),
        DialCode(name: "Qatar", dial: "+974", length: 8),
        DialCode(name: "Kuwait", dial: "+965", length: 8),
        DialCode(name: "Oman", dial: "+968", length: 8),
        DialCode(name: "Bahrain", dial: "+973", length: 8),
        DialCode(name: "Canada", dial: "+1", length: 10),
        DialCode(name: "Australia", dial: "+61", length: 9),
        DialCode(name: "Nepal", dial: "+977", length: 10),
        DialCode(name: "Sri Lanka", dial: "+94", length: 9),
        DialCode(name: "Bangladesh", dial: "+880", length: 10),
        DialCode(name: "Pakistan", dial: "+92", length: 10),
        DialCode(name: "Malaysia", dial: "+60", length: 9),
        DialCode(name: "Indonesia", dial: "+62", length: 11),
        DialCode(name: "Thailand", dial: "+66", length: 9),
        DialCode(name: "Germany", dial: "+49", length: 11),
        DialCode(name: "France", dial: "+33", length: 9),
        DialCode(name: "Netherlands", dial: "+31", length: 9),
        DialCode(name: "Ireland", dial: "+353", length: 9),
        DialCode(name: "South Africa", dial: "+27", length: 9),
        DialCode(name: "Nigeria", dial: "+234", length: 10),
        DialCode(name: "Kenya", dial: "+254", length: 9),
        DialCode(name: "Japan", dial: "+81", length: 10),
        DialCode(name: "South Korea", dial: "+82", length: 10),
        DialCode(name: "Hong Kong", dial: "+852", length: 8)
    ]

    static let india = all[0]
}

struct PinPlace: Equatable {
    var city: String
    var state: String
}

enum Pincode {
    static func place(from data: Data) -> PinPlace? {
        guard
            let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
            let row = rows.first,
            (row["Status"] as? String) == "Success",
            let offices = row["PostOffice"] as? [[String: Any]],
            let office = offices.first
        else { return nil }
        let state = (office["State"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let district = (office["District"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !state.isEmpty, !district.isEmpty else { return nil }
        return PinPlace(city: city(from: district), state: state)
    }

    static func city(from district: String) -> String {
        switch district.lowercased() {
        case "bangalore", "bengaluru", "bangalore urban", "bengaluru urban":
            return "Bengaluru"
        case "bombay", "mumbai", "mumbai suburban":
            return "Mumbai"
        case "madras", "chennai":
            return "Chennai"
        case "calcutta", "kolkata":
            return "Kolkata"
        case "new delhi", "delhi", "central delhi", "south delhi", "north delhi", "east delhi", "west delhi":
            return "Delhi"
        default:
            return district
        }
    }

    static func fetch(_ pin: String) async -> PinPlace? {
        guard pin.count == 6, pin.allSatisfy(\.isNumber) else { return nil }
        guard let url = URL(string: "https://api.postalpincode.in/pincode/\(pin)") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return place(from: data)
        } catch {
            return nil
        }
    }
}

enum ClockText {
    static func label(_ date: Date) -> String {
        let hour24 = Calendar.current.component(.hour, from: date)
        let minute = Calendar.current.component(.minute, from: date)
        let hour = hour24 % 12 == 0 ? 12 : hour24 % 12
        return String(format: "%d:%02d %@", hour, minute, hour24 >= 12 ? "PM" : "AM")
    }
}
