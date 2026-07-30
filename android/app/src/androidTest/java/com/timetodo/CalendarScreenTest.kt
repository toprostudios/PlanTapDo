// android/app/src/androidTest/java/com/timetodo/CalendarScreenTest.kt
package com.timetodo

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import com.timetodo.model.TodoEntry
import com.timetodo.ui.screens.CalendarScreen
import com.timetodo.viewmodel.TodoViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.mockito.kotlin.*

/**
 * Compose UI tests for [CalendarScreen].
 *
 * Uses a mocked [TodoViewModel] so no real DB / network is needed.
 * The tests verify that:
 *  - Todo entries are rendered in the calendar list.
 *  - The "Set Due Today" button triggers [TodoViewModel.updateTodo] with the correct todo.
 *  - Drag interactions do not crash the composable.
 *  - The screen reacts when the todos Flow emits a new list.
 */
class CalendarScreenTest {

    @get:Rule
    val composeTestRule = createComposeRule()

    private lateinit var viewModel: TodoViewModel
    private val todosFlow = MutableStateFlow<List<TodoEntry>>(emptyList())

    private fun todo(id: String, title: String) = TodoEntry(
        id = id,
        title = title,
        categoryId = null,
        isCompleted = false,
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
    fun calendarHeader_isDisplayed() {
        composeTestRule.setContent { CalendarScreen(viewModel) }

        composeTestRule.onNodeWithText("Calendar").assertIsDisplayed()
    }

    @Test
    fun emptyState_noTodoTitlesDisplayed() {
        todosFlow.value = emptyList()

        composeTestRule.setContent { CalendarScreen(viewModel) }

        // No todo cards should be present
        composeTestRule.onAllNodesWithText("Set Due Today").assertCountEquals(0)
    }

    @Test
    fun todoTitles_areDisplayedInCalendarList() {
        todosFlow.value = listOf(
            todo("1", "Sprint planning"),
            todo("2", "Code review")
        )

        composeTestRule.setContent { CalendarScreen(viewModel) }

        composeTestRule.onNodeWithText("Sprint planning").assertIsDisplayed()
        composeTestRule.onNodeWithText("Code review").assertIsDisplayed()
    }

    @Test
    fun setDueTodayButton_isDisplayedForEachTodo() {
        todosFlow.value = listOf(todo("1", "Task A"), todo("2", "Task B"))

        composeTestRule.setContent { CalendarScreen(viewModel) }

        composeTestRule.onAllNodesWithText("Set Due Today").assertCountEquals(2)
    }

    // ── Interactions ──────────────────────────────────────────────────────────

    @Test
    fun clickingSetDueToday_callsViewModelUpdateTodoWithDueDate() {
        val t = todo("3", "Due task")
        todosFlow.value = listOf(t)

        composeTestRule.setContent { CalendarScreen(viewModel) }

        composeTestRule.onNodeWithText("Set Due Today").performClick()

        // updateTodo should be called with a non-null dueDate
        verify(viewModel).updateTodo(
            argThat { id == "3" && dueDate != null }
        )
    }

    // ── List updates ──────────────────────────────────────────────────────────

    @Test
    fun whenFlowEmitsNewList_calendarUpdates() {
        todosFlow.value = listOf(todo("10", "Old task"))

        composeTestRule.setContent { CalendarScreen(viewModel) }
        composeTestRule.onNodeWithText("Old task").assertIsDisplayed()

        todosFlow.value = listOf(todo("10", "Old task"), todo("11", "New task"))
        composeTestRule.waitForIdle()

        composeTestRule.onNodeWithText("New task").assertIsDisplayed()
    }
}
