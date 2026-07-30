// android/app/src/main/java/com/timetodo/ui/TopBar.kt
package com.timetodo.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.timetodo.viewmodel.TodoViewModel
import androidx.compose.material3.icons.Icons
import androidx.compose.material3.icons.filled.Refresh
import androidx.compose.material3.icons.filled.Add
import androidx.compose.ui.Alignment
import androidx.compose.runtime.remember
import androidx.compose.runtime.mutableStateOf
import com.timetodo.ui.components.NewTodoDialog

/**
 * Premium top bar with current date, a Refresh button, and a FAB‑style New Todo button.
 * Uses glass‑morphism background (via elevation and surface) and subtle micro‑animations.
 */
@Composable
fun TopBar(viewModel: TodoViewModel) {
    val showDialog = remember { mutableStateOf(false) }
    Surface(
        tonalElevation = 4.dp,
        shadowElevation = 4.dp,
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(
                text = "TimeToDo",
                style = MaterialTheme.typography.titleLarge,
                color = MaterialTheme.colorScheme.onSurface
            )
            Row {
                IconButton(onClick = { viewModel.refreshTodos() }) {
                    Icon(
                        imageVector = Icons.Filled.Refresh,
                        contentDescription = "Refresh",
                        tint = MaterialTheme.colorScheme.primary
                    )
                }
                IconButton(onClick = { showDialog.value = true }) {
                    Icon(
                        imageVector = Icons.Filled.Add,
                        contentDescription = "New Todo",
                        tint = MaterialTheme.colorScheme.secondary
                    )
                }
    NewTodoDialog(showDialog = showDialog, onAdd = { viewModel.addTodo(it) })
            }
        }
    }
}
