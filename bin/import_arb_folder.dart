// Dart imports:
import 'dart:convert';
import 'dart:io';

// Project imports:
import 'phrase_store.dart';

/// Import a folder containing multiple .arb files into sembast
/// Preserves manual translations and follows the model for tracking translations
/// 
/// Usage: dart run bin/import_arb_folder.dart [folder_path] [source_locale]
/// Example: dart run bin/import_arb_folder.dart bin/output en
void main(List<String> arguments) async {
  final phraseStore = PhraseStore();
  
  try {
    // Parse arguments
    final folderPath = arguments.isNotEmpty ? arguments[0] : 'bin/output';
    final sourceLocale = arguments.length > 1 ? arguments[1] : 'en';
    
    print('Importing ARB files from folder: $folderPath');
    print('Source locale (for phrases): $sourceLocale\n');
    
    final folder = Directory(folderPath);
    if (!folder.existsSync()) {
      print('❌ Error: Folder "$folderPath" does not exist!');
      exit(1);
    }

    // Find all ARB files
    final arbFiles = folder
        .listSync()
        .where((file) => file.path.endsWith('.arb'))
        .map((file) => file as File)
        .toList();

    if (arbFiles.isEmpty) {
      print('❌ No ARB files found in "$folderPath"');
      exit(1);
    }

    print('Found ${arbFiles.length} ARB files to import\n');

    var totalPhrasesImported = 0;
    var totalTranslationsImported = 0;
    var manualTranslationsPreserved = 0;
    var filesProcessed = 0;

    // First pass: Import source phrases from source locale
    print('Step 1: Importing source phrases from $sourceLocale...');
    final sourceArbFile = arbFiles.firstWhere(
      (file) {
        final filename = file.path.split(Platform.pathSeparator).last;
        final locale = filename.replaceAll('app_', '').replaceAll('.arb', '');
        return locale == sourceLocale;
      },
      orElse: () => arbFiles.first, // Fallback to first file if source not found
    );
    
    final sourceFilename = sourceArbFile.path.split(Platform.pathSeparator).last;
    final sourceLocaleFromFile = sourceFilename.replaceAll('app_', '').replaceAll('.arb', '');
    
    if (sourceLocaleFromFile != sourceLocale) {
      print('  ⚠ Warning: Source locale file not found, using $sourceLocaleFromFile instead');
    }
    
    try {
      final contents = await sourceArbFile.readAsString();
      final Map<String, dynamic> arbData = json.decode(contents);

      // Filter out ARB metadata (keys starting with @)
      final phrases = arbData.entries
          .where((entry) => !entry.key.startsWith('@'))
          .toList();

      // Convert to StoredPhrase objects
      final phrasesToSave = phrases.map((entry) {
        return StoredPhrase(
          key: entry.key,
          value: entry.value.toString(),
          lastUpdated: DateTime.now(),
        );
      }).toList();

      // Save source phrases
      await phraseStore.savePhrases(phrasesToSave);
      totalPhrasesImported = phrasesToSave.length;
      print('  ✓ Imported $totalPhrasesImported source phrases from $sourceLocaleFromFile\n');
    } catch (e) {
      print('  ✗ Error importing source phrases: $e');
    }

    // Second pass: Import translations from all ARB files
    print('Step 2: Importing translations from all locales...');
    
    for (final arbFile in arbFiles) {
      // Extract locale from filename: app_fr.arb -> fr
      final filename = arbFile.path.split(Platform.pathSeparator).last;
      final locale = filename.replaceAll('app_', '').replaceAll('.arb', '');
      
      // Skip error files
      if (filename.contains('error')) {
        print('  ⊘ Skipping: $filename (error file)');
        continue;
      }

      // Skip source locale (already processed)
      if (locale == sourceLocale) {
        print('  ⊘ Skipping: $locale (source locale, already imported as phrases)');
        continue;
      }

      try {
        // Read ARB file
        final contents = await arbFile.readAsString();
        final Map<String, dynamic> arbData = json.decode(contents);

        // Filter out ARB metadata (keys starting with @)
        final translations = arbData.entries
            .where((entry) => !entry.key.startsWith('@'))
            .toList();

        if (translations.isEmpty) {
          print('  ⚠ Skipping: $locale (empty file)');
          continue;
        }

        // Convert to StoredTranslation objects, preserving manual translations
        final translationsToSave = <StoredTranslation>[];
        var skippedManual = 0;

        for (final entry in translations) {
          final phraseKey = entry.key;
          final value = entry.value.toString();
          
          // Check if this translation is already manual
          final isManual = await phraseStore.isManualTranslation(phraseKey, locale);
          
          if (isManual) {
            // Preserve manual translation - don't overwrite
            skippedManual++;
            continue;
          }
          
          // Import as azure translation (or update existing)
          translationsToSave.add(StoredTranslation(
            phraseKey: phraseKey,
            locale: locale,
            value: value,
            translatedBy: 'azure', // Mark as azure translation
            lastUpdated: DateTime.now(),
          ));
        }

        // Save translations to database in batch
        if (translationsToSave.isNotEmpty) {
          await phraseStore.saveTranslations(translationsToSave);
        }

        print('  ✓ Imported $locale: ${translationsToSave.length} translations');
        if (skippedManual > 0) {
          print('     (preserved $skippedManual manual translations)');
          manualTranslationsPreserved += skippedManual;
        }
        
        totalTranslationsImported += translationsToSave.length;
        filesProcessed++;

      } catch (e) {
        print('  ✗ Error importing $locale: $e');
      }
    }

    print('');
    print('Summary:');
    print('  ✓ Source phrases imported: $totalPhrasesImported');
    print('  ✓ Files processed: $filesProcessed');
    print('  ✓ Total translations imported: $totalTranslationsImported');
    print('  ✓ Manual translations preserved: $manualTranslationsPreserved');
    print('');
    print('All translations are now in the database!');
    print('Manual translations have been preserved and not overwritten.');
    
  } catch (e) {
    print('❌ Fatal error: $e');
    exit(1);
  } finally {
    await phraseStore.close();
  }
}

