// android/app/src/main/java/com/timetodo/model/TimeSession.kt
package com.timetodo.model

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class TimeSession(
    val id: String,
    val todoId: String,
    val startTime: Long,
    val endTime: Long?,
    val durationSeconds: Long? = null,
    val createdAt: Long,
    val updatedAt: Long
)
