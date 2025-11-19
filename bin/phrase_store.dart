// Dart imports:
import 'dart:io';

// Package imports:
import 'package:path/path.dart';
import 'package:sembast/sembast_io.dart';

/// Represents a stored phrase with metadata
class StoredPhrase {
  final String key;
  final String value;
  final DateTime lastUpdated;

  const StoredPhrase({
    required this.key,
    required this.value,
    required this.lastUpdated,
  });

  Map<String, dynamic> toMap() {
    return {
      'key': key,
      'value': value,
      'lastUpdated': lastUpdated.toIso8601String(),
    };
  }

  factory StoredPhrase.fromMap(String key, Map<String, dynamic> map) {
    return StoredPhrase(
      key: key,
      value: map['value'] as String,
      lastUpdated: DateTime.parse(map['lastUpdated'] as String),
    );
  }
}

/// Represents a stored translation with metadata
class StoredTranslation {
  final String phraseKey;
  final String locale;
  final String value;
  final String translatedBy; // "azure" or "manual"
  final DateTime lastUpdated;

  const StoredTranslation({
    required this.phraseKey,
    required this.locale,
    required this.value,
    required this.translatedBy,
    required this.lastUpdated,
  });

  Map<String, dynamic> toMap() {
    return {
      'value': value,
      'translatedBy': translatedBy,
      'lastUpdated': lastUpdated.toIso8601String(),
    };
  }

  factory StoredTranslation.fromMap(String phraseKey, String locale, Map<String, dynamic> map) {
    return StoredTranslation(
      phraseKey: phraseKey,
      locale: locale,
      value: map['value'] as String,
      translatedBy: map['translatedBy'] as String,
      lastUpdated: DateTime.parse(map['lastUpdated'] as String),
    );
  }
}

/// Service to persist and retrieve phrase data using Sembast
class PhraseStore {
  static const String dbName = 'phrases.db';
  static const String sourcePhraseStoreName = 'source_phrases';

  Database? _database;
  final _sourcePhraseStore = StoreRef<String, Map<String, dynamic>>(sourcePhraseStoreName);
  
  /// Get store for a specific locale (one store per language)
  StoreRef<String, Map<String, dynamic>> _getTranslationStore(String locale) {
    return StoreRef<String, Map<String, dynamic>>('translations_$locale');
  }

  /// Initialize the database
  Future<void> init() async {
    if (_database != null) return;

    final dbPath = join('bin', 'db', dbName);
    await Directory(dirname(dbPath)).create(recursive: true);
    _database = await databaseFactoryIo.openDatabase(dbPath);
  }

  /// Get all stored source phrases
  Future<Map<String, StoredPhrase>> getAllPhrases() async {
    await init();
    final records = await _sourcePhraseStore.find(_database!);
    
    final result = <String, StoredPhrase>{};
    for (final record in records) {
      result[record.key] = StoredPhrase.fromMap(record.key, record.value);
    }
    return result;
  }

  /// Save or update a source phrase
  Future<void> savePhrase(StoredPhrase phrase) async {
    await init();
    await _sourcePhraseStore.record(phrase.key).put(_database!, phrase.toMap());
  }

  /// Save multiple source phrases
  Future<void> savePhrases(List<StoredPhrase> phrases) async {
    await init();
    await _database!.transaction((txn) async {
      for (final phrase in phrases) {
        await _sourcePhraseStore.record(phrase.key).put(txn, phrase.toMap());
      }
    });
  }

  /// Check if a phrase exists and has the same value
  Future<bool> phraseUnchanged(String key, String value) async {
    await init();
    final record = await _sourcePhraseStore.record(key).get(_database!);
    if (record == null) return false;
    return record['value'] == value;
  }

  // ============ TRANSLATIONS METHODS ============

  /// Get a translation for a specific phrase and locale
  Future<StoredTranslation?> getTranslation(String phraseKey, String locale) async {
    await init();
    final store = _getTranslationStore(locale);
    final record = await store.record(phraseKey).get(_database!);
    
    if (record == null) return null;
    return StoredTranslation.fromMap(phraseKey, locale, record);
  }

  /// Check if a translation is manual (should not be overwritten)
  Future<bool> isManualTranslation(String phraseKey, String locale) async {
    final translation = await getTranslation(phraseKey, locale);
    return translation?.translatedBy == 'manual';
  }

  /// Save a single translation
  Future<void> saveTranslation(StoredTranslation translation) async {
    await init();
    final store = _getTranslationStore(translation.locale);
    await store.record(translation.phraseKey).put(
      _database!,
      translation.toMap(),
    );
  }

  /// Save multiple translations for a specific locale (batched for performance)
  Future<void> saveTranslations(List<StoredTranslation> translations) async {
    await init();
    
    // Group translations by locale for efficient storage
    final byLocale = <String, List<StoredTranslation>>{};
    for (final translation in translations) {
      byLocale.putIfAbsent(translation.locale, () => []).add(translation);
    }
    
    // Save each locale's translations to its own store
    await _database!.transaction((txn) async {
      for (final entry in byLocale.entries) {
        final locale = entry.key;
        final localeTranslations = entry.value;
        final store = _getTranslationStore(locale);
        
        for (final translation in localeTranslations) {
          await store.record(translation.phraseKey).put(
            txn,
            translation.toMap(),
          );
        }
      }
    });
  }

  /// Get all translations for a specific locale
  Future<Map<String, StoredTranslation>> getTranslationsForLocale(String locale) async {
    await init();
    final store = _getTranslationStore(locale);
    final records = await store.find(_database!);
    
    final result = <String, StoredTranslation>{};
    for (final record in records) {
      result[record.key] = StoredTranslation.fromMap(record.key, locale, record.value);
    }
    return result;
  }

  /// Get phrases that need translation (new or changed)
  Future<List<MapEntry<String, String>>> getPhrasesNeedingTranslation(
    Map<String, String> currentPhrases,
  ) async {
    final stored = await getAllPhrases();
    final needsTranslation = <MapEntry<String, String>>[];

    for (final entry in currentPhrases.entries) {
      final storedPhrase = stored[entry.key];
      
      // New phrase or value changed
      if (storedPhrase == null || storedPhrase.value != entry.value) {
        needsTranslation.add(entry);
      }
    }

    return needsTranslation;
  }

  /// Close the database
  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}

