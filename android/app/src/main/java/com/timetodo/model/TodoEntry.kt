// android/app/src/main/java/com/timetodo/model/TodoEntry.kt
package com.timetodo.model

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class TodoEntry(
    val id: String,
    val title: String,
    val description: String? = null,
    val categoryId: String?,
    val isCompleted: Boolean = false,
    val createdAt: Long,
    val updatedAt: Long,
    val dueDate: Long? = null,
    val timerSeconds: Long = 0L
)
