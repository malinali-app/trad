// Dart imports:
import 'dart:convert';
import 'dart:io';

// Project imports:
import 'locales.dart';
import 'phrase_store.dart';

/// Export translations from sembast to .arb files
/// 
/// Usage: dart run bin/export_arb_from_db.dart [output_folder]
/// Example: dart run bin/export_arb_from_db.dart bin/output
void main(List<String> arguments) async {
  final phraseStore = PhraseStore();
  
  try {
    // Parse arguments
    final outputFolder = arguments.isNotEmpty ? arguments[0] : 'bin/output';
    
    print('Exporting translations from database to ARB files...');
    print('Output folder: $outputFolder\n');
    
    // Create output directory if it doesn't exist
    final outputDir = Directory(outputFolder);
    await outputDir.create(recursive: true);

    // Get all locales to export
    // Use the locales from locales.dart that are supported
    final localesToExport = localesSupportedAzureTranslatorMinusFlutterUnsupported;
    
    print('Exporting ${localesToExport.length} locales...\n');

    var totalFilesExported = 0;
    var totalTranslationsExported = 0;

    for (final locale in localesToExport) {
      try {
        // Get all translations for this locale from database
        final translations = await phraseStore.getTranslationsForLocale(locale);
        
        if (translations.isEmpty) {
          print('  ⊘ Skipping: $locale (no translations in database)');
          continue;
        }

        // Convert to ARB format (Map<String, String>)
        final arbMap = <String, String>{};
        for (final entry in translations.entries) {
          arbMap[entry.key] = entry.value.value;
        }

        // Write to ARB file
        // Normalize locale for filename (remove script identifiers)
        final normalizedLocale = normalizeLocaleForArbFilename(locale);
        final filename = 'app_$normalizedLocale.arb';
        final file = File('${outputDir.path}/$filename');
        
        // Convert to JSON with proper formatting
        const encoder = JsonEncoder.withIndent('  ');
        final jsonContent = encoder.convert(arbMap);
        
        await file.writeAsString(jsonContent);

        print('  ✓ Exported $locale: ${arbMap.length} translations -> $filename');
        totalTranslationsExported += arbMap.length;
        totalFilesExported++;

      } catch (e) {
        print('  ✗ Error exporting $locale: $e');
      }
    }

    print('');
    print('Summary:');
    print('  ✓ Files exported: $totalFilesExported');
    print('  ✓ Total translations exported: $totalTranslationsExported');
    print('');
    print('All translations have been exported to ARB files!');
    print('Output location: $outputFolder');
    
  } catch (e) {
    print('❌ Fatal error: $e');
    exit(1);
  } finally {
    await phraseStore.close();
  }
}

