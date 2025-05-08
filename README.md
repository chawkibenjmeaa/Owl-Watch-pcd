# 🦉 Owl Watch PCD – AI-Powered Parental Control System

**Owl Watch PCD** is a cross-platform parental control app using **Flutter**, **Django**, **Kotlin**, and **Firebase** to help parents monitor and manage their children's device usage. It features real-time screenshot capture, app usage tracking, password-protected app locking, and AI-powered content analysis.

---

## 🔍 Project Overview

This app allows parents to:

* Set time limits on specific apps.
* Lock access once limits are reached.
* Receive insights into app usage patterns.
* Capture screenshots from the child’s phone every minute.
* Analyze screen content using AI for safety monitoring.

---

## 🚀 Features

* ⏳ App usage time tracking (per-app and daily).
* 🔒 Password-protected app locking after time expiry.
* 🖼️ Automatic screenshot capturing every minute via Kotlin foreground service.
* 🧠 Content analysis using CNN (image classification).
* 📊 Behavioral pattern detection with XGBoost.
* 🔄 Real-time syncing using Firebase.
* 🔐 Firebase Auth for secure parent/child login.

---

## 🧠 AI Models

| Model | Type    | Function                             | Accuracy |
| ----- | ------- | ------------------------------------ | -------- |
| 1     | XGBoost | Detect abnormal app usage patterns   | 88%      |
| 2     | CNN     | Analyze screenshots for safety risks | 93%      |

---

## 🛠 Tech Stack

| Layer         | Technology                         |
| ------------- | ---------------------------------- |
| Frontend      | Flutter                            |
| Backend API   | Django (with Django REST)          |
| Android       | Kotlin (MediaProjection service)   |
| Auth & DB     | Firebase Authentication, Firestore |
| Storage       | Firebase Storage                   |
| ML Frameworks | XGBoost, TensorFlow/Keras          |

---

## 🔥 Firebase Integration

* **Auth**: Parent/Child sign-in and role management.
* **Firestore**: Stores timers, rules, child data, app info.
* **Storage**: Saves captured screenshots securely.
* **Cloud Rules**: Prevent unauthorized access across accounts.

---

## 🧱 Architecture Overview

```
+------------------+     +---------------------------+
|   Parent Panel   |<--->|   Django Backend API      |
+------------------+     +------------+--------------+
                                      |
                     +-------------------------------+
                     |       Firebase Services        |
                     |  - Auth, Firestore, Storage    |
                     +------------+-------------------+
                                  |
             +-------------------v--------------------+
             |         Flutter App (Child)            |
             +-------------------+--------------------+
                                 |
                +-------------------------------+
                |   Kotlin Foreground Service    |
                |  - Screenshot Capturing        |
                |  - App Usage Monitoring        |
                +-------------------------------+
```

---

## ⚙️ Setup Instructions

### 🔧 Django Backend

```bash
cd backend/
python -m venv env
source env/bin/activate
pip install -r requirements.txt
python manage.py migrate
python manage.py runserver
```

### 📱 Flutter App

```bash
cd flutter_app/
flutter pub get
flutter run
```

### 🤖 Android Kotlin Service

* Open in Android Studio.
* Ensure permissions: `FOREGROUND_SERVICE`, `MEDIA_PROJECTION`, `SYSTEM_ALERT_WINDOW`.
* Connect a physical Android device to run.

---

## 🚧 Future Improvements

* Real-time parental alerts for inappropriate content.
* App usage analytics dashboard.
* Voice command integration.
* Geofencing & location awareness.
* Offline mode + periodic sync.

---

## 📄 License

MIT License

