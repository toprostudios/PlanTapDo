// android/app/src/main/java/com/timetodo/di/ViewModelModule.kt
package com.timetodo.di

import com.timetodo.viewmodel.AuthViewModel
import com.timetodo.viewmodel.TodoViewModel
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import dagger.hilt.android.lifecycle.HiltViewModelFactory
import javax.inject.Singleton

/**
 * Hilt module that binds ViewModels. With @HiltViewModel annotations, explicit bindings are
 * optional, but this module demonstrates how to provide any custom ViewModel factories if needed.
 */
@Module
@InstallIn(SingletonComponent::class)
object ViewModelModule {
    // No explicit providers needed; Hilt can construct ViewModels via @Inject constructors.
    // Placeholder for future custom factories.
}
