// Dart imports:
import 'dart:convert';

// Package imports:
import 'package:http/http.dart' as http;

// Project imports:
import 'models.dart';

import 'dart:io'; // Gives you File class

class Translate {
  static String _getApiKey() {
    try {
      return File('config/secret.txt').readAsStringSync().trim();
    } catch (e) {
      print('Error: Could not read API key from config/secret.txt');
      print('Please create the file with your Azure API key.');
      return ''; // Return empty string as fallback
    }
  }

  static Future<List<String>> translateWithAzure(
    String fromLocale,
    String toLocale,
    List<String> phrases,
  ) async {
    final apiKey = _getApiKey();
    
    if (phrases.isEmpty || apiKey.isEmpty) {
      return [];
    }
    var uri = Uri.parse(
      'https://api.cognitive.microsofttranslator.com/translate',
    );

    var queryParams = {
      "api-version": "3.0",
      "from": fromLocale,
      "to": toLocale,
    };
    uri = uri.replace(queryParameters: queryParams);

    var headers = {
      "Ocp-Apim-Subscription-Key": apiKey,
      "Ocp-Apim-Subscription-Region": "westeurope",
      "Content-type": "application/json",
      "content-type": "application/json",
    };

    // Build request body with multiple text entries
    final textEntries = phrases.map((phrase) => {"text": phrase}).toList();
    final body = json.encode(textEntries);

    final response = await http.post(uri, headers: headers, body: body);

    int statusCode = response.statusCode;

    if (statusCode >= 200 && statusCode < 300) {
      //print('Status Code: $statusCode');
      //print('Request : $body');
      //print('Response Body: ${response.body}');
      final decoded = json.decode(response.body) as List;
      final responseDart =
          decoded
              .map<ResponseTranslated>((e) => ResponseTranslated.fromMap(e))
              .toList();

      // Extract translations in order
      return responseDart.map((r) => r.translations.first.text).toList();
    } else if (statusCode == 429) {
      // Rate limit exceeded - throw specific exception
      throw RateLimitException('Rate limit exceeded (429)', response.body);
    } else {
      print('Error Status Code: $statusCode');
      print('Error Response Body: ${response.body}');
      return []; // :400036 target language invalid
    }
  }
}

/// Exception for rate limit errors (HTTP 429)
class RateLimitException implements Exception {
  final String message;
  final String responseBody;

  RateLimitException(this.message, this.responseBody);

  @override
  String toString() => 'RateLimitException: $message';
}
