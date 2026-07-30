// android/app/src/main/java/com/timetodo/ui/screens/CalendarScreen.kt
package com.timetodo.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp
import com.timetodo.model.TodoEntry
import com.timetodo.viewmodel.TodoViewModel
import kotlinx.coroutines.launch

/**
 * Simplified calendar view.
 * For each TodoEntry, we show a draggable card that can be moved to a date slot.
 * This is a placeholder implementation – a full calendar UI would require a custom view.
 */
@Composable
fun CalendarScreen(viewModel: TodoViewModel) {
    val todos by viewModel.todos.collectAsState()
    val coroutineScope = rememberCoroutineScope()

    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        Text("Calendar", style = MaterialTheme.typography.headlineMedium)
        Spacer(modifier = Modifier.height(8.dp))
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            items(todos, key = { it.id }) { todo ->
                var offsetY by remember { mutableStateOf(0f) }
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(80.dp)
                        .offset(y = offsetY.dp)
                        .pointerInput(Unit) {
                            detectDragGestures { change, dragAmount ->
                                change.consume()
                                offsetY += dragAmount.y
                            }
                        },
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)
                ) {
                    Column(modifier = Modifier
                        .fillMaxWidth()
                        .padding(8.dp)) {
                        Text(todo.title, style = MaterialTheme.typography.bodyLarge)
                        Spacer(modifier = Modifier.height(4.dp))
                        Button(onClick = {
                            // Set due date to today (midnight)
                            val today = System.currentTimeMillis()
                            viewModel.updateTodo(todo.copy(dueDate = today))
                        }) {
                            Text("Set Due Today")
                        }
                    }
                }
            }
        }
    }
}
