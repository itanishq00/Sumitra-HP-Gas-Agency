# Sumitra HP Gas Agency

Sumitra HP Gas Agency Management Application built with Flutter and Firebase.

A comprehensive mobile and desktop solution tailored for LPG gas agencies to streamline daily operations, cylinder inventory, delivery logistics, customer requests, staff coordination, and security management.

---

## Features

### 1. Authentication & Multi-Layered Security
- **Firebase Authentication**: Email and phone-based authentication.
- **PIN Security Gate**: Custom 4-digit security PIN (`PinGate`, `PinStorage`) for app-level access protection.
- **Biometric Authentication**: Fast and secure unlock via fingerprint and Face ID using `local_auth`.
- **Encrypted Local Storage**: Hardware-backed credential and preference storage via `flutter_secure_storage`.
- **Security Profile Management**: Toggle biometric login, change PIN, and manage agency credentials.

### 2. Executive Dashboard
- Real-time stock counts for domestic and commercial LPG cylinders.
- Overview of pending deliveries, ongoing issues, and active delivery staff.
- Quick navigation shortcuts to core operational modules.

### 3. Cylinder & Product Inventory Management
- **LPG Cylinders**: Real-time tracking of 14.2 kg (Domestic), 19 kg (Commercial), 5 kg, and 47.5 kg cylinders.
- **Stock Tracking**: Live count of filled cylinders, empty cylinders, and cylinders out for delivery.
- **Gas Appliances & Accessories**: Inventory management for gas stoves, pressure regulators, and safety pipes.
- **Stock Adjustments**: Log manual increments, decrements, and inventory corrections directly to Cloud Firestore.

### 4. Inventory Activity & Audit Trail
- Automated logging of every inventory adjustment (`inventoryActivity` collection).
- Tracks action type, affected item, change differential, timestamp, and actor details.
- Filterable activity history log for administrative auditing.

### 5. Upcoming Stock & Inbound Shipments
- Track scheduled bulk cylinder arrivals and tanker dispatches.
- Automated arrival prompt on scheduled delivery dates to confirm received quantities.
- Detailed arrival history and variance logs.

### 6. Customer & Consumer Management
- Consumer directory with search by consumer number, customer name, and contact info.
- Tracking of cylinder connection type (domestic vs. commercial) and delivery history.
- Quick actions to register bookings and record cylinder exchanges.

### 7. Staff & Delivery Fleet Coordination
- Delivery personnel directory with contact details, operational status, and assigned vehicles.
- Real-time tracking of cylinders issued to delivery boys vs. empty cylinders returned.

### 8. Issue Reporting & Complaint Management
- Centralized complaint registry for gas leakages, delivery delays, regulator defects, and billing queries.
- Priority categorization (Critical, High, Medium, Low) and status workflows (Pending, In Progress, Resolved).
- Quick emergency action shortcuts for gas leakage reports.

### 9. Firebase Cloud Functions Backend
- Node.js Cloud Functions (`functions/index.js`) providing secure owner authentication and custom token generation.

---

## Tech Stack

| Component | Technology |
|---|---|
| **Framework** | Flutter (Dart SDK ^3.13.2) |
| **Design System** | Material 3 with custom brand theming |
| **Authentication** | Firebase Auth & Custom Owner Verification |
| **Database** | Cloud Firestore |
| **Secure Storage** | Flutter Secure Storage |
| **Biometrics** | Local Auth |
| **Backend** | Firebase Cloud Functions (Node.js) |
| **Platforms Supported** | Android, iOS, macOS, Windows, Linux, Web |

---

## Getting Started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (version 3.13.2 or later)
- Android Studio / Xcode (for mobile development)
- Git

### Installation

1. **Clone the repository**:
   ```bash
   git clone https://github.com/itanishq00/Sumitra-HP-Gas-Agency.git
   cd Sumitra-HP-Gas-Agency
   ```

2. **Install Flutter dependencies**:
   ```bash
   flutter pub get
   ```

3. **Install Cloud Functions dependencies** (optional, for backend development):
   ```bash
   cd functions
   npm install
   cd ..
   ```

4. **Verify static analysis & tests**:
   ```bash
   flutter analyze
   flutter test
   ```

---

## Running the Application

### Development Mode

Run on connected device or simulator:
```bash
flutter run
```

Run on a specific platform:
```bash
flutter run -d chrome     # Web
flutter run -d macos      # macOS desktop
flutter run -d android    # Android device/emulator
flutter run -d ios        # iOS simulator
```

---

## Building for Production

### Android (APK / App Bundle)
```bash
# Build release APK
flutter build apk --release

# Build release App Bundle (Google Play Store)
flutter build appbundle --release
```
The output APK will be located at `build/app/outputs/flutter-apk/app-release.apk`.

### iOS
```bash
flutter build ios --release
```

---

## Configuration & Security Notes

- **Firebase Configuration**: Client configuration files (`google-services.json`, `GoogleService-Info.plist`, and `lib/firebase_options.dart`) connect the app to the Firebase project.
- **Sensitive Credentials**: Private keystores (`*.jks`, `*.keystore`), signing keys, service account secrets, and environment variable files (`*.env`) are strictly excluded from version control via `.gitignore`.
- **Backend Admin Privileges**: The Cloud Function in `functions/` manages administrative claims securely without exposing backend credentials in the client application.

---

## License

This project is proprietary and confidential to **Sumitra HP Gas Agency**. All rights reserved.
