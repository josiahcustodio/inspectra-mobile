# Clowtec Inspector App

A high-performance, offline-first Flutter mobile application tailored for City Health Office inspectors to streamline their field operations, inspections, and data collection.

## 📱 Features & Capabilities

- **Offline-First Architecture**
  - Uses `Hive` for robust local data storage, allowing inspectors to seamlessly work in areas with poor or no internet connectivity.
  - Synchronizes inspection templates, establishment data, and pending submissions (offline queue) automatically or manually with `Supabase` when an internet connection is available.

- **Establishment Management**
  - Search and view a database of registered establishments.
  - Add new establishments dynamically, with automatically updated "Type of Establishment" categories fetched directly from the Supabase backend.
  - Track basic setup data, employee count, health certificates, and sanitary permit control numbers.

- **Smart Inspection Forms**
  - Dynamic rendering of checklists based on the specific category of the establishment (e.g., Public Places, Food, Supermarket).
  - Categorized checklist sections and easy pass/fail judgments.
  - Real-time scoring and calculation engine that outputs immediate ratings (e.g., "Excellent").

- **Robust Evidence Collection**
  - Take Photo Evidence natively inside the application via `image_picker`.
  - Inspector and Owner digital signature capture for instant verification using `signature`.
  - Securely uploads files to cloud storage upon synchronization.

- **QR Code Scanning Integration**
  - Fast establishment lookup through the built-in QR Code scanner leveraging `mobile_scanner`.

- **Modern & Professional UI/UX**
  - A Sage Green inspired professional design system.
  - Bento-layout dashboard providing quick glances at pending inspections, synced items, and recent activity.
  - Easy-to-use search and primary action placement.

## 🛠️ Technology Stack

- **Framework**: `Flutter` (uses Material Design).
- **Backend Services**: `Supabase` (Database, Auth, Storage, Edge Functions).
- **Environment Management**: `flutter_dotenv` for handling secure credentials and `.env` configurations.
- **State Management**: `provider` (used for Rating calculations and forms).
- **Local Database**: `hive` and `hive_flutter` for blistering fast offline key-value storage.
- **Utilities**: `mobile_scanner`, `image_picker`, `signature`, `path_provider`.

## 📁 Project Structure

- `lib/core/` - Application configurations, themes (AppTheme), and constants.
- `lib/data/models/` - Data models such as `Establishment`, `ChecklistTemplate`, and `InspectionLog`.
- `lib/data/services/` - Data layers representing APIs (`sync_service.dart`) and offline caching (`offline_service.dart`).
- `lib/providers/` - Logic for changing state across the widget tree (e.g., `rating_provider.dart`).
- `lib/ui/screens/` - Main GUI boundaries (Home, Establishment, Form, Scanner, History, Splash, etc.).
- `lib/ui/widgets/` - Reusable UI components (e.g., SignaturePad).

## 🚀 Getting Started

1. **Clone the repository.**
2. **Setup your environment variables:** 
   Copy the contents of `.env.example` into a new `.env` file at the root of the project and populate it with your actual Supabase URL and Anon Key.
3. **Get packages:**
   ```bash
   flutter pub get
   ```
4. **Run the app:**
   ```bash
   flutter run
   ```

## 🔐 Security Context & Best Practices

- Requires a valid `.env` file for remote connections via Supabase. Ensure `.env` is fully populated.
- Offline data storage handles unencrypted sensitive form info. Ensure physical device securities are updated depending on field protocols.
- Role-Level Security (RLS) policies govern data insertion on the backend.
