// android/app/src/main/java/com/timetodo/di/RepositoryModule.kt
package com.timetodo.di

import com.timetodo.repository.TodoRepository
import com.timetodo.api.ApiService
import com.timetodo.db.dao.TodoDao
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object RepositoryModule {
    @Provides
    @Singleton
    fun provideTodoRepository(apiService: ApiService, todoDao: TodoDao): TodoRepository =
        TodoRepository(apiService, todoDao)
}
