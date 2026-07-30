// android/app/src/test/java/com/timetodo/ApiServiceTest.kt
package com.timetodo

import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import com.squareup.okhttp3.mockwebserver.MockResponse
import com.squareup.okhttp3.mockwebserver.MockWebServer
import com.timetodo.api.ApiService
import com.timetodo.model.TodoEntry
import okhttp3.OkHttpClient
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import retrofit2.Retrofit
import retrofit2.converter.moshi.MoshiConverterFactory

/**
 * Unit tests for [ApiService] using [MockWebServer].
 * Each test enqueues a canned JSON response, calls the corresponding endpoint,
 * and asserts that (a) the correct HTTP verb + path was used, and (b) the
 * response body was correctly deserialised.
 */
class ApiServiceTest {

    private lateinit var server: MockWebServer
    private lateinit var api: ApiService

    private val moshi: Moshi = Moshi.Builder()
        .addLast(KotlinJsonAdapterFactory())
        .build()

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()

        api = Retrofit.Builder()
            .baseUrl(server.url("/"))
            .client(OkHttpClient())
            .addConverterFactory(MoshiConverterFactory.create(moshi))
            .build()
            .create(ApiService::class.java)
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    // ── Auth ────────────────────────────────────────────────────────────────

    @Test
    fun `login sends POST to correct path`() {
        server.enqueue(MockResponse().setBody("""{"token":"abc123"}""").setResponseCode(200))

        val response = api.login(mapOf("username" to "user", "password" to "pass")).execute()

        val request = server.takeRequest()
        assertEquals("POST", request.method)
        assertEquals("/api/auth/login/", request.path)
        assertTrue(response.isSuccessful)
        assertEquals("abc123", response.body()?.get("token"))
    }

    @Test
    fun `logout sends POST to correct path`() {
        server.enqueue(MockResponse().setResponseCode(204))

        api.logout().execute()

        val request = server.takeRequest()
        assertEquals("POST", request.method)
        assertEquals("/api/auth/logout/", request.path)
    }

    // ── Todos ────────────────────────────────────────────────────────────────

    @Test
    fun `getTodos sends GET and returns list`() {
        val body = """[{"id":"1","title":"Write tests","categoryId":null,"isCompleted":false,"createdAt":0,"updatedAt":0,"timerSeconds":0}]"""
        server.enqueue(MockResponse().setBody(body).setResponseCode(200))

        val response = api.getTodos().execute()

        val request = server.takeRequest()
        assertEquals("GET", request.method)
        assertTrue(request.path!!.startsWith("/api/todos/"))
        assertTrue(response.isSuccessful)
        assertEquals(1, response.body()?.size)
        assertEquals("Write tests", response.body()?.first()?.title)
    }

    @Test
    fun `createTodo sends POST with body`() {
        val todo = TodoEntry(
            id = "2", title = "New Todo", categoryId = null,
            isCompleted = false, createdAt = 0L, updatedAt = 0L
        )
        val respBody = """{"id":"2","title":"New Todo","categoryId":null,"isCompleted":false,"createdAt":0,"updatedAt":0,"timerSeconds":0}"""
        server.enqueue(MockResponse().setBody(respBody).setResponseCode(201))

        val response = api.createTodo(todo).execute()

        val request = server.takeRequest()
        assertEquals("POST", request.method)
        assertEquals("/api/todos/", request.path)
        assertTrue(response.isSuccessful)
        assertEquals("New Todo", response.body()?.title)
    }

    @Test
    fun `updateTodo sends PUT with id in path`() {
        val todo = TodoEntry(
            id = "3", title = "Updated", categoryId = null,
            isCompleted = true, createdAt = 0L, updatedAt = 1L
        )
        val respBody = """{"id":"3","title":"Updated","categoryId":null,"isCompleted":true,"createdAt":0,"updatedAt":1,"timerSeconds":0}"""
        server.enqueue(MockResponse().setBody(respBody).setResponseCode(200))

        val response = api.updateTodo("3", todo).execute()

        val request = server.takeRequest()
        assertEquals("PUT", request.method)
        assertEquals("/api/todos/3/", request.path)
        assertTrue(response.body()?.isCompleted == true)
    }

    @Test
    fun `deleteTodo sends DELETE with id in path`() {
        server.enqueue(MockResponse().setResponseCode(204))

        api.deleteTodo("4").execute()

        val request = server.takeRequest()
        assertEquals("DELETE", request.method)
        assertEquals("/api/todos/4/", request.path)
    }

    // ── Error handling ────────────────────────────────────────────────────────

    @Test
    fun `getTodos returns unsuccessful response on 500`() {
        server.enqueue(MockResponse().setResponseCode(500))

        val response = api.getTodos().execute()

        assertFalse(response.isSuccessful)
        assertEquals(500, response.code())
    }
}
