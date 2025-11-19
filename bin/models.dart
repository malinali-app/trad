// Dart imports:
import 'dart:convert';

class Arb {
  final String locale;
  final Map<String, String> map;
  const Arb(this.locale, this.map);

  Arb copyWith({
    String? locale,
    Map<String, String>? map,
  }) {
    return Arb(
      locale ?? this.locale,
      map ?? this.map,
    );
  }
}

class ResponseTranslated {
  final List<Translation> translations;
  const ResponseTranslated({required this.translations});

  Map<String, dynamic> toMap() {
    return {
      'translations': translations.map((x) => x.toMap()).toList(),
    };
  }

  factory ResponseTranslated.fromMap(Map<String, dynamic> map) {
    return ResponseTranslated(
      translations: List<Translation>.from(
          map['translations']?.map((x) => Translation.fromMap(x))),
    );
  }

  String toJson() => json.encode(toMap());

  factory ResponseTranslated.fromJson(String source) =>
      ResponseTranslated.fromMap(json.decode(source));

  @override
  String toString() => 'ResponseTranslated(translations: $translations)';
}

class Translation {
  final String text;
  final String to;
  const Translation({required this.text, required this.to});

  Map<String, dynamic> toMap() {
    return {
      'text': text,
      'to': to,
    };
  }

  factory Translation.fromMap(Map<String, dynamic> map) {
    return Translation(
      text: map['text'] ?? '',
      to: map['to'] ?? '',
    );
  }

  String toJson() => json.encode(toMap());

  factory Translation.fromJson(String source) =>
      Translation.fromMap(json.decode(source));
}
