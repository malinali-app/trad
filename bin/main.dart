// Dart imports:
import 'dart:convert';
import 'dart:io';

// Project imports:
import 'locales.dart';
import 'models.dart';
import 'translate.dart';

void main(List<String> arguments) async {
  final outputDir = await Directory('bin/output').create();
  await createTranslations(outputDir);
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

Future<Directory> createDirectory(String folderPath) async {
  final dir = await Directory(folderPath).create();
  if (dir.path.isEmpty) {
    throw "invalid output directory path";
  }
  return dir;
}

/// Retry translation with exponential backoff for rate limiting
/// Azure can take up to 15s for large batches, so we use conservative delays
Future<List<String>> translateWithRetry(
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
    } catch (e) {
      // Check if it's a rate limit error (429)
      if (e.toString().contains('429') || e.toString().contains('Rate limit')) {
        attempt++;
        if (attempt >= maxRetries) {
          print('  Max retries ($maxRetries) reached for rate limit');
          rethrow;
        }
        
        // Exponential backoff: 10s, 20s, 40s
        // Conservative delays to respect Azure rate limits
        final waitTime = delay * (1 << (attempt - 1));
        print('  Rate limited. Waiting ${waitTime.inSeconds}s before retry $attempt/$maxRetries...');
        await Future.delayed(waitTime);
      } else {
        // Not a rate limit error, rethrow immediately
        rethrow;
      }
    }
  }
  
  // Should never reach here, but return empty list as fallback
  return [];
}

Future<File> requestTranslations(String locale, Directory outputDir) async {
  final arb = Arb(locale, phrasesMap);
  final phrases = phrasesMap;
  final keysError = <String>[];
  print('begin translate  $locale');
  
  // Batch phrases into chunks of 100
  final entries = phrases.entries.toList();
  const batchSize = 100;
  // 3 seconds between batches - Azure can take up to 15s per batch of 100 phrases
  const delayBetweenBatches = Duration(seconds: 3);
  
  for (int i = 0; i < entries.length; i += batchSize) {
    final end = (i + batchSize < entries.length) ? i + batchSize : entries.length;
    final batch = entries.sublist(i, end);
    final batchNumber = i ~/ batchSize + 1;
    
    print('Translating batch $batchNumber (${batch.length} phrases)');
    
    // Extract phrases to translate
    final phrasesToTranslate = batch.map((e) => e.value).toList();
    
    // Call Azure API with batch and retry logic for rate limiting
    List<String>? translations;
    try {
      translations = await translateWithRetry('en', locale, phrasesToTranslate);
    } catch (e) {
      print('error on batch $batchNumber: $e');
      keysError.addAll(batch.map((e) => e.key));
      continue;
    }
    
    // Check if translation failed
    if (translations.isEmpty || translations.length != phrasesToTranslate.length) {
      print('error on batch $batchNumber');
      keysError.addAll(batch.map((e) => e.key));
    } else {
      // Map translations back to their keys
      for (int j = 0; j < batch.length; j++) {
        arb.map[batch[j].key] = translations[j];
      }
    }
    
    // Space out requests to avoid rate limiting
    if (i + batchSize < entries.length) {
      await Future.delayed(delayBetweenBatches);
    }
  }
  
  if (keysError.isNotEmpty) {
    return await makeFileAndWriteAsStringAsync(
        keysError.toString(), outputDir.path, 'app_errors_${normalizeLocaleForArbFilename(locale)}.txt');
  } else {
    final normalizedLocale = normalizeLocaleForArbFilename(locale);
    final file = await makeFileAndWriteAsStringAsync(
        json.encode(arb.map), outputDir.path, 'app_$normalizedLocale.arb');
    if (file.existsSync() == false) {
      throw 'error saving file';
    }
    print('finished translating $locale');
    return file;
  }
}

Future<List<File>> createTranslations(Directory directory) async {
  final files = <File>[];
  // instead use locales
  for (final locale in localesSupportedAzureTranslatorMinusFlutterUnsupported) {
    final file = await requestTranslations(locale, directory);
    files.add(file);
  }
  return files;
}
