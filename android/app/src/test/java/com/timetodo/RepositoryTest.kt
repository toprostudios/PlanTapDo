// android/app/src/test/java/com/timetodo/RepositoryTest.kt
package com.timetodo

import app.cash.turbine.test
import com.timetodo.api.ApiService
import com.timetodo.db.dao.TodoDao
import com.timetodo.model.TodoEntry
import com.timetodo.repository.TodoRepository
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.mockito.kotlin.*
import retrofit2.Call
import retrofit2.Response

/**
 * Unit tests for [TodoRepository] using Mockito-Kotlin mocks.
 *
 * Every test follows the pattern:
 *  1. Arrange – configure mock [ApiService] and [TodoDao] behaviour.
 *  2. Act     – call the repository method under test.
 *  3. Assert  – verify downstream calls and emitted Flow values.
 */
class RepositoryTest {

    private lateinit var api: ApiService
    private lateinit var dao: TodoDao
    private lateinit var repository: TodoRepository

    // Helper to create a minimal TodoEntry for tests
    private fun todo(id: String = "1", title: String = "Test Todo") = TodoEntry(
        id = id,
        title = title,
        categoryId = null,
        isCompleted = false,
        createdAt = 0L,
        updatedAt = 0L
    )

    @Before
    fun setUp() {
        api = mock()
        dao = mock()
        repository = TodoRepository(api, dao)
    }

    // ── todos Flow ────────────────────────────────────────────────────────────

    @Test
    fun `todos flow emits list from DAO`() = runTest {
        val todoList = listOf(todo("1"), todo("2"))
        whenever(dao.getAll()).thenReturn(flowOf(todoList))

        // Recreate repo so it picks up the stubbed DAO
        val repo = TodoRepository(api, dao)

        repo.todos.test {
            assertEquals(todoList, awaitItem())
            cancelAndIgnoreRemainingEvents()
        }
    }

    // ── refreshTodos ──────────────────────────────────────────────────────────

    @Test
    fun `refreshTodos inserts fetched todos into DAO on success`() = runTest {
        val serverTodos = listOf(todo("10"), todo("11"))
        val call: Call<List<TodoEntry>> = mock()
        whenever(api.getTodos(any())).thenReturn(call)
        whenever(call.execute()).thenReturn(Response.success(serverTodos))

        repository.refreshTodos()

        verify(dao).insert(serverTodos[0])
        verify(dao).insert(serverTodos[1])
    }

    @Test
    fun `refreshTodos does not insert when response is unsuccessful`() = runTest {
        val call: Call<List<TodoEntry>> = mock()
        whenever(api.getTodos(any())).thenReturn(call)
        whenever(call.execute()).thenReturn(Response.error(401, okhttp3.ResponseBody.create(null, "")))

        repository.refreshTodos()

        verify(dao, never()).insert(any())
    }

    @Test
    fun `refreshTodos does not insert when body is null`() = runTest {
        val call: Call<List<TodoEntry>> = mock()
        whenever(api.getTodos(any())).thenReturn(call)
        whenever(call.execute()).thenReturn(Response.success(null))

        repository.refreshTodos()

        verify(dao, never()).insert(any())
    }

    // ── addTodo ───────────────────────────────────────────────────────────────

    @Test
    fun `addTodo inserts server response into DAO on success`() = runTest {
        val newTodo = todo("20", "New")
        val serverTodo = newTodo.copy(updatedAt = 999L)
        val call: Call<TodoEntry> = mock()
        whenever(api.createTodo(newTodo)).thenReturn(call)
        whenever(call.execute()).thenReturn(Response.success(serverTodo))

        repository.addTodo(newTodo)

        verify(dao).insert(serverTodo)
    }

    @Test
    fun `addTodo does not insert when response fails`() = runTest {
        val newTodo = todo("21")
        val call: Call<TodoEntry> = mock()
        whenever(api.createTodo(newTodo)).thenReturn(call)
        whenever(call.execute()).thenReturn(Response.error(500, okhttp3.ResponseBody.create(null, "")))

        repository.addTodo(newTodo)

        verify(dao, never()).insert(any())
    }

    // ── updateTodo ────────────────────────────────────────────────────────────

    @Test
    fun `updateTodo calls DAO update with server response`() = runTest {
        val existing = todo("30")
        val updated = existing.copy(isCompleted = true)
        val call: Call<TodoEntry> = mock()
        whenever(api.updateTodo("30", existing)).thenReturn(call)
        whenever(call.execute()).thenReturn(Response.success(updated))

        repository.updateTodo(existing)

        verify(dao).update(updated)
    }

    // ── deleteTodo ────────────────────────────────────────────────────────────

    @Test
    fun `deleteTodo removes entry from DAO after successful API call`() = runTest {
        val existing = todo("40")
        val deleteCall: Call<Unit> = mock()
        whenever(api.deleteTodo("40")).thenReturn(deleteCall)
        whenever(deleteCall.execute()).thenReturn(Response.success(Unit))
        whenever(dao.getById("40")).thenReturn(flowOf(existing))

        repository.deleteTodo("40")

        verify(dao).delete(existing)
    }

    @Test
    fun `deleteTodo does not call DAO when API call fails`() = runTest {
        val deleteCall: Call<Unit> = mock()
        whenever(api.deleteTodo("41")).thenReturn(deleteCall)
        whenever(deleteCall.execute()).thenReturn(Response.error(404, okhttp3.ResponseBody.create(null, "")))

        repository.deleteTodo("41")

        verify(dao, never()).delete(any())
    }
}
