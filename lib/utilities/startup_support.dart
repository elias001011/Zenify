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

import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/constants/app_constants.dart';
import 'package:musify/services/data_manager.dart' show validateHiveBackup;

/// Builds the message shown when the desktop audio engine cannot start.
///
/// libmpv is a runtime dependency that is deliberately not bundled with the
/// Linux tarball, so make the fix explicit instead of surfacing a raw error.
String desktopAudioErrorMessage(Object error) {
  final details = error.toString();
  if (details.toLowerCase().contains('libmpv')) {
    return '$appName could not start playback because libmpv is not installed.\n\n'
        'Install the libmpv runtime library and restart $appName:\n'
        '  Fedora:         sudo dnf install mpv-libs\n'
        '  Debian/Ubuntu:  sudo apt install libmpv2 (libmpv1 on older releases)\n'
        '  Arch:           sudo pacman -S mpv\n\n'
        'Details: $details';
  }
  return '$appName could not start the audio engine.\n\n$details';
}

/// Shown instead of the app when initialization fails before the router and
/// localization are available. Intentionally self-contained and English-only.
class StartupErrorApp extends StatefulWidget {
  const StartupErrorApp({super.key, required this.message});

  final String message;

  @override
  State<StartupErrorApp> createState() => _StartupErrorAppState();
}

class _StartupErrorAppState extends State<StartupErrorApp> {
  static const Color _seedColor = Color(0xFF4F6BED);

  Future<void> _copyDetails(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: widget.message));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Error details copied to clipboard.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: _seedColor),
      darkTheme: ThemeData(
        colorSchemeSeed: _seedColor,
        brightness: Brightness.dark,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.music_off_rounded,
                        size: 56,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '$appName could not start',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      SelectableText(
                        widget.message,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          FilledButton.icon(
                            onPressed: () => _copyDetails(context),
                            icon: const Icon(Icons.copy_rounded),
                            label: const Text('Copy details'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => exit(0),
                            icon: const Icon(Icons.close_rounded),
                            label: const Text('Quit'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hive boxes written by previous desktop builds.
const List<String> legacyDesktopBoxNames = [
  'settings',
  'user',
  'userNoBackup',
  'cache',
];

/// Outcome of [copyHiveBoxes].
class HiveCopyReport {
  const HiveCopyReport({this.copied = const [], this.failed = const []});

  final List<String> copied;
  final List<String> failed;

  bool get hasWork => copied.isNotEmpty || failed.isNotEmpty;

  String describe() => failed.isEmpty
      ? 'copied ${copied.join(', ')}'
      : 'failed ${failed.join(', ')}';
}

/// A staged migration must finish before any participating database reopens.
class HiveMigrationPending implements Exception {
  const HiveMigrationPending(this.path);
  final String path;
  @override
  String toString() =>
      'Library migration to $path is pending. Close other music apps and restart Zenify.';
}

/// Copies the Hive boxes in [from] into [to] when [to] has none yet.
///
/// Copy, not move: [from] may still belong to another Musify install.
/// Downloads stay put, since offline songs store absolute paths. A partly
/// copied set is removed again, so old and new data never mix.
Future<HiveCopyReport> copyHiveBoxes({
  required Directory from,
  required Directory to,
  void Function(String message, {Object? error, StackTrace? stackTrace})? log,
}) async {
  if (from.absolute.path == to.absolute.path) return const HiveCopyReport();
  final staging = Directory('${to.path}/.hive-migration');
  final journal = File('${staging.path}/pending.json');
  await to.create(recursive: true);
  final copied = <String>[];
  final locks = <RandomAccessFile>[];
  try {
    // Resume a complete staged snapshot after interruption between renames.
    if (!await journal.exists()) {
      if (await _hasHiveBoxes(to) || !await _hasHiveBoxes(from)) {
        return const HiveCopyReport();
      }
      if (await staging.exists()) await staging.delete(recursive: true);
      await staging.create(recursive: true);
      final names = <String, String>{};
      final unlocked = <String>{};
      for (final box in legacyDesktopBoxNames) {
        final name = '${box.toLowerCase()}.hive';
        final source = File('${from.path}/$name');
        if (!await source.exists()) continue;
        // Hive holds this lock while its box is open. Refuse a live source
        // rather than copy a snapshot that is changing underneath us.
        final lockFile = File('${from.path}/${box.toLowerCase()}.lock');
        final RandomAccessFile lock;
        try {
          lock = await lockFile.open(mode: FileMode.append);
        } on FileSystemException catch (error) {
          // A folder Zenify may only read (read-only, or Documents under
          // Windows' Controlled Folder Access) can't hold the lock: copy it
          // anyway and check the copy frame by frame instead.
          log?.call('Copying $name without its lock', error: error);
          unlocked.add(name);
          names[name] = box;
          continue;
        }
        try {
          await lock.lock();
          locks.add(lock);
        } catch (_) {
          await lock.close();
          rethrow;
        }
        names[name] = box;
      }
      for (final MapEntry(key: name, value: box) in names.entries) {
        final bytes = await File('${from.path}/$name').readAsBytes();
        if (unlocked.contains(name)) {
          try {
            await validateHiveBackup(box, bytes);
          } on FormatException catch (error) {
            // A damaged frame must not keep Zenify from starting: Hive
            // recovers the box on opening, as Musify itself would.
            log?.call('Copying $name with a damaged frame', error: error);
          }
        }
        await File('${staging.path}/$name').writeAsBytes(bytes, flush: true);
      }
      final pending = File('${journal.path}.tmp');
      await pending.writeAsString(jsonEncode(names.keys.toList()), flush: true);
      await pending.rename(journal.path);
    }
    final names = (jsonDecode(await journal.readAsString()) as List)
        .cast<String>();
    for (final name in names) {
      if (!legacyDesktopBoxNames.any(
        (box) => '${box.toLowerCase()}.hive' == name,
      )) {
        throw const FormatException('Invalid migration journal');
      }
      final staged = File('${staging.path}/$name');
      final target = File('${to.path}/$name');
      if (await staged.exists()) {
        if (await target.exists())
          throw StateError('Migration target already exists: $name');
        await staged.rename(target.path);
      } else if (!await target.exists()) {
        throw StateError('Incomplete migration snapshot: $name');
      }
      copied.add(name);
    }
    await journal.delete();
    await staging.delete(recursive: true);
    return HiveCopyReport(copied: copied);
  } catch (error, stack) {
    log?.call('Hive migration failed', error: error, stackTrace: stack);
    // A journal means a complete snapshot exists: preserve it for recovery.
    // The caller must not open missing boxes until this transaction completes.
    if (await journal.exists()) throw HiveMigrationPending(to.path);
    return const HiveCopyReport(failed: ['migration']);
  } finally {
    for (final lock in locks) {
      await lock.unlock();
      await lock.close();
    }
  }
}

/// A library copied from another Musify install (such as the Desktop Port)
/// carries that install's Local Sync identity and pairings; two apps sharing
/// them would pose as one device. Zenify keeps the library, starts its own
/// identity and leaves Local Sync off until turned on here.
Future<void> forgetImportedSyncIdentity() async {
  final store = Hive.box('userNoBackup');
  await store.deleteAll([
    for (final key in store.keys)
      if (key is String && key.startsWith('localSync')) key,
  ]);
  await Hive.box('settings')
      .deleteAll(['localSyncEnabled', 'localSyncLastSyncedAt']);
}

/// Modern Musify data precedes the old Documents layout. Existing Zenify
/// data wins; original files/downloads are never moved or deleted.
Future<HiveCopyReport> migrateLegacyDesktopData({
  required Directory target,
  required List<Directory> sources,
  void Function(String message, {Object? error, StackTrace? stackTrace})? log,
}) async {
  for (final source in sources) {
    final report = await copyHiveBoxes(from: source, to: target, log: log);
    if (report.hasWork) return report;
  }
  return const HiveCopyReport();
}

/// Platform support paths used before the Zenify identity change.
List<Directory> legacyMusifyDirectories(
  String targetPath, {
  required bool windows,
  Map<String, String>? environment,
}) {
  final env = environment ?? Platform.environment;
  if (windows) {
    final appData = env['APPDATA'];
    return [
      if (appData != null) ...[
        Directory('$appData/com.gokadzev/musify'),
        Directory('$appData/com.gokadzev/Musify'),
        Directory('$appData/com.gokadzev.musify'),
      ],
    ];
  }
  return [
    Directory('${Directory(targetPath).parent.path}/com.gokadzev.musify'),
  ];
}

Future<bool> _hasHiveBoxes(Directory directory) async {
  for (final box in legacyDesktopBoxNames) {
    final file = File(
      '${directory.path}${Platform.pathSeparator}${box.toLowerCase()}.hive',
    );
    if (await file.exists()) return true;
  }
  return false;
}
