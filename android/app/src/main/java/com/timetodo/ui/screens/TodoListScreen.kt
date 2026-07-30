// android/app/src/main/java/com/timetodo/ui/screens/TodoListScreen.kt
package com.timetodo.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.timetodo.model.TodoEntry
import com.timetodo.viewmodel.TodoViewModel
import com.timetodo.ui.components.TodoCard
import kotlinx.coroutines.launch

/**
 * Premium todo list screen.
 * - Shows a pull‑to‑refresh indicator.
 * - Each todo is displayed as a glass‑morphism card with subtle elevation.
 * - Swipe‑to‑delete is hinted via a trailing icon (full swipe gesture requires
 *   additional libraries; this is a simplified version).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TodoListScreen(viewModel: TodoViewModel) {
    val todos by viewModel.todos.collectAsState()
    val coroutineScope = rememberCoroutineScope()
    var isRefreshing by remember { mutableStateOf(false) }

    // Simple pull‑to‑refresh using SwipeRefresh from Material3 (experimental)
    val refreshState = rememberPullRefreshState(isRefreshing)

    Box(modifier = Modifier
        .fillMaxSize()
        .pullRefresh(refreshState)) {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            items(todos, key = { it.id }) { todo ->
                TodoCard(
                    todo = todo,
                    onDelete = { viewModel.deleteTodo(it.id) },
                    onToggleComplete = { updated ->
                        viewModel.updateTodo(updated.copy(isCompleted = !updated.isCompleted))
                    },
                    onTimerToggle = { viewModel.startTimer(it.id) }
                )
            }
        }
        PullRefreshIndicator(isRefreshing, refreshState, Modifier.align(Alignment.TopCenter))
    }

    // Trigger refresh when user pulls
    LaunchedEffect(isRefreshing) {
        if (isRefreshing) {
            viewModel.refreshTodos()
            coroutineScope.launch {
                // Simulate short loading time
                kotlinx.coroutines.delay(800)
                isRefreshing = false
            }
        }
    }
}
