/*
 *     Copyright (C) 2026 Valeri Gokadze
 *
 *     Musify is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version.
 *
 *     Musify is distributed in the hope that it will be useful,
 *     but WITHOUT ANY WARRANTY; without even the implied warranty of
 *     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *     GNU General Public License for more details.
 *
 *     You should have received a copy of the GNU General Public License
 *     along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 *
 *     For more information about Musify, including how to contribute,
 *     please visit: https://github.com/gokadzev/Musify
 */

import 'dart:convert';
import 'dart:io';

import 'package:hive_ce/hive_ce.dart';
import 'package:musify/utilities/startup_support.dart';

/// Folders chosen in the installer, from `install-config.txt` beside the exe.
class InstallConfig {
  const InstallConfig({this.dataDir, this.downloadsDir, this.previousDataDir});

  static const fileName = 'install-config.txt';
  static const _appliedDownloadsKey = 'installDownloadsDirectory';

  final String? dataDir;
  final String? previousDataDir;
  final String? downloadsDir;

  static InstallConfig parse(String text) {
    String? read(String key) {
      final body = text.startsWith('\uFEFF') ? text.substring(1) : text;
      for (final line in const LineSplitter().convert(body)) {
        if (!line.startsWith('$key=')) continue;
        final value = line.substring(key.length + 1).trim();
        return _isAbsolute(value) ? value : null;
      }
      return null;
    }

    return InstallConfig(
      dataDir: read('dataDir'),
      downloadsDir: read('downloadsDir'),
      previousDataDir: read('previousDataDir'),
    );
  }

  static Future<InstallConfig> load({File? file}) async {
    try {
      final source =
          file ??
          File(
            '${File(Platform.resolvedExecutable).parent.path}'
            '${Platform.pathSeparator}$fileName',
          );
      if (!await source.exists()) return const InstallConfig();
      return parse(utf8.decode(await source.readAsBytes()));
    } catch (_) {
      return const InstallConfig();
    }
  }

  static bool _isAbsolute(String value) =>
      !value.contains('\u0000') &&
      (value.startsWith('/') ||
          RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value) ||
          value.startsWith(r'\\'));

  /// The Hive folder: [dataDir] once usable and populated, else [defaultDir].
  Future<String> resolveDataDir(
    String defaultDir, {
    void Function(String message)? log,
  }) async {
    final target = dataDir ?? defaultDir;
    final previous = previousDataDir;
    final source = previous != null && await Directory(previous).exists()
        ? previous
        : defaultDir;
    if (_same(target, source)) return source;

    try {
      final directory = Directory(target);
      await directory.create(recursive: true);
      final probe = await directory.createTemp('.zenify-write-');
      await probe.delete();

      final report = await copyHiveBoxes(
        from: Directory(source),
        to: directory,
        log: log == null
            ? null
            : (message, {error, stackTrace}) =>
                  log(error == null ? message : '$message: $error'),
      );
      if (report.failed.isNotEmpty) {
        log?.call('Could not copy ${report.failed.join(', ')} to $target');
        return source;
      }
      if (report.copied.isNotEmpty) {
        log?.call('Copied ${report.copied.join(', ')} to $target');
      }
      return target;
    } on HiveMigrationPending {
      rethrow;
    } catch (e) {
      log?.call('Data folder $target is unusable, keeping $source: $e');
      return source;
    }
  }

  /// Seeds the downloads folder on first setup. Settings can move it later.
  Future<void> applyDownloadsDir({void Function(String message)? log}) async {
    final target = downloadsDir;
    if (target == null) return;

    try {
      final store = Hive.box('userNoBackup');
      final existing = store.get('downloadsDirectory');
      // The old marker could also name a folder the installer never applied.
      if (store.containsKey(_appliedDownloadsKey) ||
          (existing is String && existing.isNotEmpty)) {
        return;
      }
      await Directory(target).create(recursive: true);
      await store.putAll({
        'downloadsDirectory': target,
        _appliedDownloadsKey: target,
      });
    } catch (e) {
      log?.call('Downloads folder $target is unusable, using the default: $e');
    }
  }

  static bool _same(String a, String b) {
    String normal(String value) {
      final slashed = value.replaceAll(r'\', '/');
      final trimmed = slashed.length > 1 && slashed.endsWith('/')
          ? slashed.substring(0, slashed.length - 1)
          : slashed;
      return Platform.isWindows ? trimmed.toLowerCase() : trimmed;
    }

    return normal(a) == normal(b);
  }
}
