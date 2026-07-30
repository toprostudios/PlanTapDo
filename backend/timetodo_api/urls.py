from django.urls import path, include
from rest_framework import routers
from rest_framework_simplejwt.views import (
    TokenObtainPairView,
    TokenRefreshView,
    TokenVerifyView,
)
from .views import (
    CategoryViewSet,
    TodoEntryViewSet,
    TimeSessionViewSet,
    RepeatRuleViewSet,
)

router = routers.DefaultRouter()
router.register(r'categories', CategoryViewSet, basename='category')
router.register(r'todos', TodoEntryViewSet, basename='todo')
router.register(r'sessions', TimeSessionViewSet, basename='session')
router.register(r'repeat-rules', RepeatRuleViewSet, basename='repeat-rule')

urlpatterns = [
    path('api/', include(router.urls)),
    path('api/auth/token/', TokenObtainPairView.as_view(), name='token_obtain_pair'),
    path('api/auth/token/refresh/', TokenRefreshView.as_view(), name='token_refresh'),
    path('api/auth/token/verify/', TokenVerifyView.as_view(), name='token_verify'),
]
