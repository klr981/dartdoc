// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io' show stderr, stdout;

import 'package:analyzer/file_system/file_system.dart';
import 'package:cli_util/cli_logging.dart' show Ansi;
import 'package:dartdoc/src/dartdoc_options.dart';
import 'package:dartdoc/src/package_meta.dart';
import 'package:logging/logging.dart';

final _logger = Logger('dartdoc');

/// A custom [Level] for tracking file writes and verification.
///
/// Has a value of `501` – one more than [Level.FINE].
const Level progressLevel = Level('PROGRESS', 501);

/// A custom [Level] for errant print statements.
///
/// Has a value of `1201` – one more than [Level.SHOUT].
const Level printLevel = Level('PRINT', 1201);

void logWarning(String? message) {
  _logger.log(Level.WARNING, message);
}

void logInfo(String? message) {
  _logger.log(Level.INFO, message);
}

void logDebug(String? message) {
  _logger.log(Level.FINE, message);
}

void logProgress(String? message) {
  _logger.log(progressLevel, message);
}

void logPrint(String? message) {
  _logger.log(printLevel, message);
}

abstract class Jsonable {
  /// The `String` to print when in human-readable mode
  String get text;

  /// The JSON content to print when in JSON-output mode.
  Object toJson();

  @override
  String toString() => text;
}

void startLogging(LoggingContext config) {
  // By default, get all log output at `progressLevel` or greater.
  // This allows us to capture progress events and print `...`.
  Logger.root.level = progressLevel;
  if (config.json) {
    Logger.root.onRecord.listen((record) {
      if (record.level == progressLevel) {
        return;
      }

      var output = <String, dynamic>{'level': record.level.name};

      if (record.object is Jsonable) {
        output['data'] = record.object;
      } else {
        output['message'] = record.message;
      }

      print(json.encode(output));
    });
  } else {
    final stopwatch = Stopwatch()..start();

    // Used to track if we're printing `...` to show progress.
    // Allows unified new-line tracking
    var writingProgress = false;
    var ansi = Ansi(Ansi.terminalSupportsAnsi);
    var spinnerIndex = 0;
    const spinner = ['-', r'\', '|', '/'];

    Logger.root.onRecord.listen((record) {
      if (record.level == progressLevel) {
        if (!config.quiet &&
            config.showProgress &&
            stopwatch.elapsed.inMilliseconds > 125) {
          if (writingProgress = false) {
            stdout.write(' ');
          }
          writingProgress = true;
          stdout.write('${ansi.backspace}${spinner[spinnerIndex]}');
          spinnerIndex = (spinnerIndex + 1) % spinner.length;
          stopwatch.reset();
        }
        return;
      }

      stopwatch.reset();
      if (writingProgress) {
        stdout.write('${ansi.backspace} ${ansi.backspace}');
      }
      var message = record.message;
      assert(message.isNotEmpty);

      if (record.level < Level.WARNING) {
        if (!config.quiet) {
          print(message);
        }
      } else {
        if (writingProgress) {
          // Some console implementations, like IntelliJ, apparently need
          // the backspace to occur for stderr as well.
          stderr.write('${ansi.backspace} ${ansi.backspace}');
        }
        stderr.writeln(message);
      }
      writingProgress = false;
    });
  }
}

abstract class LoggingContext implements DartdocOptionContextBase {
  bool get json => optionSet['json'].valueAt(context);

  bool get showProgress => optionSet['showProgress'].valueAt(context);

  bool get quiet => optionSet['quiet'].valueAt(context);
}

List<DartdocOption<Object>> createLoggingOptions(
    PackageMetaProvider packageMetaProvider) {
  var resourceProvider = packageMetaProvider.resourceProvider;
  return [
    DartdocOptionArgOnly<bool>('json', false, resourceProvider,
        help: 'Prints out progress JSON maps. One entry per line.',
        negatable: true),
    DartdocOptionArgOnly<bool>(
        'showProgress', Ansi.terminalSupportsAnsi, resourceProvider,
        help: 'Display progress indications to console stdout.',
        negatable: true),
    DartdocOptionArgSynth<bool>('quiet',
        (DartdocSyntheticOption<Object> option, Folder dir) {
      if (option.parent['generateDocs'].valueAt(dir) == false) {
        return true;
      }
      return false;
    }, resourceProvider,
        abbr: 'q',
        negatable: true,
        help: 'Only show warnings and errors; silence all other output.'),
  ];
}
