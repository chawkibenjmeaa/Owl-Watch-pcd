from django.urls import path
from .views import analyze_image

urlpatterns = [
    path('analyze/<str:file_id>/', analyze_image, name='analyze_image'),
]
