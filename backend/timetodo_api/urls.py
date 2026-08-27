from django.urls import path, include
from rest_framework import routers
from .views import (
    CategoryViewSet,
    TodoEntryViewSet,
    TimeSessionViewSet,
    RepeatRuleViewSet,
    LocationTravelTimeViewSet,
    RegisterView,
    EmailVerificationRequestView,
    EmailVerificationConfirmView,
    PasswordResetRequestView,
    PasswordResetConfirmView,
    LogoutView,
    LogoutRetryView,
    SessionListView,
    SessionDetailView,
    RevokeAllSessionsView,
    AccountDeletionView,
    MFASetupView,
    MFAConfirmView,
    MFADisableView,
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
    path('api/auth/email/verify/request/', EmailVerificationRequestView.as_view(), name='auth_email_verify_request'),
    path('api/auth/email/verify/confirm/', EmailVerificationConfirmView.as_view(), name='auth_email_verify_confirm'),
    path('api/auth/password/reset/request/', PasswordResetRequestView.as_view(), name='auth_password_reset_request'),
    path('api/auth/password/reset/confirm/', PasswordResetConfirmView.as_view(), name='auth_password_reset_confirm'),
    path('api/auth/me/', UserProfileView.as_view(), name='auth_me'),
    path('api/auth/logout/', LogoutView.as_view(), name='auth_logout'),
    path('api/auth/logout/retry/', LogoutRetryView.as_view(), name='auth_logout_retry'),
    path('api/auth/account/', AccountDeletionView.as_view(), name='auth_account_delete'),
    path('api/auth/sessions/', SessionListView.as_view(), name='auth_session_list'),
    path('api/auth/sessions/revoke-all/', RevokeAllSessionsView.as_view(), name='auth_session_revoke_all'),
    path('api/auth/sessions/<uuid:pk>/', SessionDetailView.as_view(), name='auth_session_detail'),
    path('api/auth/mfa/setup/', MFASetupView.as_view(), name='auth_mfa_setup'),
    path('api/auth/mfa/confirm/', MFAConfirmView.as_view(), name='auth_mfa_confirm'),
    path('api/auth/mfa/disable/', MFADisableView.as_view(), name='auth_mfa_disable'),
    path('api/auth/token/', ThrottledTokenObtainPairView.as_view(), name='token_obtain_pair'),
    path('api/auth/token/refresh/', ThrottledTokenRefreshView.as_view(), name='token_refresh'),
    path('api/auth/token/verify/', ThrottledTokenVerifyView.as_view(), name='token_verify'),
    path('api/sync/', SyncView.as_view(), name='sync_state'),
]
