# **trad**  
*A Dart-based CLI for free translation & localization.*

---
## **How It Works**

The translation tool uses incremental updates by default:
- **First run:** All phrases are translated
- **Subsequent runs:** Only new or changed phrases are translated
- **Manual translations:** Marked translations are preserved and never overwritten
- **Database:** Changes are tracked in `bin/db/phrases.db` (Sembast)
- **Batching:** API calls are batched (100 phrases per request) to optimize performance  

---
## Caveats
- The Azure translator __freemium__ includes 2 million characters per month ([full pricing](https://azure.microsoft.com/en-us/pricing/details/cognitive-services/translator)), 
- The tool relies on this (generous) machine translation API designed to translate __text__, not complex .arb structures so prefer flat text (e.g. better have three entries, _user_, _users_ and _userNone_)

---

## **Quick Start**

1. **Configure Azure Translator:**  
   - Edit `config/secret.txt` and add your **Azure Translator key**.  
   - Region: `westeurope` (hardcoded)


2. **Paste your English ARB file** into:  
   ```text
   bin/input/app_en.arb
   ```

3. **Run translation:**  
   ```bash
   dart run bin/main.dart
   ```
   By default, only new or changed phrases are translated.  
   To force translation of all phrases:  
   ```bash
   dart run bin/main.dart --force
   ```

---

## **Other Commands**

- **Mark manual translations:**  
  Protect specific translations from being overwritten by automatic updates.  
  Use this when you've manually reviewed or corrected a translation and want to preserve it.  
  ```bash
  dart run bin/mark_manual.dart <locale> <phraseKey1> [phraseKey2] ...
  ```
  **Example:**  
  ```bash
  dart run bin/mark_manual.dart fr greeting welcome
  dart run bin/mark_manual.dart es "userProfile" "settingsMenu"
  ```
  
  **Why manual translations matter:**  
  - Automatic translations may not capture context, cultural nuances, or brand voice  
  - After human review/correction, you want to preserve those improvements  
  - Manual translations are skipped during incremental updates, saving API costs  
  - Ensures quality translations aren't accidentally overwritten

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

Since Sembast db is just a JSONL file you can also open it in a text editor.
```text
bin/db/phrases.db
```

