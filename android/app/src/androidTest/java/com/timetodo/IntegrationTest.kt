// android/app/src/androidTest/java/com/timetodo/IntegrationTest.kt
package com.timetodo

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.timetodo.model.TodoEntry
import dagger.hilt.android.testing.HiltAndroidRule
import dagger.hilt.android.testing.HiltAndroidTest
import dagger.hilt.android.testing.UninstallModules
import com.timetodo.di.NetworkModule
import com.timetodo.di.DatabaseModule
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import javax.inject.Inject

/**
 * End-to-end instrumentation tests that boot the real [MainActivity] with Hilt,
 * exercise the full UI stack, and verify integration between UI ↔ ViewModel ↔
 * Repository layers.
 *
 * Network calls are **not** stubbed here – tests assume a locally running backend
 * (or a test flavour that injects a MockWebServer via a TestNetworkModule).
 * If you have no running backend, annotate tests with @Ignore and rely on
 * [ApiServiceTest] and [RepositoryTest] for network-layer coverage.
 *
 * Structure:
 *  1. Login flow
 *  2. Todo CRUD
 *  3. Timer start / stop
 *  4. WebSocket-triggered refresh (simulated)
 */
@HiltAndroidTest
@RunWith(AndroidJUnit4::class)
class IntegrationTest {

    @get:Rule(order = 0)
    val hiltRule = HiltAndroidRule(this)

    @get:Rule(order = 1)
    val composeTestRule = createAndroidComposeRule<MainActivity>()

    @Before
    fun inject() {
        hiltRule.inject()
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    /** Performs the login flow via the UI. */
    private fun login(username: String = "testuser", password: String = "testpass") {
        composeTestRule.onNodeWithTag("username_field").performTextInput(username)
        composeTestRule.onNodeWithTag("password_field").performTextInput(password)
        composeTestRule.onNodeWithTag("login_button").performClick()
        composeTestRule.waitForIdle()
    }

    // ── 1. Login ──────────────────────────────────────────────────────────────

    @Test
    fun loginFlow_successNavigatesToTodoList() {
        login()

        // After successful login the todo list screen should appear
        composeTestRule.onNodeWithTag("todo_list_screen").assertIsDisplayed()
    }

    @Test
    fun loginFlow_wrongCredentials_showsErrorMessage() {
        login(username = "bad_user", password = "wrong_pass")

        composeTestRule.onNodeWithTag("login_error_message").assertIsDisplayed()
    }

    // ── 2. Todo CRUD ──────────────────────────────────────────────────────────

    @Test
    fun createTodo_appearsInList() {
        login()

        // Open new-todo dialog via FAB
        composeTestRule.onNodeWithTag("fab_new_todo").performClick()
        composeTestRule.onNodeWithTag("new_todo_title_field").performTextInput("Integration test todo")
        composeTestRule.onNodeWithTag("new_todo_save_button").performClick()
        composeTestRule.waitForIdle()

        composeTestRule.onNodeWithText("Integration test todo").assertIsDisplayed()
    }

    @Test
    fun toggleCompleteTodo_updatesCheckmark() {
        login()

        // Assumes at least one todo exists after login (seeded by refreshTodos)
        composeTestRule.onAllNodesWithTag("toggle_complete_checkbox").onFirst().performClick()
        composeTestRule.waitForIdle()

        composeTestRule.onAllNodesWithTag("completed_indicator").onFirst().assertIsDisplayed()
    }

    @Test
    fun deleteTodo_removesItFromList() {
        login()

        // Get text of first todo for later assertion
        val titleNode = composeTestRule.onAllNodesWithTag("todo_title").onFirst()
        val titleText = titleNode.fetchSemanticsNode().config
            .getOrNull(SemanticsProperties.Text)?.firstOrNull()?.text ?: return

        // Delete first todo
        composeTestRule.onAllNodesWithTag("delete_todo_button").onFirst().performClick()
        composeTestRule.waitForIdle()

        composeTestRule.onNodeWithText(titleText).assertDoesNotExist()
    }

    // ── 3. Timer ──────────────────────────────────────────────────────────────

    @Test
    fun startTimer_changesButtonToStop() {
        login()

        composeTestRule.onAllNodesWithTag("timer_toggle_button").onFirst().performClick()
        composeTestRule.waitForIdle()

        // After starting, the button label should change to "Stop"
        composeTestRule.onAllNodesWithText("Stop").onFirst().assertIsDisplayed()
    }

    @Test
    fun stopTimer_changesButtonBackToStart() {
        login()

        // Start then stop
        composeTestRule.onAllNodesWithTag("timer_toggle_button").onFirst().performClick()
        composeTestRule.waitForIdle()
        composeTestRule.onAllNodesWithText("Stop").onFirst().performClick()
        composeTestRule.waitForIdle()

        composeTestRule.onAllNodesWithText("Start").onFirst().assertIsDisplayed()
    }

    // ── 4. Navigation ─────────────────────────────────────────────────────────

    @Test
    fun bottomNav_calendarTab_showsCalendarScreen() {
        login()

        composeTestRule.onNodeWithTag("nav_calendar").performClick()
        composeTestRule.waitForIdle()

        composeTestRule.onNodeWithTag("calendar_screen").assertIsDisplayed()
    }

    @Test
    fun bottomNav_analyticsTab_showsAnalyticsScreen() {
        login()

        composeTestRule.onNodeWithTag("nav_analytics").performClick()
        composeTestRule.waitForIdle()

        composeTestRule.onNodeWithTag("analytics_screen").assertIsDisplayed()
    }
}
