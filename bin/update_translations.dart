// Dart imports:
import 'dart:convert';
import 'dart:io';

// Project imports:
import 'locales.dart';
import 'models.dart';
import 'phrase_store.dart';
import 'translate.dart';

/// Incremental translation - only translates new or changed phrases
void main(List<String> arguments) async {
  print('Starting incremental translation...\n');
  final forceTranslation = arguments.contains('--force');
  final outputDir = await Directory('bin/output').create();
  final phraseStore = PhraseStore();
  
  try {
    await updateTranslations(outputDir, phraseStore, forceTranslation: forceTranslation);
  } finally {
    await phraseStore.close();
  }
  
  print('\nIncremental translation complete!');
}

Map<String, String> get phrasesMap {
  final contents = File('bin/input/phrases.json').readAsStringSync();
  final jsonPhrases = json.decode(contents);

  final map = <String, String>{};

  for (final phrase in jsonPhrases) {
    final miniMap = Map<String, String>.from(phrase);
    map[miniMap.keys.first] = miniMap.values.first;
  }
  return map;
}

Future<File> makeFileAndWriteAsStringAsync(
    String content, String folder, String fileName) async {
  final file = File('$folder/$fileName');
  final fileWritten = await file.writeAsString(content);
  return fileWritten;
}

/// Detect changes and translate only what's needed
Future<void> updateTranslations(
  Directory outputDir,
  PhraseStore phraseStore,
  {bool forceTranslation = false}
) async {
  final currentPhrases = phrasesMap;
List<MapEntry<String, String>> phrasesToTranslate = [];

 if (forceTranslation) {
  // Get phrases that need translation (new or changed)
   phrasesToTranslate = currentPhrases.entries.toList();
 } else {
   phrasesToTranslate = 
      await phraseStore.getPhrasesNeedingTranslation(currentPhrases);
  
  if (phrasesToTranslate.isEmpty) {
    print('✓ No changes detected. All phrases are up to date!');
    return;
  }
  
  print('Found ${phrasesToTranslate.length} phrases that need translation:');
  for (final entry in phrasesToTranslate) {
    print('  - ${entry.key}');
  }
 }
  print('');
  
  // Update the phrase store with new/changed phrases
  final updatedPhrases = phrasesToTranslate.map((e) => StoredPhrase(
    key: e.key,
    value: e.value,
    lastUpdated: DateTime.now(),
  )).toList();
  
  await phraseStore.savePhrases(updatedPhrases);
  print('✓ Updated phrase store\n');
  
  // Now translate only the changed phrases for all languages
  final files = <File>[];
  for (final locale in localesSupportedAzureTranslatorMinusFlutterUnsupported) {
    final file = await translateDeltaForLocale(
      locale,
      currentPhrases,
      phrasesToTranslate,
      outputDir,
      phraseStore,
    );
    files.add(file);
  }
  
  print('\n✓ Translated ${phrasesToTranslate.length} phrases for ${files.length} languages');
}

/// Retry translation with exponential backoff for rate limiting
/// Azure can take up to 15s for large batches, so we use conservative delays
Future<List<String>> _translateWithRetry(
  String fromLocale,
  String toLocale,
  List<String> phrases, {
  int maxRetries = 3,
}) async {
  int attempt = 0;
  // Start with 10s to allow Azure rate limit windows to reset
  Duration delay = const Duration(seconds: 10);
  
  while (attempt < maxRetries) {
    try {
      return await Translate.translateWithAzure(fromLocale, toLocale, phrases);
    } on RateLimitException {
      attempt++;
      if (attempt >= maxRetries) {
        print('  ⚠ Max retries ($maxRetries) reached for rate limit');
        rethrow;
      }
      
      // Exponential backoff: 10s, 20s, 40s
      // Conservative delays to respect Azure rate limits
      final waitTime = delay * (1 << (attempt - 1));
      print('  ⏳ Rate limited. Waiting ${waitTime.inSeconds}s before retry $attempt/$maxRetries...');
      await Future.delayed(waitTime);
    }
  }
  
  // Should never reach here, but return empty list as fallback
  return [];
}

/// Translate only changed phrases for a specific locale and merge with existing
Future<File> translateDeltaForLocale(
  String locale,
  Map<String, String> allPhrases,
  List<MapEntry<String, String>> phrasesToTranslate,
  Directory outputDir,
  PhraseStore phraseStore,
) async {
  print('Translating for $locale (${phrasesToTranslate.length} phrases)...');
  
  // Load existing translations from DB
  final existingTranslations = await phraseStore.getTranslationsForLocale(locale);
  final translationsMap = <String, String>{};
  
  // Populate with existing translations
  for (final entry in existingTranslations.entries) {
    translationsMap[entry.key] = entry.value.value;
  }
  
  // Filter phrases to translate: skip manual translations
  final phrasesNeedingTranslation = <MapEntry<String, String>>[];
  final skippedManual = <String>[];
  
  for (final entry in phrasesToTranslate) {
    final isManual = await phraseStore.isManualTranslation(entry.key, locale);
    if (isManual) {
      skippedManual.add(entry.key);
      // Keep existing manual translation
      continue;
    }
    phrasesNeedingTranslation.add(entry);
  }
  
  if (skippedManual.isNotEmpty) {
    print('  ⚠ Skipped ${skippedManual.length} manual translations');
  }
  
  if (phrasesNeedingTranslation.isEmpty) {
    print('  ✓ No new phrases to translate');
    // Still write ARB file with existing translations
  } else {
    // Translate in batches of 100
    final keysError = <String>[];
    const batchSize = 100;
    // 3 seconds between batches - Azure can take up to 15s per batch of 100 phrases
    const delayBetweenBatches = Duration(seconds: 3);
    
    for (int i = 0; i < phrasesNeedingTranslation.length; i += batchSize) {
      final end = (i + batchSize < phrasesNeedingTranslation.length) 
          ? i + batchSize 
          : phrasesNeedingTranslation.length;
      final batch = phrasesNeedingTranslation.sublist(i, end);
      final batchNumber = i ~/ batchSize + 1;
      
      // Extract phrases to translate
      final phrasesInBatch = batch.map((e) => e.value).toList();
      
      // Call Azure API with batch and retry logic for rate limiting
      List<String>? translations;
      try {
        translations = await _translateWithRetry(
          'en',
          locale,
          phrasesInBatch,
          maxRetries: 3,
        );
      } on RateLimitException {
        print('  ✗ Rate limit exceeded on batch $batchNumber after retries');
        keysError.addAll(batch.map((e) => e.key));
        continue;
      } catch (e) {
        print('  ✗ Unexpected error on batch $batchNumber: $e');
        keysError.addAll(batch.map((e) => e.key));
        continue;
      }
      
      // Check if translation failed
      if (translations.isEmpty || translations.length != phrasesInBatch.length) {
        print('  ✗ Error on batch $batchNumber');
        keysError.addAll(batch.map((e) => e.key));
      } else {
        // Save translations to database and map
        final translationsToSave = <StoredTranslation>[];
        for (int j = 0; j < batch.length; j++) {
          final phraseKey = batch[j].key;
          final translatedValue = translations[j];
          
          translationsMap[phraseKey] = translatedValue;
          
          translationsToSave.add(StoredTranslation(
            phraseKey: phraseKey,
            locale: locale,
            value: translatedValue,
            translatedBy: 'azure',
            lastUpdated: DateTime.now(),
          ));
        }
        
        // Save to database
        await phraseStore.saveTranslations(translationsToSave);
      }
      
      // Space out requests to avoid rate limiting
      if (i + batchSize < phrasesNeedingTranslation.length) {
        await Future.delayed(delayBetweenBatches);
      }
    }
    
    if (keysError.isNotEmpty) {
      print('  ✗ Failed: ${keysError.length} errors');
      final normalizedLocale = normalizeLocaleForArbFilename(locale);
      return await makeFileAndWriteAsStringAsync(
          keysError.toString(), outputDir.path, 'app_errors_$normalizedLocale.txt');
    }
  }
  
  // Create final ARB with all translations from database
  final finalArb = Arb(locale, translationsMap);
  
  // Normalize locale for filename (remove script identifiers)
  final normalizedLocale = normalizeLocaleForArbFilename(locale);
  final file = await makeFileAndWriteAsStringAsync(
      json.encode(finalArb.map), outputDir.path, 'app_$normalizedLocale.arb');
  if (!file.existsSync()) {
    throw 'error saving file';
  }
  print('  ✓ Done');
  return file;
}

