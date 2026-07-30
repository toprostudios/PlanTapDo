// android/app/src/main/java/com/timetodo/ui/screens/AnalyticsScreen.kt
package com.timetodo.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.timetodo.viewmodel.TodoViewModel

/**
 * Simple analytics screen placeholder.
 * Shows a title and a placeholder for a chart. In a full implementation,
 * you would use a Compose chart library (e.g., compose‑charts) to render
 * time‑tracking statistics, completed todo counts, etc.
 */
@Composable
fun AnalyticsScreen(viewModel: TodoViewModel) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Top
    ) {
        Text(
            text = "Analytics",
            style = MaterialTheme.typography.headlineMedium,
            modifier = Modifier.padding(bottom = 24.dp)
        )
        // Placeholder chart – a grey box with rounded corners
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(200.dp)
                .background(
                    color = MaterialTheme.colorScheme.surfaceVariant,
                    shape = MaterialTheme.shapes.medium
                )
        ) {
            Text(
                text = "Chart goes here",
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.align(Alignment.Center)
            )
        }
        // Additional stats could be added here using viewModel data
        Spacer(modifier = Modifier.height(24.dp))
        // Example stat
        Text(
            text = "Total Todos: ${viewModel.todos.collectAsState().value.size}",
            style = MaterialTheme.typography.bodyLarge
        )
    }
}
