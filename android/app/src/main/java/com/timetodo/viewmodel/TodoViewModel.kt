// android/app/src/main/java/com/timetodo/viewmodel/TodoViewModel.kt
package com.timetodo.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.timetodo.model.TodoEntry
import com.timetodo.repository.TodoRepository
import com.timetodo.socket.TodoWebSocket
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject
import android.content.Context

/**
 * ViewModel mirroring the web store functionality.
 * It provides CRUD operations, timer handling, and reacts to WebSocket refresh messages.
 */
@HiltViewModel
class TodoViewModel @Inject constructor(
    private val repository: TodoRepository,
    @ApplicationContext private val context: Context,
    // Provide the WebSocket URL; replace with actual backend URL.
    private val wsUrl: String = "wss://your-api.example.com/ws/todos/"
) : ViewModel() {
    private val _todos = MutableStateFlow<List<TodoEntry>>(emptyList())
    val todos: StateFlow<List<TodoEntry>> = _todos.asStateFlow()

    private val ws = TodoWebSocket(wsUrl) { tokenProvider() }

    init {
        // Load from local DB and refresh from network
        viewModelScope.launch {
            repository.todos.collect { localList ->
                _todos.value = localList
            }
        }
        // Initial network sync
        viewModelScope.launch { repository.refreshTodos() }
        // Set up WebSocket handler
        ws.setMessageHandler { message ->
            // Expect JSON with a "type" field, e.g., {"type":"refresh"}
            if (message.contains("\"type\":\"refresh\"")) {
                viewModelScope.launch { repository.refreshTodos() }
            }
        }
        ws.connect()
    }

    private fun tokenProvider(): String? {
        // Retrieve token from AuthViewModel's shared preferences (simple approach)
        // Assuming AuthViewModel stored token in EncryptedSharedPreferences under key "jwt_token".
        val prefs = context.getSharedPreferences("auth_prefs", Context.MODE_PRIVATE)
        return prefs.getString("jwt_token", null)
    }

    // CRUD helpers
    fun addTodo(todo: TodoEntry) = viewModelScope.launch { repository.addTodo(todo) }
    fun updateTodo(todo: TodoEntry) = viewModelScope.launch { repository.updateTodo(todo) }
    fun deleteTodo(id: String) = viewModelScope.launch { repository.deleteTodo(id) }

    // Timer handling (simple increment)
    fun startTimer(todoId: String) {
        // Implementation detail: could call an API endpoint to start a session.
        // Placeholder: not implemented yet.
    }

    fun stopTimer(todoId: String) {
        // Placeholder for stopping timer.
    }

    fun refreshTodos() = viewModelScope.launch { repository.refreshTodos() }

    override fun onCleared() {
        super.onCleared()
        ws.disconnect()
    }
}
