import numpy as np
import joblib
from PIL import Image
import tensorflow as tf
import re
import pandas as pd
import os
from django.conf import settings
import __main__
from .ml_utils.text_cleaner import TextCleaner
__main__.TextCleaner = TextCleaner




# ==================== LOAD AI MODELS ====================

# Load nudity detection model (.keras)
nudity_model_path = os.path.join(settings.BASE_DIR, 'AImodels/models/model_finetuned.keras')
nudity_model = tf.keras.models.load_model(nudity_model_path)
nudity_class_labels = ['NORMAL IMAGE', 'SUGGESTIVE', 'PORN']

# Load influencer detection model (.pkl)
influencer_model_path = os.path.join(settings.BASE_DIR, 'AImodels/models/influencer_classifier_model.pkl')
model_data = joblib.load(influencer_model_path)

influencer_vectorizer = model_data["vectorizer"]
influencer_model = model_data["model"]
label_encoder = model_data["label_encoder"]
text_cleaner = TextCleaner()

# ==================== UTILITY FUNCTIONS ====================

def preprocess_for_nudity_model(image):
    """
    Resize and normalize image for the nudity model.
    """
    img = image.resize((224, 224))
    img = np.array(img) / 255.0
    return np.expand_dims(img, axis=0)

def process_image_with_text_and_ai(image_stream):
    """
    Perform nudity detection on image and influencer detection on optional text.
    """
    try:
        # === Nudity Detection ===
        img = Image.open(image_stream).convert("RGB")
        nudity_input = preprocess_for_nudity_model(img)
        nudity_prediction = nudity_model.predict(nudity_input)[0]
        nudity_class_index = np.argmax(nudity_prediction)
        nudity_class = nudity_class_labels[nudity_class_index]
        nudity_confidence = float(nudity_prediction[nudity_class_index])
        is_inappropriate = nudity_class in ['SUGGESTIVE', 'PORN']
    except Exception as e:
        print(f"Error during nudity detection: {e}")
        nudity_class = "ERROR"
        nudity_confidence = 0.0
        is_inappropriate = False
    input_text="Mrbean"

    # === Influencer Detection ===
    influencer_detected = False
    if input_text:
        try:
            cleaned_text = text_cleaner.transform([input_text])
            vect_text = influencer_vectorizer.transform(cleaned_text)
            pred = influencer_model.predict(vect_text)[0]
            label = label_encoder.inverse_transform([pred])[0]
            influencer_detected = (label.lower() == 'unsuitable')
        except Exception as e:
            print(f"Error during influencer detection: {e}")
            influencer_detected = False

    return {
        'nudity_detected': is_inappropriate,
        'nudity_class': nudity_class,
        'nudity_confidence': nudity_confidence,
        'influencer_detected': influencer_detected
    }
