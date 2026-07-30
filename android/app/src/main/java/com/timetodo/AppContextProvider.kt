// android/app/src/main/java/com/timetodo/AppContextProvider.kt
package com.timetodo

import android.app.Application

/**
 * Simple object to expose the Application context for places where a static context is needed
 * (e.g., Amplitude initialization). The Application subclass sets this reference on creation.
 */
object AppContextProvider {
    lateinit var context: Application
        private set

    fun init(app: Application) {
        context = app
    }
}
