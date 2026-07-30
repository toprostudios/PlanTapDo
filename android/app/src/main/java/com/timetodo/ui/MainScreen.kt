// android/app/src/main/java/com/timetodo/ui/MainScreen.kt
package com.timetodo.ui

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.timetodo.viewmodel.TodoViewModel
import com.timetodo.ui.screens.TodoListScreen
import com.timetodo.ui.screens.CalendarScreen
import com.timetodo.ui.screens.AnalyticsScreen

/**
 * Root composable for the Android client. Provides a Scaffold with a TopBar, BottomNavigation
 * and a NavHost to switch between the three main sections.
 *
 * The UI follows a dark‑mode‑first premium design: the Scaffold uses the background from
 * the Material3 theme, the BottomNavigation icons have subtle glows, and each screen
 * employs glass‑morphism cards with micro‑animations.
 */
@Composable
fun MainScreen() {
    val navController = rememberNavController()
    val todoViewModel: TodoViewModel = hiltViewModel()

    Scaffold(
        topBar = { TopBar(viewModel = todoViewModel) },
        bottomBar = { BottomNavBar(navController) }
    ) { innerPadding ->
        NavHost(
            navController = navController,
            startDestination = "todos",
            modifier = Modifier.padding(innerPadding)
        ) {
            composable("todos") { TodoListScreen(viewModel = todoViewModel) }
            composable("calendar") { CalendarScreen(viewModel = todoViewModel) }
            composable("analytics") { AnalyticsScreen(viewModel = todoViewModel) }
        }
    }
}

@Composable
private fun BottomNavBar(navController: NavHostController) {
    NavigationBar {
        NavigationBarItem(
            selected = navController.currentDestination?.route == "todos",
            onClick = { navController.navigate("todos") { launchSingleTop = true } },
            icon = { Icon(Icons.Default.List, contentDescription = "Todos") },
            label = { Text("Todos") }
        )
        NavigationBarItem(
            selected = navController.currentDestination?.route == "calendar",
            onClick = { navController.navigate("calendar") { launchSingleTop = true } },
            icon = { Icon(Icons.Default.DateRange, contentDescription = "Calendar") },
            label = { Text("Calendar") }
        )
        NavigationBarItem(
            selected = navController.currentDestination?.route == "analytics",
            onClick = { navController.navigate("analytics") { launchSingleTop = true } },
            icon = { Icon(Icons.Default.ShowChart, contentDescription = "Analytics") },
            label = { Text("Analytics") }
        )
    }
}
