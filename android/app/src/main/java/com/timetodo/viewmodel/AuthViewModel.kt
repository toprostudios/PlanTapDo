// android/app/src/main/java/com/timetodo/viewmodel/AuthViewModel.kt
package com.timetodo.viewmodel

import android.app.Application
import android.content.Context
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.timetodo.api.ApiService
import com.timetodo.model.TodoEntry
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKeys

/**
 * Handles user authentication: login, token persistence, and logout.
 * Token is stored securely using EncryptedSharedPreferences.
 */
@HiltViewModel
class AuthViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
    private val apiService: ApiService
) : AndroidViewModel(context as Application) {
    private val _isLoggedIn = MutableStateFlow(false)
    val isLoggedIn: StateFlow<Boolean> = _isLoggedIn

    private val _loginError = MutableStateFlow<String?>(null)
    val loginError: StateFlow<String?> = _loginError

    private val sharedPrefs by lazy {
        val masterKeyAlias = MasterKeys.getOrCreate(MasterKeys.AES256_GCM_SPEC)
        EncryptedSharedPreferences.create(
            "auth_prefs",
            masterKeyAlias,
            context,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    }

    fun login(username: String, password: String) {
        viewModelScope.launch {
            try {
                val response = apiService.login(mapOf("username" to username, "password" to password)).execute()
                if (response.isSuccessful) {
                    val token = response.body()?.get("token") as? String
                    token?.let {
                        sharedPrefs.edit().putString("jwt_token", it).apply()
                        _isLoggedIn.value = true
                        _loginError.value = null
                    } ?: run {
                        _loginError.value = "Invalid token received"
                    }
                } else {
                    _loginError.value = "Login failed: ${response.code()}"
                }
            } catch (e: Exception) {
                _loginError.value = e.message
            }
        }
    }

    fun logout() {
        viewModelScope.launch {
            apiService.logout().execute()
            sharedPrefs.edit().remove("jwt_token").apply()
            _isLoggedIn.value = false
        }
    }

    fun getToken(): String? = sharedPrefs.getString("jwt_token", null)
}
