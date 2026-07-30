// android/app/src/main/java/com/timetodo/App.kt
package com.timetodo

import android.app.Application
import com.amplitude.api.Amplitude
import com.timetodo.monitoring.AmplitudeManager
import com.timetodo.monitoring.SentryManager
import dagger.hilt.android.HiltAndroidApp
import io.sentry.Sentry

@HiltAndroidApp
class App : Application() {
    override fun onCreate() {
        super.onCreate()
        // Initialize static context provider
        AppContextProvider.init(this)
        // Initialize Amplitude via manager (replace with actual API key)
        AmplitudeManager.init("YOUR_AMPLITUDE_API_KEY")
        // Initialize Sentry directly (or via manager)
        Sentry.init(this) { options ->
            options.dsn = "YOUR_SENTRY_DSN"
        }
    }
}
