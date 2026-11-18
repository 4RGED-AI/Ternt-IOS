import CoreLocation
import Foundation
import GooglePlacesSwift

struct PlaceHit: Identifiable, Hashable {
    var id: String
    var title: String
    var subtitle: String
}

struct MapPoint: Equatable {
    var latitude: Double
    var longitude: Double
}

enum CommunityPlaces {
    private static let fields: [PlaceProperty] = [.placeID, .displayName, .formattedAddress, .addressComponents, .coordinate]
    private static let housing: Set<PlaceType> = [
        PlaceType(rawValue: "apartment_complex"),
        PlaceType(rawValue: "apartment_building"),
        PlaceType(rawValue: "condominium_complex"),
        PlaceType(rawValue: "housing_complex")
    ]
    private static var session = AutocompleteSessionToken()

    @MainActor
    static func nearby(_ point: MapPoint) async -> [Community] {
        let request = SearchNearbyRequest(
            locationRestriction: CircularCoordinateRegion(center: point.coordinate, radius: 800),
            placeProperties: fields,
            includedTypes: housing,
            maxResultCount: 8,
            rankPreference: .distance,
            regionCode: "IN"
        )
        guard case .success(let response) = await PlacesClient.shared.responseForSearchNearby(with: request) else { return [] }
        return (response.places ?? []).compactMap(community(from:))
    }

    @MainActor
    static func search(_ query: String, near point: MapPoint?) async -> [PlaceHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        async let suggested = autocomplete(trimmed, near: point)
        async let matched = textSearch(trimmed, near: point)
        let suggestedHits = await suggested
        let matchedHits = await matched
        var seen = Set<String>()
        var hits: [PlaceHit] = []
        for hit in suggestedHits + matchedHits where seen.insert(hit.id).inserted {
            hits.append(hit)
            if hits.count == 20 { break }
        }
        return hits
    }

    @MainActor
    private static func autocomplete(_ query: String, near point: MapPoint?) async -> [PlaceHit] {
        let filter = AutocompleteFilter(
            countries: ["IN"],
            origin: point.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) },
            coordinateRegionBias: point.map { CircularCoordinateRegion(center: $0.coordinate, radius: 8000) },
            regionCode: "IN"
        )
        let request = AutocompleteRequest(query: query, sessionToken: session, filter: filter)
        guard case .success(let suggestions) = await PlacesClient.shared.fetchAutocompleteSuggestions(with: request) else { return [] }
        return suggestions.compactMap { suggestion in
            guard case .place(let place) = suggestion else { return nil }
            return PlaceHit(
                id: place.placeID,
                title: String(place.attributedPrimaryText.characters),
                subtitle: place.attributedSecondaryText.map { String($0.characters) } ?? ""
            )
        }
    }

    @MainActor
    private static func textSearch(_ query: String, near point: MapPoint?) async -> [PlaceHit] {
        let bias: any CoordinateRegionBias
        if let point {
            bias = CircularCoordinateRegion(center: point.coordinate, radius: 50_000)
        } else if let india = RectangularCoordinateRegion(
            northEast: CLLocationCoordinate2D(latitude: 35.5, longitude: 97.5),
            southWest: CLLocationCoordinate2D(latitude: 6.5, longitude: 68.1)
        ) {
            bias = india
        } else {
            return []
        }
        let request = SearchByTextRequest(
            textQuery: query,
            placeProperties: [.placeID, .displayName, .formattedAddress],
            locationBias: bias,
            maxResultCount: 20,
            isOpenNow: false,
            rankPreference: .relevance,
            regionCode: "IN"
        )
        guard case .success(let places) = await PlacesClient.shared.searchByText(with: request) else { return [] }
        return places.compactMap { place in
            guard let id = place.placeID, let title = place.displayName, !title.isEmpty else { return nil }
            return PlaceHit(id: id, title: title, subtitle: place.formattedAddress ?? "")
        }
    }

    @MainActor
    static func details(_ placeID: String) async -> Community? {
        let request = FetchPlaceRequest(placeID: placeID, placeProperties: fields, sessionToken: session)
        session = AutocompleteSessionToken()
        guard case .success(let place) = await PlacesClient.shared.fetchPlace(with: request) else { return nil }
        return community(from: place)
    }

    static func locate() async -> MapPoint? {
        let box = LocationBox()
        return await box.fix()
    }

    private static func community(from place: Place) -> Community? {
        let name = place.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty, let id = place.placeID, !id.isEmpty else { return nil }
        let parts = place.addressComponents ?? []
        func part(_ type: PlaceType) -> String {
            parts.first { $0.types.contains(type) }?.name ?? ""
        }
        let street = [part(.streetNumber), part(.route)].filter { !$0.isEmpty }.joined(separator: " ")
        let area = [part(.sublocalityLevel1), part(.sublocality), part(.neighborhood)].first { !$0.isEmpty } ?? ""
        let coordinate = place.location
        let placed = CLLocationCoordinate2DIsValid(coordinate)
            && abs(coordinate.latitude) > 0.01
            && abs(coordinate.longitude) > 0.01
        return Community(
            id: id,
            name: name,
            street: street,
            area: area,
            city: part(.locality),
            pincode: part(.postalCode),
            state: part(.administrativeAreaLevel1),
            latitude: placed ? coordinate.latitude : nil,
            longitude: placed ? coordinate.longitude : nil
        )
    }
}

private extension MapPoint {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

private final class LocationBox: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<MapPoint?, Never>?
    private var started = false

    func fix() async -> MapPoint? {
        manager.delegate = self
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            let status = manager.authorizationStatus
            if status == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else {
                handle(status)
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        handle(manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            finish(nil)
            return
        }
        finish(MapPoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(nil)
    }

    private func handle(_ status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            guard !started else { return }
            started = true
            manager.requestLocation()
        case .notDetermined:
            break
        default:
            finish(nil)
        }
    }

    private func finish(_ point: MapPoint?) {
        continuation?.resume(returning: point)
        continuation = nil
    }
}
