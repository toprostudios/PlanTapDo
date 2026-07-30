// android/app/src/main/java/com/timetodo/db/AppDatabase.kt
package com.timetodo.db

import androidx.room.Database
import androidx.room.RoomDatabase
import com.timetodo.model.Category
import com.timetodo.model.TodoEntry
import com.timetodo.model.TimeSession
import com.timetodo.db.dao.CategoryDao
import com.timetodo.db.dao.TodoDao
import com.timetodo.db.dao.TimeSessionDao

/**
 * Room database that holds the app's local data.
 * Version 1 includes Category, TodoEntry and TimeSession tables.
 */
@Database(
    entities = [Category::class, TodoEntry::class, TimeSession::class],
    version = 1,
    exportSchema = false
)
abstract class AppDatabase : RoomDatabase() {
    abstract fun categoryDao(): CategoryDao
    abstract fun todoDao(): TodoDao
    abstract fun timeSessionDao(): TimeSessionDao
}
