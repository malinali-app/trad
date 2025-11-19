import 'dart:convert';
import 'dart:io';

/// Check all translation files for common issues:
/// 1. Untranslated strings (still in French or English)
/// 2. Empty translations
/// 3. Suspicious patterns
void main() async {
  // Determine base directory (script might be run from bin/ or root)
  final outputDir = Directory('output').existsSync() 
      ? Directory('output')
      : Directory('bin/output');
  
  if (!outputDir.existsSync()) {
    print('❌ Error: output directory not found!');
    exit(1);
  }

  // Load source files
  final frFile = File('${outputDir.path}/app_fr.arb');
  final enFile = File('${outputDir.path}/app_en.arb');
  
  if (!frFile.existsSync() || !enFile.existsSync()) {
    print('❌ Error: Source files (app_fr.arb or app_en.arb) not found!');
    exit(1);
  }

  final frData = json.decode(await frFile.readAsString()) as Map<String, dynamic>;
  final enData = json.decode(await enFile.readAsString()) as Map<String, dynamic>;

  // Find all ARB files
  final arbFiles = outputDir
      .listSync()
      .where((file) => file.path.endsWith('.arb'))
      .map((file) => file as File)
      .where((file) => !file.path.contains('_fr.arb') && !file.path.contains('_en.arb'))
      .toList();

  print('Checking ${arbFiles.length} translation files...\n');

  final issues = <String, List<TranslationIssue>>{};
  final untranslatedKeys = <String>{};

  // Check each file
  for (final arbFile in arbFiles) {
    final filename = arbFile.path.split(Platform.pathSeparator).last;
    final locale = filename.replaceAll('app_', '').replaceAll('.arb', '');
    
    try {
      final contents = await arbFile.readAsString();
      final Map<String, dynamic> arbData = json.decode(contents);
      
      final fileIssues = <TranslationIssue>[];
      
      // Check each translation
      for (final entry in arbData.entries) {
        final key = entry.key;
        if (key.startsWith('@')) continue; // Skip metadata
        
        final value = entry.value.toString();
        final frValue = frData[key]?.toString() ?? '';
        final enValue = enData[key]?.toString() ?? '';
        
        // Check for untranslated strings (still in French)
        if (value == frValue && value.isNotEmpty) {
          fileIssues.add(TranslationIssue(
            key: key,
            issue: 'Untranslated (same as French source)',
            value: value,
            expected: 'Should be translated to $locale',
          ));
          untranslatedKeys.add(key);
        }
        
        // Check for suspicious patterns
        if (value.contains('Gestion des paiements')) {
          fileIssues.add(TranslationIssue(
            key: key,
            issue: 'Contains French text "Gestion des paiements"',
            value: value,
            expected: 'Should be translated',
          ));
        }
        
        if (value.contains('Voir les statistiques')) {
          fileIssues.add(TranslationIssue(
            key: key,
            issue: 'Contains French text "Voir les statistiques"',
            value: value,
            expected: 'Should be translated',
          ));
        }
        
        if (value.contains('Saisir une vente hors-catalogue')) {
          fileIssues.add(TranslationIssue(
            key: key,
            issue: 'Contains French text "Saisir une vente hors-catalogue"',
            value: value,
            expected: 'Should be translated',
          ));
        }
        
        // Check for empty translations
        if (value.isEmpty && frValue.isNotEmpty) {
          fileIssues.add(TranslationIssue(
            key: key,
            issue: 'Empty translation',
            value: value,
            expected: frValue,
          ));
        }
        
        // Check for English words that might be wrong (like "Cart" in non-English files)
        if (locale != 'en' && value == 'Cart' && key == 'cabas') {
          fileIssues.add(TranslationIssue(
            key: key,
            issue: 'Uses English word "Cart" instead of translation',
            value: value,
            expected: 'Should be translated to $locale',
          ));
        }
      }
      
      if (fileIssues.isNotEmpty) {
        issues[locale] = fileIssues;
      }
    } catch (e) {
      print('⚠ Error reading $filename: $e');
    }
  }

  // Print summary
  print('=' * 80);
  print('TRANSLATION CHECK SUMMARY');
  print('=' * 80);
  print('\nTotal files checked: ${arbFiles.length}');
  print('Files with issues: ${issues.length}');
  print('Total issues found: ${issues.values.fold(0, (sum, list) => sum + list.length)}');
  print('\nUntranslated keys (appearing in multiple files): ${untranslatedKeys.length}');
  
  if (untranslatedKeys.isNotEmpty) {
    print('\nMost common untranslated keys:');
    final keyCounts = <String, int>{};
    for (final locale in issues.keys) {
      for (final issue in issues[locale]!) {
        if (issue.issue.contains('Untranslated') || issue.issue.contains('French text')) {
          keyCounts[issue.key] = (keyCounts[issue.key] ?? 0) + 1;
        }
      }
    }
    final sortedKeys = keyCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in sortedKeys.take(10)) {
      print('  - ${entry.key}: appears in ${entry.value} files');
    }
  }

  // Print detailed issues by locale
  print('\n${'=' * 80}');
  print('DETAILED ISSUES BY LOCALE');
  print('=' * 80);
  
  final sortedLocales = issues.keys.toList()..sort();
  for (final locale in sortedLocales) {
    final localeIssues = issues[locale]!;
    print('\n📁 $locale (${localeIssues.length} issues):');
    print('-' * 80);
    
    // Group by issue type
    final byType = <String, List<TranslationIssue>>{};
    for (final issue in localeIssues) {
      final type = issue.issue.split(':').first;
      byType.putIfAbsent(type, () => []).add(issue);
    }
    
    for (final type in byType.keys) {
      print('\n  $type:');
      for (final issue in byType[type]!.take(5)) {
        print('    • ${issue.key}');
        print('      Current: "${issue.value}"');
        if (issue.expected.isNotEmpty) {
          print('      Expected: ${issue.expected}');
        }
      }
      if (byType[type]!.length > 5) {
        print('    ... and ${byType[type]!.length - 5} more');
      }
    }
  }
  
  // Save report to file
  final reportFile = File('translation_issues_report.txt');
  final report = StringBuffer();
  report.writeln('TRANSLATION ISSUES REPORT');
  report.writeln('Generated: ${DateTime.now()}');
  report.writeln('${'=' * 80}');
  report.writeln('\nTotal issues: ${issues.values.fold(0, (sum, list) => sum + list.length)}');
  report.writeln('\nUntranslated keys: ${untranslatedKeys.join(", ")}');
  
  for (final locale in sortedLocales) {
    report.writeln('\n$locale:');
    for (final issue in issues[locale]!) {
      report.writeln('  ${issue.key}: ${issue.issue}');
      report.writeln('    Value: "${issue.value}"');
    }
  }
  
  await reportFile.writeAsString(report.toString());
  print('\n\n✅ Detailed report saved to: ${reportFile.path}');
}

class TranslationIssue {
  final String key;
  final String issue;
  final String value;
  final String expected;

  TranslationIssue({
    required this.key,
    required this.issue,
    required this.value,
    required this.expected,
  });
}

