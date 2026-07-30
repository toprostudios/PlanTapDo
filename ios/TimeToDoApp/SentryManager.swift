// SentryManager.swift
// NOTE: Sentry SDK is not yet added via Swift Package Manager.
// This stub uses os.log so the rest of the app compiles cleanly.
// To enable real Sentry monitoring, add the Sentry package
// (https://github.com/getsentry/sentry-cocoa) and uncomment the
// lines marked SENTRY below.
import Foundation
import os.log

final class SentryManager {
    static let shared = SentryManager()
    private let log = Logger(subsystem: "com.timetodo.app", category: "Sentry")

    private init() {}

    func configure() {
        let dsn = ProcessInfo.processInfo.environment["SENTRY_DSN"] ?? "YOUR_SENTRY_DSN"
        log.info("SentryManager configured (stub). DSN prefix: \(dsn.prefix(8))")

        // SENTRY:
        // SentrySDK.start { options in
        //     options.dsn = dsn
        //     options.debug = true
        //     options.enableAutoSessionTracking = true
        // }
    }

    func capture(error: Error) {
        log.error("Captured error: \(error.localizedDescription)")

        // SENTRY:
        // SentrySDK.capture(error: error)
    }

    func capture(message: String) {
        log.warning("Captured message: \(message)")

        // SENTRY:
        // SentrySDK.capture(message: message)
    }
}
