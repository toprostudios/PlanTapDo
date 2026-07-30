// android/app/src/main/java/com/timetodo/model/RepeatRule.kt
package com.timetodo.model

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class RepeatRule(
    val id: String,
    val todoId: String,
    val intervalDays: Int,
    val startDate: Long,
    val endDate: Long?,
    val createdAt: Long,
    val updatedAt: Long
)
