import 'package:yaml/yaml.dart';

import 'ir.dart';
import 'naming.dart';

/// Reads an OpenAPI 3.x document (YAML or JSON) into an [ApiDoc].
///
/// Covers primitives, nested objects, arrays, string enums, nullable and
/// required, local `$ref`s, `allOf` merging, path/query/body params and one
/// JSON response per operation. `oneOf`/`anyOf`, multipart and header
/// params are reported in [ApiDoc.warnings] instead.
class OpenApiLoader {
  ApiDoc load(String text) {
    final Object? doc;
    try {
      doc = _plain(loadYaml(text));
    } on YamlException catch (e) {
      throw FormatException('Invalid spec: ${e.message}');
    }
    if (doc is! Map<String, Object?>) {
      throw const FormatException('Invalid spec: expected a map');
    }
    final version = doc['openapi'];
    if (version is! String || !version.startsWith('3.')) {
      throw FormatException(
        doc.containsKey('swagger')
            ? 'Swagger 2.0 is not supported; convert the spec to OpenAPI 3.'
            : 'Not an OpenAPI 3.x document (missing "openapi: 3.x").',
      );
    }
    return _Loader(doc).run();
  }

  static Object? _plain(Object? node) => switch (node) {
    YamlMap m => <String, Object?>{
      for (final e in m.entries) '${e.key}': _plain(e.value),
    },
    YamlList l => [for (final v in l) _plain(v)],
    _ => node,
  };
}

typedef _Json = Map<String, Object?>;

const _methods = {'get', 'put', 'post', 'delete', 'patch', 'head', 'options'};
const _envelopeKeys = {
  'code',
  'message',
  'msg',
  'status',
  'statusCode',
  'success',
  'error',
  'errors',
};

class _Loader {
  _Loader(this.root);

  final _Json root;
  final schemas = <String, ApiSchema>{};
  final warnings = <String>[];

  /// Component name → Dart class name, for schemas already registered.
  final _componentClass = <String, String>{};

  /// Dart names taken (registered or being built).
  final _taken = <String>{};

  _Json _components(String kind) {
    final c = root['components'];
    final m = c is Map ? c[kind] : null;
    return m is _Json ? m : const {};
  }

  ApiDoc run() {
    final ops = <ApiOperation>[];
    final names = <String>{};
    final paths = root['paths'];
    if (paths is _Json) {
      for (final MapEntry(key: path, value: item) in paths.entries) {
        if (item is! _Json) continue;
        for (final MapEntry(key: method, value: op) in item.entries) {
          if (!_methods.contains(method) || op is! _Json) continue;
          final built = _operation(path, method, item, op, names);
          if (built != null) ops.add(built);
        }
      }
    }
    final info = root['info'];
    return ApiDoc(
      title: info is Map && info['title'] is String
          ? info['title'] as String
          : '',
      operations: ops,
      schemas: schemas,
      warnings: warnings,
    );
  }

  ApiOperation? _operation(
    String path,
    String method,
    _Json pathItem,
    _Json op,
    Set<String> names,
  ) {
    var name = op['operationId'] is String
        ? identifier(op['operationId'] as String)
        : identifier('$method ${path.replaceAll(RegExp(r'[{}]'), ' by ')}');
    for (var i = 2; names.contains(name); i++) {
      name = '${name.replaceAll(RegExp(r'\d+$'), '')}$i';
    }
    names.add(name);
    final where = '$name (${method.toUpperCase()} $path)';
    final hint = pascal(name);

    // Path-level params, overridden by operation-level ones.
    final params = <String, _Json>{};
    for (final list in [pathItem['parameters'], op['parameters']]) {
      if (list is! List) continue;
      for (final raw in list) {
        final param = _deref(raw, 'parameters');
        if (param == null) continue;
        params['${param['in']}:${param['name']}'] = param;
      }
    }
    final pathParams = <ApiParam>[];
    final queryParams = <ApiParam>[];
    for (final param in params.values) {
      final jsonName = '${param['name']}';
      final location = param['in'];
      if (location != 'path' && location != 'query') {
        warnings.add(
          '$where: $location parameter "$jsonName" is not generated; '
          'pass it through your API client.',
        );
        continue;
      }
      final built = ApiParam(
        name: identifier(jsonName),
        jsonName: jsonName,
        type: _type(param['schema'], '$hint${pascal(jsonName)}', where),
        required: location == 'path' || param['required'] == true,
      );
      (location == 'path' ? pathParams : queryParams).add(built);
    }
    pathParams.sort(
      (a, b) => path
          .indexOf('{${a.jsonName}}')
          .compareTo(path.indexOf('{${b.jsonName}}')),
    );

    ApiBody? body;
    final rawBody = _deref(op['requestBody'], 'requestBodies');
    if (rawBody != null) {
      final schema = _jsonSchema(rawBody['content']);
      if (schema == null) {
        warnings.add('$where: request body is not JSON; operation skipped.');
        return null;
      }
      body = ApiBody(_type(schema, '${hint}Request', where));
    }

    ApiType? response;
    var envelope = false;
    final responses = op['responses'];
    if (responses is _Json) {
      final codes =
          responses.keys
              .where((c) => RegExp(r'^2(\d\d|XX)$').hasMatch(c))
              .toList()
            ..sort();
      if (codes.isNotEmpty) {
        final res = _deref(responses[codes.first], 'responses');
        final schema = res == null ? null : _jsonSchema(res['content']);
        if (schema != null) {
          final resolved = _resolve(schema);
          final props = resolved['properties'];
          if (props is _Json &&
              props.containsKey('data') &&
              props.keys.any(_envelopeKeys.contains)) {
            envelope = true;
            final data = _type(props['data'], '${hint}Response', where);
            response = data is AnyType ? null : data;
          } else {
            response = _type(schema, '${hint}Response', where);
          }
        }
      }
    }

    final tags = op['tags'];
    return ApiOperation(
      name: name,
      method: method,
      path: path,
      tags: tags is List && tags.isNotEmpty
          ? [for (final t in tags) '$t']
          : const ['default'],
      summary: op['summary'] is String ? op['summary'] as String : null,
      pathParams: pathParams,
      queryParams: queryParams,
      body: body,
      response: response,
      envelope: envelope,
    );
  }

  /// The JSON schema inside a `content` map, if any.
  Object? _jsonSchema(Object? content) {
    if (content is! _Json) return null;
    for (final MapEntry(key: type, value: media) in content.entries) {
      if (type.contains('json') && media is Map) return media['schema'] ?? {};
    }
    return null;
  }

  /// Follows a `#/components/<kind>/X` reference.
  _Json? _deref(Object? raw, String kind) {
    if (raw is! _Json) return null;
    final ref = raw[r'$ref'];
    if (ref is! String) return raw;
    final prefix = '#/components/$kind/';
    if (!ref.startsWith(prefix)) {
      throw FormatException('Unsupported \$ref "$ref" (only $prefix…)');
    }
    final target = _components(kind)[ref.substring(prefix.length)];
    if (target is! _Json) throw FormatException('Unresolved \$ref "$ref"');
    return _deref(target, kind);
  }

  String _refName(String ref) {
    const prefix = '#/components/schemas/';
    if (!ref.startsWith(prefix)) {
      throw FormatException('Unsupported \$ref "$ref" (only $prefix…)');
    }
    final name = ref.substring(prefix.length);
    if (_components('schemas')[name] is! _Json) {
      throw FormatException('Unresolved \$ref "$ref"');
    }
    return name;
  }

  /// A schema with `$ref`s followed and `allOf` merged into one object.
  _Json _resolve(Object? raw) {
    if (raw is! _Json) return const {};
    final ref = raw[r'$ref'];
    if (ref is String) {
      return _resolve(_components('schemas')[_refName(ref)]);
    }
    final allOf = raw['allOf'];
    if (allOf is! List) return raw;
    final properties = <String, Object?>{};
    final required = <Object?>{};
    for (final part in [...allOf, raw]) {
      final r = identical(part, raw) ? raw : _resolve(part);
      if (r['properties'] is Map) properties.addAll(r['properties'] as _Json);
      if (r['required'] is List) required.addAll(r['required'] as List);
    }
    return {
      'type': 'object',
      if (raw['description'] != null) 'description': raw['description'],
      'properties': properties,
      'required': required.toList(),
    };
  }

  bool _isObject(_Json raw) =>
      raw['allOf'] is List ||
      (raw['properties'] is Map && (raw['properties'] as Map).isNotEmpty);

  bool _isStringEnum(_Json raw) =>
      raw['enum'] is List &&
      (raw['enum'] as List).isNotEmpty &&
      (raw['enum'] as List).every((v) => v is String);

  bool _isNullable(Object? raw) {
    if (raw is! _Json) return false;
    if (raw['nullable'] == true) return true;
    final type = raw['type'];
    return type is List && type.contains('null');
  }

  ApiType _type(Object? raw, String hint, String where) {
    if (raw is! _Json || raw.isEmpty) return const AnyType();

    final ref = raw[r'$ref'];
    if (ref is String) {
      final name = _refName(ref);
      final target = _components('schemas')[name] as _Json;
      if (_isObject(target) || _isStringEnum(target)) {
        return _registerComponent(name, target, where);
      }
      return _type(target, pascal(name), where);
    }

    final allOf = raw['allOf'];
    if (allOf is List && allOf.length == 1 && raw['properties'] == null) {
      return _type(allOf.single, hint, where);
    }

    for (final key in ['oneOf', 'anyOf']) {
      final options = raw[key];
      if (options is! List) continue;
      // `oneOf: [X, {type: 'null'}]` is just a nullable X.
      final nonNull = options
          .where((o) => !(o is Map && o['type'] == 'null'))
          .toList();
      if (nonNull.length == 1) return _type(nonNull.single, hint, where);
      warnings.add('$where: $key is not supported; $hint is typed as Object?.');
      return const AnyType();
    }

    if (_isStringEnum(raw)) return _registerEnum(_unique(pascal(hint)), raw);
    if (_isObject(raw)) {
      return _registerObject(_unique(pascal(hint)), raw, where);
    }

    var type = raw['type'];
    if (type is List) {
      final nonNull = type.where((t) => t != 'null').toList();
      type = nonNull.length == 1 ? nonNull.single : null;
    }
    switch (type) {
      case 'string':
        if (raw['format'] == 'date-time') return const DateTimeType();
        if (raw['format'] == 'binary') {
          warnings.add(
            '$where: binary data is not supported; typed as Object?.',
          );
          return const AnyType();
        }
        return const PrimitiveType('String');
      case 'integer':
        return const PrimitiveType('int');
      case 'number':
        return const PrimitiveType('double');
      case 'boolean':
        return const PrimitiveType('bool');
      case 'array':
        return ListType(_type(raw['items'], '${hint}Item', where));
      case 'object':
        return const MapType();
    }
    return const AnyType();
  }

  String _unique(String base) {
    var name = base.isEmpty ? 'Model' : base;
    if (coreTypeNames.contains(name)) {
      warnings.add(
        'Schema "$name" renamed to ${name}Model (clashes with dart:core).',
      );
      name = '${name}Model';
    }
    var candidate = name;
    for (var i = 2; _taken.contains(candidate); i++) {
      candidate = '$name$i';
    }
    _taken.add(candidate);
    return candidate;
  }

  RefType _registerComponent(String component, _Json raw, String where) {
    final known = _componentClass[component];
    if (known != null) {
      return RefType(
        known,
        isEnum: schemas[known]?.isEnum ?? _isStringEnum(raw),
      );
    }
    final name = _unique(pascal(component));
    _componentClass[component] = name;
    return _isStringEnum(raw)
        ? _registerEnum(name, raw)
        : _registerObject(name, raw, where);
  }

  RefType _registerEnum(String name, _Json raw) {
    final values = <ApiEnumValue>[];
    final used = <String>{};
    for (final v in (raw['enum'] as List).cast<String>()) {
      var id = identifier(v, isEnumValue: true);
      for (var i = 2; used.contains(id); i++) {
        id = '${identifier(v, isEnumValue: true)}$i';
      }
      used.add(id);
      values.add(ApiEnumValue(id, v));
    }
    schemas[name] = ApiSchema.enumeration(
      name,
      values,
      description: raw['description'] as String?,
    );
    return RefType(name, isEnum: true);
  }

  RefType _registerObject(String name, _Json raw, String where) {
    final resolved = _resolve(raw);
    final props = resolved['properties'] as _Json? ?? const {};
    final required = {...?(resolved['required'] as List?)};
    final fields = <ApiField>[];
    final used = <String>{};
    // Register first so self-references resolve.
    schemas[name] = ApiSchema.object(name, const []);
    for (final MapEntry(key: jsonName, value: prop) in props.entries) {
      var id = identifier(jsonName);
      for (var i = 2; used.contains(id); i++) {
        id = '${identifier(jsonName)}$i';
      }
      used.add(id);
      final isRequired = required.contains(jsonName);
      final type = _type(prop, '$name${pascal(jsonName)}', where);
      fields.add(
        ApiField(
          name: id,
          jsonName: jsonName,
          type: type,
          required: isRequired,
          nullable: type is! AnyType && (!isRequired || _isNullable(prop)),
          description: prop is Map ? prop['description'] as String? : null,
        ),
      );
    }
    schemas[name] = ApiSchema.object(
      name,
      fields,
      description: resolved['description'] as String?,
    );
    return RefType(name, isEnum: false);
  }
}
