// android/app/src/main/java/com/timetodo/repository/TodoRepository.kt
package com.timetodo.repository

import com.timetodo.api.ApiService
import com.timetodo.db.dao.TodoDao
import com.timetodo.model.TodoEntry
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Repository that mediates between the remote API and the local Room database.
 * It exposes a Flow of TodoEntry list for UI consumption and methods to perform CRUD.
 */
@Singleton
class TodoRepository @Inject constructor(
    private val apiService: ApiService,
    private val todoDao: TodoDao
) {
    // Observe local DB
    val todos: Flow<List<TodoEntry>> = todoDao.getAll()

    // Refresh from network and store locally
    suspend fun refreshTodos() = withContext(Dispatchers.IO) {
        val response = apiService.getTodos().execute()
        if (response.isSuccessful) {
            response.body()?.forEach { todoDao.insert(it) }
        } else {
            // optionally handle error
        }
    }

    suspend fun addTodo(todo: TodoEntry) = withContext(Dispatchers.IO) {
        // Send to server
        val resp = apiService.createTodo(todo).execute()
        if (resp.isSuccessful) {
            resp.body()?.let { todoDao.insert(it) }
        }
    }

    suspend fun updateTodo(todo: TodoEntry) = withContext(Dispatchers.IO) {
        val resp = apiService.updateTodo(todo.id, todo).execute()
        if (resp.isSuccessful) {
            resp.body()?.let { todoDao.update(it) }
        }
    }

    suspend fun deleteTodo(id: String) = withContext(Dispatchers.IO) {
        val resp = apiService.deleteTodo(id).execute()
        if (resp.isSuccessful) {
            // Remove from local DB
            val local = todoDao.getById(id).first()
            local?.let { todoDao.delete(it) }
        }
    }
}
