// android/app/src/main/java/com/timetodo/ui/components/TodoCard.kt
package com.timetodo.ui.components

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.timetodo.model.TodoEntry

/**
 * Premium glass‑morphism card for a single Todo.
 * - Shows title, optional description, and a checkbox to toggle completion.
 * - Has a subtle blur background to achieve a frosted‑glass effect.
 * - Clicking the trailing delete icon triggers the provided onDelete callback.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TodoCard(
    todo: TodoEntry,
    onDelete: (TodoEntry) -> Unit,
    onToggleComplete: (TodoEntry) -> Unit,
    onTimerToggle: (TodoEntry) -> Unit,
) {
    Card(
        shape = RoundedCornerShape(12.dp),
        colors = CardDefaults.cardColors(containerColor = Color.Transparent),
        modifier = Modifier
            .fillMaxWidth()
            .blur(12.dp) // glass‑morphism effect
            .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.6f))
            .animateContentSize()
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp)
        ) {
            Checkbox(
                checked = todo.isCompleted,
                onCheckedChange = { onToggleComplete(todo) }
            )
            Column(
                modifier = Modifier
                    .weight(1f)
                    .padding(start = 8.dp)
            ) {
                Text(
                    text = todo.title,
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurface
                )
                todo.description?.let { desc ->
                    Text(
                        text = desc,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2,
                        modifier = Modifier.padding(top = 2.dp)
                    )
                }
            }
            IconButton(onClick = { onTimerToggle(todo) }) {
                Icon(
                    imageVector = if (todo.isTimerRunning) Icons.Filled.Stop else Icons.Filled.PlayArrow,
                    contentDescription = if (todo.isTimerRunning) "Stop timer" else "Start timer",
                    tint = MaterialTheme.colorScheme.primary
                )
            }
            IconButton(onClick = { onDelete(todo) }) {
                Icon(
                    imageVector = Icons.Default.Delete,
                    contentDescription = "Delete",
                    tint = MaterialTheme.colorScheme.error
                )
            }
        }
    }
}
