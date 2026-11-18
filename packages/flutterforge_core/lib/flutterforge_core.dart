/// Deterministic project-convention detection and convention-aware code
/// generation for Flutter apps.
library;

export 'src/changes/apply.dart';
export 'src/changes/change_plan.dart';
export 'src/changes/diff.dart' show unifiedDiff;
export 'src/config/forge_config.dart';
export 'src/context/client_shape.dart' show ClientShape, WrapperMethod;
export 'src/context/conventions.dart' show Detection;
export 'src/context/project_context.dart';
export 'src/context/scanner.dart';
export 'src/context/similar_code.dart';
export 'src/openapi/emitter.dart';
export 'src/openapi/ir.dart';
export 'src/openapi/loader.dart';
export 'src/openapi/type_mapper.dart' show dartType, dartTypeOf;
