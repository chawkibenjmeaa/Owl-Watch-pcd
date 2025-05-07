import firebase_admin
from firebase_admin import credentials, firestore
from django.shortcuts import render
# Initialize Firebase app (only once)
cred = credentials.Certificate(r"C:\Users\zaidc\Desktop\pcdenv\pcdproject\firebase\projet-pcd-5c35a-firebase-adminsdk-fbsvc-3064a8874b.json")
firebase_admin.initialize_app(cred)

# Connect to Firestore
db = firestore.client()

def index(request):
    # Example: Fetch all documents from "parents" collection
    parents_ref = db.collection('parents')
    docs = parents_ref.stream()

    parents_data = [doc.to_dict() for doc in docs]

    return render(request, 'index.html', {'parents': parents_data})
