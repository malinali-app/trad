import 'dart:convert';
import 'dart:io';

void main() async {
  try {
    print('Converting ARB to JSON...');
    
    // Read the .arb file
    final inputFile = File('bin/input/app_en.arb');
    if (!inputFile.existsSync()) {
      print('❌ Error: bin/input/app_en.arb not found!');
      exit(1);
    }
    
    final inputContent = await inputFile.readAsString();
    final Map<String, dynamic> arbData = jsonDecode(inputContent);
    
    // Filter out ARB metadata (keys starting with @)
    // and convert to list of single-entry maps
    final List<Map<String, dynamic>> jsonData = arbData.entries
        .where((entry) => !entry.key.startsWith('@')) // Skip metadata
        .map((entry) => {entry.key: entry.value.toString()})
        .toList();

    // Write to the .json file with pretty formatting
    final outputFile = File('bin/input/phrases.json');
    
    // Use JsonEncoder with indent for readability
    const encoder = JsonEncoder.withIndent('    ');
    final prettyJson = encoder.convert(jsonData);
    
    await outputFile.writeAsString(prettyJson);

    print('✓ Successfully converted ${jsonData.length} phrases');
    print('✓ Output: bin/input/phrases.json');
    
    // Show examples of special characters that were preserved
    final specialChars = jsonData.where((item) {
      final value = item.values.first.toString();
      return value.contains('\$') || 
             value.contains('\\n') || 
             value.contains('"');
    });
    
    if (specialChars.isNotEmpty) {
      print('✓ Preserved ${specialChars.length} phrases with special characters');
    }
    
  } catch (e) {
    print('❌ Error during conversion: $e');
    exit(1);
  }
}