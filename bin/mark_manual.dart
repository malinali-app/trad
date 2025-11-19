// Dart imports:
import 'dart:io';

// Project imports:
import 'phrase_store.dart';

/// Mark specific translations as manual to prevent them from being overwritten
/// Usage: dart run bin/mark_manual.dart <locale> <phraseKey1> [phraseKey2] [...]
void main(List<String> arguments) async {
  if (arguments.length < 2) {
    print('Usage: dart run bin/mark_manual.dart <locale> <phraseKey1> [phraseKey2] ...');
    print('');
    print('Example:');
    print('  dart run bin/mark_manual.dart fr greeting welcome');
    print('');
    print('This marks translations as "manual" so they won\'t be overwritten by updates.');
    exit(1);
  }

  final locale = arguments[0];
  final phraseKeys = arguments.sublist(1);

  print('Marking ${phraseKeys.length} translation(s) as manual for locale: $locale');
  print('');

  final phraseStore = PhraseStore();
  
  try {
    final markedCount = <String>[];
    final notFoundCount = <String>[];

    for (final phraseKey in phraseKeys) {
      // Check if translation exists
      final existing = await phraseStore.getTranslation(phraseKey, locale);
      
      if (existing == null) {
        print('  ⚠ Translation not found: $phraseKey');
        notFoundCount.add(phraseKey);
        continue;
      }

      // Update translation to mark as manual
      final manualTranslation = StoredTranslation(
        phraseKey: phraseKey,
        locale: locale,
        value: existing.value,
        translatedBy: 'manual',
        lastUpdated: DateTime.now(),
      );

      await phraseStore.saveTranslation(manualTranslation);
      print('  ✓ Marked as manual: $phraseKey');
      markedCount.add(phraseKey);
    }

    print('');
    print('Summary:');
    print('  ✓ Marked as manual: ${markedCount.length}');
    if (notFoundCount.isNotEmpty) {
      print('  ⚠ Not found: ${notFoundCount.length}');
    }
    print('');
    print('These translations will not be overwritten by update_translations.dart');
    
  } finally {
    await phraseStore.close();
  }
}

