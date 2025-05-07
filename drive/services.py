import os
import io
from django.conf import settings
from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.http import MediaIoBaseDownload
from drive.models import DriveState

# Scope to read drive file metadata and content
SCOPES = ['https://www.googleapis.com/auth/drive.readonly']
SERVICE_ACCOUNT_FILE = os.path.join(settings.BASE_DIR, 'drive', 'credentials.json')


def get_drive_service():
    """
    Build and return the Google Drive v3 service using a service account.
    """
    creds = service_account.Credentials.from_service_account_file(
        SERVICE_ACCOUNT_FILE, scopes=SCOPES
    )
    return build('drive', 'v3', credentials=creds)


def _get_state(key):
    return DriveState.objects.get_or_create(key=key, defaults={'value': ''})[0]


def get_start_page_token(service):
    """
    Retrieve or initialize the startPageToken for listing changes.
    """
    state = _get_state('start_page_token')
    if not state.value:
        resp = service.changes().getStartPageToken().execute()
        state.value = resp.get('startPageToken')
        state.save()
    return state.value


def save_page_token(token):
    """
    Update the saved token after processing changes.
    """
    state = _get_state('start_page_token')
    state.value = token
    state.save()


def list_drive_changes(service, page_token):
    """
    List changes since the given pageToken.
    Returns (changes, next_page_token, new_start_page_token).
    """
    resp = service.changes().list(
        pageToken=page_token,
        spaces='drive',
        fields='newStartPageToken,nextPageToken,changes(fileId, file(name, mimeType, parents))'
    ).execute()
    return (
        resp.get('changes', []),
        resp.get('nextPageToken'),
        resp.get('newStartPageToken')
    )


def download_file(service, file_id):
    """
    Download a file's binary content into BytesIO and return it.
    """
    fh = io.BytesIO()
    request = service.files().get_media(fileId=file_id)
    downloader = MediaIoBaseDownload(fh, request)
    done = False
    while not done:
        status, done = downloader.next_chunk()
    fh.seek(0)
    return fh