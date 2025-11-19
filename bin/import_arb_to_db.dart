// Dart imports:
import 'dart:convert';
import 'dart:io';

// Project imports:
import 'phrase_store.dart';

/// Import existing ARB translations into the database
/// Usage: dart run bin/import_arb_to_db.dart
void main() async {
  final phraseStore = PhraseStore();
  
  try {
    print('Importing existing ARB translations to database...\n');
    
    final outputDir = Directory('bin/output');
    if (!outputDir.existsSync()) {
      print('❌ Error: bin/output directory not found!');
      print('   No existing translations to import.');
      exit(1);
    }

    // Find all ARB files
    final arbFiles = outputDir
        .listSync()
        .where((file) => file.path.endsWith('.arb'))
        .map((file) => file as File)
        .toList();

    if (arbFiles.isEmpty) {
      print('❌ No ARB files found in bin/output/');
      exit(1);
    }

    print('Found ${arbFiles.length} ARB files to import\n');

    var totalImported = 0;
    var filesProcessed = 0;

    for (final arbFile in arbFiles) {
      // Extract locale from filename: app_fr.arb -> fr
      final filename = arbFile.path.split(Platform.pathSeparator).last;
      final locale = filename.replaceAll('app_', '').replaceAll('.arb', '');
      
      // Skip error files
      if (filename.contains('error')) {
        print('  ⊘ Skipping: $filename (error file)');
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

        // Convert to StoredTranslation objects
        final translationsToSave = translations.map((entry) {
          return StoredTranslation(
            phraseKey: entry.key,
            locale: locale,
            value: entry.value.toString(),
            translatedBy: 'azure', // Mark as azure (existing translations)
            lastUpdated: DateTime.now(),
          );
        }).toList();

        // Save to database in batch
        await phraseStore.saveTranslations(translationsToSave);

        print('  ✓ Imported $locale: ${translations.length} translations');
        totalImported += translations.length;
        filesProcessed++;

      } catch (e) {
        print('  ✗ Error importing $locale: $e');
      }
    }

    print('');
    print('Summary:');
    print('  ✓ Files processed: $filesProcessed');
    print('  ✓ Total translations imported: $totalImported');
    print('');
    print('All existing translations are now in the database!');
    print('You can now use update_translations.dart for incremental updates.');
    
  } finally {
    await phraseStore.close();
  }
}

