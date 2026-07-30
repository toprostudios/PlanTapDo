// android/app/src/main/java/com/timetodo/ui/components/NewTodoDialog.kt
package com.timetodo.ui.components

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Dialog
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.timetodo.model.TodoEntry
import java.util.UUID

/**
 * Simple dialog for creating a new Todo.
 * For brevity we only capture title and optional description.
 * In a full implementation you could add category selection, due date picker, etc.
 */
@Composable
fun NewTodoDialog(
    showDialog: MutableState<Boolean>,
    onAdd: (TodoEntry) -> Unit,
    onDismiss: () -> Unit = { showDialog.value = false }
) {
    if (!showDialog.value) return

    val titleState = remember { mutableStateOf("") }
    val descriptionState = remember { mutableStateOf("") }

    Dialog(onDismissRequest = { onDismiss() }) {
        Column(modifier = Modifier
            .fillMaxWidth()
            .padding(24.dp)) {
            Text(text = "New Todo", style = MaterialTheme.typography.titleLarge)
            Spacer(modifier = Modifier.height(16.dp))
            OutlinedTextField(
                value = titleState.value,
                onValueChange = { titleState.value = it },
                label = { Text("Title") },
                modifier = Modifier.fillMaxWidth()
            )
            Spacer(modifier = Modifier.height(8.dp))
            OutlinedTextField(
                value = descriptionState.value,
                onValueChange = { descriptionState.value = it },
                label = { Text("Description (optional)") },
                modifier = Modifier.fillMaxWidth()
            )
            Spacer(modifier = Modifier.height(24.dp))
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = androidx.compose.foundation.layout.Arrangement.End) {
                Button(onClick = {
                    // Build TodoEntry and forward to ViewModel
                    val now = System.currentTimeMillis()
                    val todo = TodoEntry(
                        id = UUID.randomUUID().toString(),
                        title = titleState.value,
                        description = descriptionState.value.ifBlank { null },
                        categoryId = null,
                        isCompleted = false,
                        createdAt = now,
                        updatedAt = now,
                        dueDate = null,
                        timerSeconds = 0L
                    )
                    onAdd(todo)
                    showDialog.value = false
                }) {
                    Text("Add")
                }
                Spacer(modifier = Modifier.width(8.dp))
                Button(onClick = { onDismiss() }) {
                    Text("Cancel")
                }
            }
        }
    }
}
