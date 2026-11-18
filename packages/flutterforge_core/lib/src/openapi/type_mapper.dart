import 'ir.dart';

/// The Dart type for [t] (without nullability).
String dartType(ApiType t) => switch (t) {
  PrimitiveType(:final dart) => dart,
  DateTimeType() => 'DateTime',
  ListType(:final item) => 'List<${dartType(item)}>',
  MapType() => 'Map<String, dynamic>',
  RefType(:final name) => name,
  AnyType() => 'Object?',
};

/// [t] with `?` added when [nullable] (and not already nullable).
String dartTypeOf(ApiType t, {required bool nullable}) =>
    nullable && t is! AnyType ? '${dartType(t)}?' : dartType(t);

/// Builds JSON decode/encode expressions using the project's method names
/// (`fromJson/toJson` or `fromMap/toMap`).
class JsonCodec {
  const JsonCodec({this.from = 'fromJson', this.to = 'toJson'});

  final String from;
  final String to;

  /// Expression turning JSON value [expr] into [t].
  String decode(ApiType t, String expr, {bool nullable = false}) {
    if (nullable) {
      return switch (t) {
        AnyType() => expr,
        PrimitiveType(dart: 'String' || 'bool') => '$expr as ${dartType(t)}?',
        PrimitiveType(dart: 'int') => '($expr as num?)?.toInt()',
        PrimitiveType(dart: 'double') => '($expr as num?)?.toDouble()',
        MapType() => '$expr as Map<String, dynamic>?',
        _ => '$expr == null ? null : ${decode(t, expr)}',
      };
    }
    return switch (t) {
      PrimitiveType(dart: 'int') => '($expr as num).toInt()',
      PrimitiveType(dart: 'double') => '($expr as num).toDouble()',
      PrimitiveType(:final dart) => '$expr as $dart',
      DateTimeType() => 'DateTime.parse($expr as String)',
      ListType(:final item) =>
        '($expr as List<dynamic>).map((e) => ${decode(item, 'e')}).toList()',
      MapType() => '$expr as Map<String, dynamic>',
      RefType(:final name, isEnum: true) => '$name.fromValue($expr as String)',
      RefType(:final name) => '$name.$from($expr as Map<String, dynamic>)',
      AnyType() => expr,
    };
  }

  /// Expression turning Dart value [expr] of type [t] into JSON.
  /// With [nullable], [expr] may be null and the result is null then.
  String encode(ApiType t, String expr, {bool nullable = false}) {
    final q = nullable ? '?' : '';
    return switch (t) {
      DateTimeType() => '$expr$q.toIso8601String()',
      ListType(:final item) when !isIdentity(item) =>
        '$expr$q.map((e) => ${encode(item, 'e')}).toList()',
      RefType(isEnum: true) => '$expr$q.value',
      RefType() => '$expr$q.$to()',
      _ => expr,
    };
  }

  /// Whether [encode] returns its input unchanged.
  static bool isIdentity(ApiType t) => switch (t) {
    DateTimeType() || RefType() => false,
    ListType(:final item) => isIdentity(item),
    _ => true,
  };
}
