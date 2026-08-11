from django.urls import path, include
from rest_framework import routers
from .views import (
    CategoryViewSet,
    TodoEntryViewSet,
    TimeSessionViewSet,
    RepeatRuleViewSet,
    LocationTravelTimeViewSet,
    RegisterView,
    LogoutView,
    ThrottledTokenObtainPairView,
    ThrottledTokenRefreshView,
    ThrottledTokenVerifyView,
    UserProfileView,
    SyncView,
    health_live,
    health_ready,
)

router = routers.DefaultRouter()
router.register(r'categories', CategoryViewSet, basename='category')
router.register(r'todos', TodoEntryViewSet, basename='todo')
router.register(r'sessions', TimeSessionViewSet, basename='session')
router.register(r'travel-times', LocationTravelTimeViewSet, basename='travel-time')
router.register(r'repeat-rules', RepeatRuleViewSet, basename='repeat-rule')

urlpatterns = [
    path('health/live/', health_live, name='health_live'),
    path('health/ready/', health_ready, name='health_ready'),
    path('api/', include(router.urls)),
    path('api/auth/register/', RegisterView.as_view(), name='auth_register'),
    path('api/auth/me/', UserProfileView.as_view(), name='auth_me'),
    path('api/auth/logout/', LogoutView.as_view(), name='auth_logout'),
    path('api/auth/token/', ThrottledTokenObtainPairView.as_view(), name='token_obtain_pair'),
    path('api/auth/token/refresh/', ThrottledTokenRefreshView.as_view(), name='token_refresh'),
    path('api/auth/token/verify/', ThrottledTokenVerifyView.as_view(), name='token_verify'),
    path('api/sync/', SyncView.as_view(), name='sync_state'),
]
