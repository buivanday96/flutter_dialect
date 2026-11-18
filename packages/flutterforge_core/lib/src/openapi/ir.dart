/// The small internal model of an API: only what the emitter needs.
library;

sealed class ApiType {
  const ApiType();
}

/// `String`, `int`, `double` or `bool`.
class PrimitiveType extends ApiType {
  const PrimitiveType(this.dart);
  final String dart;
}

class DateTimeType extends ApiType {
  const DateTimeType();
}

class ListType extends ApiType {
  const ListType(this.item);
  final ApiType item;
}

/// A free-form JSON object.
class MapType extends ApiType {
  const MapType();
}

/// A generated class or enum, by Dart name.
class RefType extends ApiType {
  const RefType(this.name, {required this.isEnum});
  final String name;
  final bool isEnum;
}

/// Anything we can't type (oneOf, unknown): passed through as `Object?`.
class AnyType extends ApiType {
  const AnyType();
}

class ApiField {
  const ApiField({
    required this.name,
    required this.jsonName,
    required this.type,
    required this.required,
    required this.nullable,
    this.description,
  });

  final String name;
  final String jsonName;
  final ApiType type;

  /// Listed in the schema's `required`.
  final bool required;

  /// The Dart type gets a `?`.
  final bool nullable;
  final String? description;
}

class ApiEnumValue {
  const ApiEnumValue(this.name, this.value);
  final String name;
  final String value;
}

class ApiSchema {
  const ApiSchema.object(this.name, this.fields, {this.description})
    : enumValues = const [];
  const ApiSchema.enumeration(this.name, this.enumValues, {this.description})
    : fields = const [];

  final String name;
  final String? description;
  final List<ApiField> fields;
  final List<ApiEnumValue> enumValues;

  bool get isEnum => enumValues.isNotEmpty;
}

class ApiParam {
  const ApiParam({
    required this.name,
    required this.jsonName,
    required this.type,
    required this.required,
  });

  final String name;
  final String jsonName;
  final ApiType type;
  final bool required;
}

class ApiBody {
  const ApiBody(this.type);
  final ApiType type;
}

class ApiOperation {
  const ApiOperation({
    required this.name,
    required this.method,
    required this.path,
    required this.tags,
    required this.pathParams,
    required this.queryParams,
    required this.body,
    required this.response,
    required this.envelope,
    this.summary,
  });

  /// Dart method name.
  final String name;

  /// Lower-case HTTP method.
  final String method;
  final String path;
  final List<String> tags;
  final String? summary;

  /// In the order they appear in [path].
  final List<ApiParam> pathParams;
  final List<ApiParam> queryParams;
  final ApiBody? body;

  /// Decoded payload type; `null` when there is none.
  final ApiType? response;

  /// The JSON response wraps the payload in `{code, message, data}`;
  /// [response] is the type of `data`.
  final bool envelope;
}

class ApiDoc {
  ApiDoc({
    required this.title,
    required this.operations,
    required this.schemas,
    required this.warnings,
  });

  final String title;
  final List<ApiOperation> operations;

  /// Every class/enum some operation needs, keyed by Dart name.
  final Map<String, ApiSchema> schemas;

  /// Things that were skipped or simplified.
  final List<String> warnings;

  List<String> get tags => {for (final o in operations) ...o.tags}.toList();

  /// Operations tagged [tag] (case-insensitive). Throws [ArgumentError] when
  /// there are none.
  List<ApiOperation> operationsFor(String tag) {
    final t = tag.toLowerCase();
    final ops = [
      for (final o in operations)
        if (o.tags.any((x) => x.toLowerCase() == t)) o,
    ];
    if (ops.isEmpty) {
      throw ArgumentError.value(
        tag,
        'tag',
        'No operations with this tag. Tags in the spec: ${tags.join(', ')}',
      );
    }
    return ops;
  }
}
