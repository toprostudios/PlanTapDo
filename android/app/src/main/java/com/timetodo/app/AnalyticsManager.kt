package com.timetodo.app

import android.content.Context
import com.amplitude.api.Amplitude

object AnalyticsManager {
    fun init(context: Context) {
        val apiKey = System.getenv("AMPLITUDE_API_KEY") ?: "YOUR_AMPLITUDE_API_KEY"
        Amplitude.getInstance().initialize(context, apiKey)
    }

    fun track(event: String, properties: org.json.JSONObject? = null) {
        Amplitude.getInstance().logEvent(event, properties)
    }
}
