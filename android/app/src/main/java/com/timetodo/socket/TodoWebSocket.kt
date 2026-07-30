// android/app/src/main/java/com/timetodo/socket/TodoWebSocket.kt
package com.timetodo.socket

import android.util.Log
import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import com.timetodo.model.TodoEntry
import okhttp3.*
import okio.ByteString
import java.util.concurrent.TimeUnit

/**
 * Simple WebSocket wrapper that connects to the backend WebSocket endpoint.
 * It parses incoming JSON messages and forwards them to a registered handler.
 * The message format follows the web client: { "type": "refresh" } or other events.
 */
class TodoWebSocket(
    private val url: String,
    private val tokenProvider: () -> String?
) {
    private var webSocket: WebSocket? = null
    private var reconnectAttempts = 0
    private var messageHandler: ((String) -> Unit)? = null

    private val client: OkHttpClient = OkHttpClient.Builder()
        .pingInterval(30, TimeUnit.SECONDS)
        .build()

    private val moshi = Moshi.Builder()
        .add(KotlinJsonAdapterFactory())
        .build()

    fun setMessageHandler(handler: (String) -> Unit) {
        messageHandler = handler
    }

    fun connect() {
        val requestBuilder = Request.Builder()
            .url(url)
        tokenProvider()?.let { token ->
            requestBuilder.addHeader("Authorization", "Bearer $token")
        }
        val request = requestBuilder.build()
        webSocket = client.newWebSocket(request, socketListener)
    }

    fun disconnect() {
        webSocket?.close(1000, "Normal closure")
        webSocket = null
    }

    fun send(message: String) {
        webSocket?.send(message)
    }

    private val socketListener = object : WebSocketListener() {
        override fun onOpen(webSocket: WebSocket, response: Response) {
            Log.d("TodoWebSocket", "Connected")
            reconnectAttempts = 0
        }

        override fun onMessage(webSocket: WebSocket, text: String) {
            Log.d("TodoWebSocket", "Message received: $text")
            messageHandler?.invoke(text)
        }

        override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
            onMessage(webSocket, bytes.utf8())
        }

        override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
            Log.d("TodoWebSocket", "Closing: $code / $reason")
            webSocket.close(1000, null)
        }

        override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
            Log.d("TodoWebSocket", "Closed: $code / $reason")
        }

        override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
            Log.e("TodoWebSocket", "Failure: ${t.message}")
            // Simple exponential back‑off reconnection
            if (reconnectAttempts < 5) {
                val delay = (2.0.pow(reconnectAttempts.toDouble()) * 1000L).toLong()
                Log.d("TodoWebSocket", "Reconnecting in $delay ms")
                android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                    reconnectAttempts++
                    connect()
                }, delay)
            }
        }
    }
}
