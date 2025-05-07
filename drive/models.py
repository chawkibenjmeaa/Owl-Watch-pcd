from django.db import models

class DriveState(models.Model):
    """
    Simple key/value store to save the last Drive change token.
    """
    key = models.CharField(max_length=100, unique=True)
    value = models.TextField()

    def __str__(self):
        return f"{self.key}: {self.value}"