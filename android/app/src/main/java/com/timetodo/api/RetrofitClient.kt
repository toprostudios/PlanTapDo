// android/app/src/main/java/com/timetodo/api/RetrofitClient.kt
package com.timetodo.api

import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.Response
import retrofit2.Retrofit
import retrofit2.converter.moshi.MoshiConverterFactory
import java.util.concurrent.TimeUnit

/**
 * Provides a singleton Retrofit instance configured with JWT authentication interceptor.
 * The interceptor reads the token from SharedPreferences (which is set by AuthViewModel).
 */
object RetrofitClient {
    private const val BASE_URL = "https://your-api.example.com/" // replace with actual backend URL
    private const val TIMEOUT_SECONDS = 30L

    private var retrofit: Retrofit? = null

    fun getInstance(tokenProvider: () -> String?): Retrofit {
        if (retrofit == null) {
            val client = OkHttpClient.Builder()
                .addInterceptor(AuthInterceptor(tokenProvider))
                .connectTimeout(TIMEOUT_SECONDS, TimeUnit.SECONDS)
                .readTimeout(TIMEOUT_SECONDS, TimeUnit.SECONDS)
                .build()

            retrofit = Retrofit.Builder()
                .baseUrl(BASE_URL)
                .client(client)
                .addConverterFactory(MoshiConverterFactory.create())
                .build()
        }
        return retrofit!!
    }
}

private class AuthInterceptor(private val tokenProvider: () -> String?) : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val original = chain.request()
        val token = tokenProvider()
        val requestBuilder = original.newBuilder()
        token?.let {
            requestBuilder.addHeader("Authorization", "Bearer $it")
        }
        return chain.proceed(requestBuilder.build())
    }
}
