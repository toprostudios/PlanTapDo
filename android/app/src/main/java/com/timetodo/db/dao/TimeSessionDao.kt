// android/app/src/main/java/com/timetodo/db/dao/TimeSessionDao.kt
package com.timetodo.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import androidx.room.Delete
import com.timetodo.model.TimeSession
import kotlinx.coroutines.flow.Flow

@Dao
interface TimeSessionDao {
    @Query("SELECT * FROM TimeSession")
    fun getAll(): Flow<List<TimeSession>>

    @Query("SELECT * FROM TimeSession WHERE id = :id LIMIT 1")
    suspend fun getById(id: String): TimeSession?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(session: TimeSession)

    @Update
    suspend fun update(session: TimeSession)

    @Delete
    suspend fun delete(session: TimeSession)
}
