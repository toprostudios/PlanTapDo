// android/app/src/main/java/com/timetodo/db/dao/TodoDao.kt
package com.timetodo.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import androidx.room.Delete
import com.timetodo.model.TodoEntry
import kotlinx.coroutines.flow.Flow

@Dao
interface TodoDao {
    @Query("SELECT * FROM TodoEntry")
    fun getAll(): Flow<List<TodoEntry>>

    @Query("SELECT * FROM TodoEntry WHERE id = :id LIMIT 1")
    suspend fun getById(id: String): TodoEntry?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(todo: TodoEntry)

    @Update
    suspend fun update(todo: TodoEntry)

    @Delete
    suspend fun delete(todo: TodoEntry)
}
