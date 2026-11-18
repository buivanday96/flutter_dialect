import 'dart:io';

import 'package:args/args.dart';
import 'package:dart_mcp/stdio.dart';
import 'package:flutter_dialect/mcp_server.dart';

/// Stdio MCP server. Logs go to stderr; stdout carries JSON-RPC only.
void main(List<String> args) {
  final parser = ArgParser()
    ..addOption(
      'root',
      help: 'Flutter project directory (default: current directory).',
    )
    ..addFlag('help', abbr: 'h', negatable: false);
  final results = parser.parse(args);
  if (results.flag('help')) {
    stderr.writeln(
      'Usage: flutter_dialect_mcp [--root <dir>]\n${parser.usage}',
    );
    return;
  }
  DialectServer(
    stdioChannel(input: stdin, output: stdout),
    root: results.option('root') ?? Directory.current.path,
  );
}
