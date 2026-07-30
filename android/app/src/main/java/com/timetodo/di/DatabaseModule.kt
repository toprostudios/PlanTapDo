// android/app/src/main/java/com/timetodo/di/DatabaseModule.kt
package com.timetodo.di

import android.content.Context
import androidx.room.Room
import com.timetodo.db.AppDatabase
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object DatabaseModule {
    private const val DB_NAME = "timetodo.db"

    @Provides
    @Singleton
    fun provideAppDatabase(@ApplicationContext context: Context): AppDatabase =
        Room.databaseBuilder(context, AppDatabase::class.java, DB_NAME)
            .fallbackToDestructiveMigration()
            .build()

    @Provides
    @Singleton
    fun provideCategoryDao(db: AppDatabase) = db.categoryDao()

    @Provides
    @Singleton
    fun provideTodoDao(db: AppDatabase) = db.todoDao()

    @Provides
    @Singleton
    fun provideTimeSessionDao(db: AppDatabase) = db.timeSessionDao()
}
