# **dartrad**  
*A Dart-based CLI for translation & localization.*

---

## **Quick Start**

1. **Paste your English ARB file** into:  
   ```text
   bin/input/app_en.arb
   ```

2. **Generate phrases JSON:**  
   ```bash
   dart run bin/arb_to_json.dart
   ```

3. **Configure Azure Translator:**  
   - Edit `config` and add your **Azure Translator key**.

4. **Run full translation:**  
   ```bash
   dart run bin/main.dart
   ```
   Or incremental update:  
   ```bash
   dart run bin/update_translations.dart
   ```

5. **Force translations:**  
   ```bash
   dart run bin/update_translations.dart --force
   ```

---

## **Other Commands**

- **Mark manual translations:**  
  ```bash
  dart run bin/mark_manual.dart
  ```

- **Import existing ARB files:**  
  ```bash
  dart run bin/import_arb_to_db.dart
  dart run bin/import_arb_folder.dart [folder_path] [source_locale]
  # Example:
  dart run bin/import_arb_folder.dart bin/output fr
  ```

- **Export ARB from DB:**  
  ```bash
  dart run bin/export_arb_from_db.dart
  ```

---

## **View Data in Sembast**

You may use: https://github.com/weebi-com/sembast_gui

The database is just a JSON file. Open it in any text editor:  
```text
bin/db/phrases.db
```

---

## **Scripts Overview**

### **1. `main.dart` – Full Translation (First Run)**  
**Use when:** Initial setup or full translation.  
**What it does:**  
- Translates **all phrases** in `bin/input/phrases.json`.  
- Batches API calls (100 phrases/request).  
- Generates ARB files for all supported locales.  
- Outputs to `bin/output/`.  

**Run:**  
```bash
dart run bin/main.dart
```

---

### **2. `update_translations.dart` – Incremental Translation**  
**Use when:** Frequent changes to ARB files.  
**What it does:**  
- Detects **new or changed phrases**.  
- Translates only the delta (faster & cheaper).  
- Merges updates into existing ARB files.  
- Persists history in `bin/db/phrases.db` (Sembast).  

**Run:**  
```bash
dart run bin/update_translations.dart
```

**First incremental run:**  
- All phrases will be translated.  
- Subsequent runs only translate changes.  

---

## **How Incremental Translation Works**
1. Load current phrases from `bin/input/phrases.json`.  
2. Load stored phrases from Sembast DB.  
3. Compare values:  
   ```dart
   if (stored[key].value != currentValue) {
     // Needs translation!
   }
   ```
4. Translate only the delta (100 phrases per batch).  
5. Merge with existing ARB files.  
6. Update DB with new values & timestamps.  

---

## **Workflow Example**
**Initial setup:**  
```bash
dart run bin/main.dart
```

**Daily workflow:**  
```bash
# 1. Edit bin/input/phrases.json
# 2. Run incremental update
dart run bin/update_translations.dart
# Only changed phrases will be translated! ✨
```

---

## **Persistence**
- **Database:** `bin/db/phrases.db` (Sembast - pure Dart NoSQL).  
- **Structure:**  
   ```json
   {
     "phraseKey": {
       "value": "English text",
       "lastUpdated": "2025-11-16T10:30:00Z"
     }
   }
   ```

---

## **API Configuration**
Both scripts use Azure Translator settings from `bin/translate.dart`:  
- Add your API key to `Ocp-Apim-Subscription-Key` header.  
- Region: `westeurope`.  
- Batch size: 100 phrases per request.  
