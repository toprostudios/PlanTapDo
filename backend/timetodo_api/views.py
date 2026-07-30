from rest_framework import viewsets, permissions
from .models import Category, TodoEntry, TimeSession, RepeatRule
from .serializers import (
    CategorySerializer,
    TodoEntrySerializer,
    TimeSessionSerializer,
    RepeatRuleSerializer,
)

# All viewsets require authenticated access
class BaseAuthenticatedViewSet(viewsets.ModelViewSet):
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        # Restrict to objects owned by the requesting user
        return self.queryset.filter(owner=self.request.user)

    def perform_create(self, serializer):
        # Automatically set the owner on creation
        serializer.save(owner=self.request.user)


class CategoryViewSet(BaseAuthenticatedViewSet):
    queryset = Category.objects.all()
    serializer_class = CategorySerializer


class TodoEntryViewSet(BaseAuthenticatedViewSet):
    queryset = TodoEntry.objects.all()
    serializer_class = TodoEntrySerializer


class TimeSessionViewSet(BaseAuthenticatedViewSet):
    queryset = TimeSession.objects.all()
    serializer_class = TimeSessionSerializer


class RepeatRuleViewSet(BaseAuthenticatedViewSet):
    queryset = RepeatRule.objects.all()
    serializer_class = RepeatRuleSerializer
