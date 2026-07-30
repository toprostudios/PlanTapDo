// android/app/src/main/java/com/timetodo/monitoring/AmplitudeManager.kt
package com.timetodo.monitoring

import com.amplitude.api.Amplitude

object AmplitudeManager {
    /**
     * Call this once on application start to initialize Amplitude with your API key.
     * The API key can be set via a constant or retrieved from a secure source.
     */
    fun init(apiKey: String) {
        Amplitude.getInstance().initialize(com.timetodo.AppContextProvider.context, apiKey)
    }

    /**
     * Simple wrapper to log events.
     */
    fun logEvent(eventName: String, properties: Map<String, Any>? = null) {
        if (properties != null) {
            Amplitude.getInstance().logEvent(eventName, properties)
        } else {
            Amplitude.getInstance().logEvent(eventName)
        }
    }
}
