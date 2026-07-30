// SentryManager.kt
package com.timetodo.app

import android.content.Context
import io.sentry.Sentry
import io.sentry.SentryOptions

object SentryManager {
    fun init(context: Context) {
        val dsn = System.getenv("SENTRY_DSN") ?: "YOUR_SENTRY_DSN"
        Sentry.init { options: SentryOptions ->
            options.dsn = dsn
            options.debug = true
            options.enableAutoSessionTracking = true
            options.sessionTrackingIntervalMillis = 60000
        }
    }
}
