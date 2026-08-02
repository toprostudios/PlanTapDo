// AnalyticsManager.swift
// NOTE: Amplitude SDK is not yet added via Swift Package Manager.
// This stub uses os.log so the rest of the app compiles cleanly.
// To enable real Amplitude tracking, add the AmplitudeSwift package
// (https://github.com/amplitude/Amplitude-Swift) and uncomment the
// lines marked AMPLITUDE below.
import Foundation
import os.log

final class AnalyticsManager {
    static let shared = AnalyticsManager()
    private let log = Logger(subsystem: "com.plantapdo.app", category: "Analytics")

    // AMPLITUDE: private var amplitude: Amplitude?

    private init() {}

    func configure() {
        let apiKey = ProcessInfo.processInfo.environment["AMPLITUDE_API_KEY"] ?? "YOUR_AMPLITUDE_API_KEY"
        log.info("AnalyticsManager configured (stub). API key prefix: \(apiKey.prefix(4))")

        // AMPLITUDE:
        // amplitude = Amplitude(configuration: Configuration(apiKey: apiKey))
    }

    func track(event: String, properties: [String: Any]? = nil) {
        log.debug("Track event: \(event), properties: \(String(describing: properties))")

        // AMPLITUDE:
        // amplitude?.track(eventType: event, eventProperties: properties)
    }
}
