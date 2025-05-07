# test_drive.py
import json
from google.oauth2 import service_account
from googleapiclient.discovery import build

SCOPES = ['https://www.googleapis.com/auth/drive.readonly']
creds = service_account.Credentials.from_service_account_file(
    'drive/credentials.json', scopes=SCOPES
)
service = build('drive', 'v3', credentials=creds)

# try listing one file
resp = service.files().list(pageSize=1, fields='files(id,name)').execute()
print('OK:', resp.get('files'))
