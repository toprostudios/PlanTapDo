// android/app/src/androidTest/java/com/timetodo/TodoListScreenTest.kt
package com.timetodo

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import com.timetodo.model.TodoEntry
import com.timetodo.ui.screens.TodoListScreen
import com.timetodo.viewmodel.TodoViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.mockito.kotlin.*

/**
 * Compose UI tests for [TodoListScreen].
 *
 * These tests use a mock [TodoViewModel] so they run without a real network
 * or database – only the Compose rendering layer is exercised.
 */
class TodoListScreenTest {

    @get:Rule
    val composeTestRule = createComposeRule()

    private lateinit var viewModel: TodoViewModel
    private val todosFlow = MutableStateFlow<List<TodoEntry>>(emptyList())

    private fun todo(id: String, title: String, completed: Boolean = false) = TodoEntry(
        id = id,
        title = title,
        categoryId = null,
        isCompleted = completed,
        createdAt = 0L,
        updatedAt = 0L
    )

    @Before
    fun setUp() {
        viewModel = mock {
            on { todos } doReturn todosFlow
        }
    }

    // ── Rendering ─────────────────────────────────────────────────────────────

    @Test
    fun emptyState_showsNoTodoCards() {
        todosFlow.value = emptyList()

        composeTestRule.setContent { TodoListScreen(viewModel) }

        composeTestRule.onAllNodesWithTag("todo_card").assertCountEquals(0)
    }

    @Test
    fun todoCards_areDisplayedForEachEntry() {
        todosFlow.value = listOf(
            todo("1", "Buy milk"),
            todo("2", "Write tests")
        )

        composeTestRule.setContent { TodoListScreen(viewModel) }

        composeTestRule.onNodeWithText("Buy milk").assertIsDisplayed()
        composeTestRule.onNodeWithText("Write tests").assertIsDisplayed()
    }

    @Test
    fun completedTodo_hasCorrectCompletedIndicator() {
        todosFlow.value = listOf(todo("1", "Done task", completed = true))

        composeTestRule.setContent { TodoListScreen(viewModel) }

        // Completed todos should show a strikethrough / done badge (tagged "completed_indicator")
        composeTestRule.onNodeWithTag("completed_indicator").assertIsDisplayed()
    }

    // ── Interactions ──────────────────────────────────────────────────────────

    @Test
    fun clickingDeleteButton_callsViewModelDeleteTodo() {
        todosFlow.value = listOf(todo("42", "Delete me"))

        composeTestRule.setContent { TodoListScreen(viewModel) }

        composeTestRule.onNodeWithTag("delete_todo_42").performClick()

        verify(viewModel).deleteTodo("42")
    }

    @Test
    fun clickingToggleComplete_callsViewModelUpdateTodo() {
        val t = todo("5", "Toggle me")
        todosFlow.value = listOf(t)

        composeTestRule.setContent { TodoListScreen(viewModel) }

        composeTestRule.onNodeWithTag("toggle_complete_5").performClick()

        verify(viewModel).updateTodo(t.copy(isCompleted = !t.isCompleted))
    }

    @Test
    fun clickingTimerButton_callsViewModelStartTimer() {
        todosFlow.value = listOf(todo("7", "Timer todo"))

        composeTestRule.setContent { TodoListScreen(viewModel) }

        composeTestRule.onNodeWithTag("timer_toggle_7").performClick()

        verify(viewModel).startTimer("7")
    }

    // ── List updates ──────────────────────────────────────────────────────────

    @Test
    fun whenTodosFlowEmitsNewList_uiUpdates() {
        todosFlow.value = listOf(todo("1", "First"))

        composeTestRule.setContent { TodoListScreen(viewModel) }
        composeTestRule.onNodeWithText("First").assertIsDisplayed()

        // Emit a new list
        todosFlow.value = listOf(todo("1", "First"), todo("2", "Second"))
        composeTestRule.waitForIdle()

        composeTestRule.onNodeWithText("Second").assertIsDisplayed()
    }
}
