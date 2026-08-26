import Foundation
import CoreLocation
import SwiftData
import WeatherKit

/// Backfills historical weather onto runs from WeatherKit — sources rarely record it (Strava's
/// weather panel never leaves their site; Nike writes none), but every outdoor run has a start
/// coordinate and a timestamp, and that's all historical weather needs. Source-recorded values
/// always win: the backfill only fills fields the recorder left empty.
@MainActor
enum WeatherBackfill {

    private static var isRunning = false

    /// One batched pass: the newest not-yet-backfilled located runs. Idempotent and re-entrant
    /// safe — call it from any surface's appearance; repeated passes walk further back through
    /// the history until everything is attempted.
    static func run(context: ModelContext, limit: Int = 60) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        var descriptor = FetchDescriptor<Run>(
            predicate: #Predicate { $0.weatherBackfilled == false && $0.startLatitude != nil },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        guard let runs = try? context.fetch(descriptor), !runs.isEmpty else { return }

        var failures = 0
        for run in runs {
            let succeeded = await backfill(run)
            if !succeeded {
                failures += 1
                // Entitlement missing or network down: every call will fail the same way —
                // stop burning the batch and let a later pass retry.
                if failures >= 3 { break }
            }
        }
        try? context.save()
    }

    /// Fetches the hour of weather covering this run's start and fills the empty fields.
    /// Returns false only on a thrown error (auth / network), which leaves the run unflagged
    /// for retry; "no data for that hour" flags it done — it will never improve.
    @discardableResult
    static func backfill(_ run: Run) async -> Bool {
        guard let lat = run.startLatitude, let lon = run.startLongitude else {
            run.weatherBackfilled = true
            return true
        }
        let location = CLLocation(latitude: lat, longitude: lon)
        let start = run.startDate
        let end = start.addingTimeInterval(max(Double(run.elapsedTime), 3600))
        do {
            let forecast = try await WeatherService.shared.weather(
                for: location, including: .hourly(startDate: start, endDate: end))
            guard let hour = forecast.forecast.first(where: {
                $0.date <= start && start < $0.date.addingTimeInterval(3600)
            }) ?? forecast.forecast.first else {
                run.weatherBackfilled = true
                return true
            }
            if run.weatherTemperatureC == nil {
                run.weatherTemperatureC = hour.temperature.converted(to: .celsius).value
            }
            if run.weatherConditionRaw == nil {
                run.weatherConditionRaw = condition(from: hour.condition)?.rawValue
            }
            if run.weatherHumidity == nil { run.weatherHumidity = hour.humidity }
            if run.weatherFeelsLikeC == nil {
                run.weatherFeelsLikeC = hour.apparentTemperature.converted(to: .celsius).value
            }
            if run.weatherWindSpeedMS == nil {
                run.weatherWindSpeedMS = hour.wind.speed.converted(to: .metersPerSecond).value
            }
            if run.weatherWindDirectionDeg == nil {
                run.weatherWindDirectionDeg = hour.wind.direction.converted(to: .degrees).value
            }
            run.weatherBackfilled = true
            return true
        } catch {
            return false
        }
    }

    /// WeatherKit's taxonomy folded onto the app's small, legible set.
    private static func condition(from wk: WeatherKit.WeatherCondition) -> WeatherCondition? {
        switch wk {
        case .clear, .mostlyClear, .hot:                            return .clear
        case .partlyCloudy:                                         return .partlyCloudy
        case .cloudy, .mostlyCloudy:                                return .cloudy
        case .foggy:                                                return .fog
        case .haze, .smoky:                                         return .hazy
        case .breezy, .windy:                                       return .wind
        case .drizzle:                                              return .drizzle
        case .rain, .heavyRain, .sunShowers:                        return .rain
        case .snow, .heavySnow, .flurries, .blizzard,
             .blowingSnow, .sunFlurries, .wintryMix:                return .snow
        case .sleet, .freezingRain, .freezingDrizzle, .hail:        return .sleet
        case .thunderstorms, .isolatedThunderstorms,
             .scatteredThunderstorms, .strongStorms:                return .thunderstorm
        default:                                                    return nil
        }
    }
}
