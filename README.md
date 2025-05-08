Got it! Here's the updated and ready-to-paste `README.md` for your **Owl-Watch-pcd** project, now correctly reflecting:

* **Two models**:

  * **Model 1**: XGBoost (accuracy: 88%)
  * **Model 2**: CNN (accuracy: 93%)
* Uses **Django** for backend
* Uses **Flutter** for UI
* Uses **Kotlin** for Android services
* Integrates **Firebase** (Firestore + Auth + Storage)
* No screenshots included
* Structure inspired by [DDoS-Detection-With-AI](https://github.com/tahangz/DDoS-Detection-With-AI)

---

```markdown
# 🦉 Owl Watch PCD — Intelligent Parental Control & Monitoring System

**Owl Watch PCD** is a smart cross-platform parental control system combining real-time app monitoring, screen surveillance, and AI-based behavior detection. Built with Flutter, Django, and Kotlin, it empowers parents to supervise and control their children's mobile activity safely and efficiently.

## 📌 Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Tech Stack](#tech-stack)
- [Architecture](#architecture)
- [ML Models](#ml-models)
- [Firebase Integration](#firebase-integration)
- [Installation](#installation)
- [Usage](#usage)
- [Future Enhancements](#future-enhancements)
- [License](#license)

---

## 🧠 Overview

**Owl Watch** enables intelligent monitoring of children's mobile devices through a hybrid system that tracks app usage, locks apps after time limits, and captures screen activity for analysis. It uses **XGBoost** and **CNN** models to detect inappropriate or excessive usage patterns. All data and rules are stored and synchronized using **Firebase**.

---

## ✨ Features

- ⏲️ App usage limits with real-time countdowns  
- 🔐 Password-protected app blocking when time is exceeded  
- 🖼️ Automatic periodic screenshot capture (Kotlin + MediaProjection)  
- 📊 AI-based content classification using XGBoost and CNN  
- 🧑‍🤝‍🧑 Parent-child account linking  
- ⚙️ Admin configuration of daily time quotas and blocked apps  
- ☁️ Real-time sync with Firebase Firestore and Storage  

---

## 🛠 Tech Stack

| Layer         | Technology                            |
|---------------|----------------------------------------|
| Mobile UI     | Flutter                                |
| Android Logic | Kotlin (Foreground Service)            |
| Backend       | Django + Django REST Framework         |
| ML Models     | XGBoost (usage model), CNN (image model) |
| Database      | Firebase Firestore                     |
| Auth          | Firebase Authentication                |
| Storage       | Firebase Storage (screenshots)         |

---

## 🏗️ Architecture

```

+-----------------+       +--------------------------+
\|   Parent Panel  | <---> |   Django REST Backend    |
\| (Admin/Settings)|       |  - User/Auth Management  |
+-----------------+       |  - Time/App Config APIs  |
+-----------+--------------+
|
+------------v------------+
\|    Firebase (Cloud DB)  |
\|  - Firestore (Rules/Logs)|
\|  - Auth (Users)          |
\|  - Storage (Screenshots) |
+------------+-------------+
|
+---------------v----------------+
\|      Flutter Child App         |
\|  - Usage UI + App Control      |
\|  - Password/Lock Screens       |
+---------------+----------------+
|
+-----------v-----------+
\|  Kotlin Foreground App |
\|  - Screenshot Capture  |
\|  - Usage Monitoring    |
+------------------------+

````

---

## 🧠 ML Models

### 1. XGBoost Model
- **Goal**: Classify app usage patterns as normal or risky
- **Accuracy**: 88%
- **Inputs**: App name, session length, time of day, frequency
- **Use case**: Lightweight real-time predictions on-device

### 2. CNN Model
- **Goal**: Analyze screenshots for visual indicators of inappropriate content
- **Accuracy**: 93%
- **Inputs**: Screenshots (grayscale or RGB)
- **Use case**: Post-capture analysis using Firebase Cloud Function or backend script

---

## 🔥 Firebase Integration

- **Firestore**: Stores app time limits, usage history, and user configs  
- **Authentication**: Parent and child sign-in with email/password or Google  
- **Storage**: Uploads screenshots every minute from the Kotlin service  
- **Security Rules**: Separate access roles for parents and children

---

## ⚙️ Installation

### 1. Clone the Repository
```bash
git clone https://github.com/chawkibenjmeaa/Owl-Watch-pcd.git
cd Owl-Watch-pcd
````

### 2. Backend Setup (Django)

```bash
cd backend
python3 -m venv env
source env/bin/activate
pip install -r requirements.txt
python manage.py migrate
python manage.py runserver
```

### 3. Flutter App

```bash
cd flutter_app
flutter pub get
flutter run
```

### 4. Android Kotlin Service

* Open `/android_app` in Android Studio
* Grant permissions for `SYSTEM_ALERT_WINDOW`, `FOREGROUND_SERVICE`, and `MEDIA_PROJECTION`
* Build and run the service on a child’s device

---

## ▶️ Usage

* Parent logs in via the web or app to configure time limits and monitored apps
* Child uses the phone as usual; usage is tracked live
* After exceeding limits, the app is locked
* Screenshots are taken every minute and uploaded
* The CNN model analyzes screenshots and flags them if needed

---

## 🚀 Future Enhancements

* Add live alerting to parent devices
* Implement GPS-based geofencing
* Integrate voice recognition for audio context
* Build reporting dashboard with daily usage trends

---

## 📄 License

This project is licensed under the **MIT License**.
