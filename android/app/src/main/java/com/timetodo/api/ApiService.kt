// android/app/src/main/java/com/timetodo/api/ApiService.kt
package com.timetodo.api

import com.timetodo.model.Category
import com.timetodo.model.TodoEntry
import com.timetodo.model.TimeSession
import com.timetodo.model.RepeatRule
import retrofit2.Call
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.PUT
import retrofit2.http.DELETE
import retrofit2.http.Path
import retrofit2.http.Query

/**
 * Retrofit service defining the REST API used by the Android client.
 * Endpoints mirror those of the Django backend (see web implementation).
 */
interface ApiService {
    // Authentication
    @POST("/api/auth/login/")
    fun login(@Body credentials: Map<String, String>): Call<Map<String, String>> // returns {"token": "..."}

    @POST("/api/auth/logout/")
    fun logout(): Call<Unit>

    // Categories
    @GET("/api/categories/")
    fun getCategories(): Call<List<Category>>

    @POST("/api/categories/")
    fun createCategory(@Body category: Category): Call<Category>

    @PUT("/api/categories/{id}/")
    fun updateCategory(@Path("id") id: String, @Body category: Category): Call<Category>

    @DELETE("/api/categories/{id}/")
    fun deleteCategory(@Path("id") id: String): Call<Unit>

    // Todos
    @GET("/api/todos/")
    fun getTodos(@Query("category") categoryId: String? = null): Call<List<TodoEntry>>

    @POST("/api/todos/")
    fun createTodo(@Body todo: TodoEntry): Call<TodoEntry>

    @PUT("/api/todos/{id}/")
    fun updateTodo(@Path("id") id: String, @Body todo: TodoEntry): Call<TodoEntry>

    @DELETE("/api/todos/{id}/")
    fun deleteTodo(@Path("id") id: String): Call<Unit>

    // Time Sessions
    @GET("/api/timesessions/")
    fun getTimeSessions(): Call<List<TimeSession>>

    @POST("/api/timesessions/")
    fun startSession(@Body session: TimeSession): Call<TimeSession>

    @PUT("/api/timesessions/{id}/")
    fun stopSession(@Path("id") id: String, @Body session: TimeSession): Call<TimeSession>

    // Repeat Rules
    @GET("/api/repeatrules/")
    fun getRepeatRules(): Call<List<RepeatRule>>

    @POST("/api/repeatrules/")
    fun createRepeatRule(@Body rule: RepeatRule): Call<RepeatRule>

    @PUT("/api/repeatrules/{id}/")
    fun updateRepeatRule(@Path("id") id: String, @Body rule: RepeatRule): Call<RepeatRule>

    @DELETE("/api/repeatrules/{id}/")
    fun deleteRepeatRule(@Path("id") id: String): Call<Unit>
}
