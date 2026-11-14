import 'dart:io';

import 'package:html/parser.dart' show parse;
import 'package:http/http.dart';

import 'environment.dart';

Future<void> main() async => write(await process(await fetch()));

Future<Set<String>> fetch() async {
  print('Fetching lint rules from $remote.');

  final response = parse((await get(remote)).body);

  // The page lists every rule in a YAML snippet, i.e. `linter:\n  rules:\n    - rule_name`.
  final rules = response
      .getElementsByTagName('code')
      .map((code) => code.text)
      .firstWhere((text) => text.trimLeft().startsWith('linter:'), orElse: () => '')
      .split('\n')
      .map((line) => RegExp(r'^\s*-\s*(\w+)\s*$').firstMatch(line)?.group(1))
      .whereType<String>()
      .toSet();

  if (rules.isEmpty) {
    throw StateError('No rules found.');
  }

  return rules;
}

Future<(Set<String> released, Set<String> removed)> process(Set<String> remote) async {
  final existing = <String>{...rules['linter']['rules'], ...rules['ignore']};
  final released = <String>{};
  final experimental = <String>{};
  final unreleased = <String>{};
  final removed = <String>{};

  print('Checking rules. This might take awhile.');
  for (final rule in remote) {
    print('https://dart.dev/tools/linter-rules/$rule');
    final response = await get(Uri.parse('https://dart.dev/tools/linter-rules/$rule'));
    if (response.statusCode == 404) {
      print('Warning: https://dart.dev/tools/linter-rules/$rule does not exist.');
      continue;
    }

    final tags = parse(response.body).querySelectorAll('.tags .tag-label').map((tag) => tag.text).join(' ');
    if (tags.isEmpty) {
      print('Warning: unable to find tags for https://dart.dev/tools/linter-rules/$rule.');
      continue;
    }

    final isRemoved = tags.contains('Deprecated') || tags.contains('Removed');
    final isExperimental = tags.contains('Experimental');
    final isUnreleased = tags.contains('Unreleased');

    if (existing.contains(rule)) {
      if (isRemoved) {
        removed.add(rule);
      }
    } else if (isExperimental) {
      experimental.add(rule);
    } else if (isUnreleased) {
      unreleased.add(rule);
    } else if (!isRemoved) {
      released.add(rule);
    }
  }

  if (experimental.isNotEmpty) {
    print('The following rules are experimental:');
    for (final rule in experimental) {
      print('https://dart.dev/tools/linter-rules/$rule');
    }
  }

  if (unreleased.isNotEmpty) {
    print('The following rules are unreleased:');
    for (final rule in unreleased) {
      print('https://dart.dev/tools/linter-rules/$rule');
    }
  }

  return (released, removed);
}

void write((Set<String> released, Set<String> removed) rules) {
  final (Set<String> released, Set<String> removed) = rules;

  if (released.isNotEmpty) {
    print('The following rules are stable:');
    options.writeAsStringSync('\nreleased:\n', mode: FileMode.append);

    for (final rule in released) {
      print('https://dart.dev/tools/linter-rules/$rule');
      options.writeAsStringSync('  - $rule\n', mode: FileMode.append);
    }
  } else {
    print('No new stable lint rules released.');
  }

  if (removed.isNotEmpty) {
    print('The following rules have been removed:');
    options.writeAsStringSync('\nremoved:\n', mode: FileMode.append);

    for (final rule in removed) {
      print('https://dart.dev/tools/linter-rules/$rule');
      options.writeAsStringSync('  - $rule\n', mode: FileMode.append);
    }
  } else {
    print('No new lint rules removed.');
  }
}
