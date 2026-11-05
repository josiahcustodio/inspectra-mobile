import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';

/// Self-update for sideloaded installs, fed by the GitHub Releases that
/// release.ps1 publishes.
///
/// A public, APK-only repo because a private one would need a token inside the
/// APK. update.json comes from the releases/latest/download redirect rather
/// than the REST API, whose 60 requests/hour limit is shared by every tablet
/// behind the same office IP.
const _manifestUrl =
    'https://github.com/josiahcustodio/inspectra-releases/releases/latest/download/update.json';

// Stamped by release.ps1. 0 in debug and plain builds, which turns this off.
const _currentBuild = int.fromEnvironment('APP_BUILD');

class AppUpdate {
  const AppUpdate({
    required this.build,
    required this.version,
    required this.notes,
    required this.url,
    required this.sha256,
    required this.megabytes,
  });

  final int build;
  final String version;
  final String notes;
  final String url;
  final String sha256;
  final int megabytes;

  /// The update for this device from an update.json body, or null when it is
  /// not newer or no APK was published for [abi].
  static AppUpdate? parse(
    String body, {
    required int currentBuild,
    required String abi,
  }) {
    final manifest = jsonDecode(body) as Map<String, dynamic>;
    final build = manifest['build'] as int;
    final apk = (manifest['apks'] as Map<String, dynamic>)[abi];
    if (build <= currentBuild || apk == null) return null;
    return AppUpdate(
      build: build,
      version: manifest['version'] as String,
      notes: manifest['notes'] as String,
      url: apk['url'] as String,
      sha256: apk['sha256'] as String,
      megabytes: apk['megabytes'] as int,
    );
  }
}

/// Wraps the whole app, above the router, so go_router redirects (the splash
/// leaving /sync, say) cannot tear the prompt down mid-download the way they
/// would a showDialog route.
class UpdateGate extends StatefulWidget {
  const UpdateGate({super.key, required this.child});

  final Widget child;

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  AppLifecycleListener? _lifecycle;
  bool _checking = false;
  int _snoozedBuild = 0;

  AppUpdate? _update;
  int? _percent; // Non-null while downloading.
  String? _error;

  @override
  void initState() {
    super.initState();
    if (_currentBuild == 0 || !Platform.isAndroid) return;
    _connectivity = Connectivity().onConnectivityChanged.listen((_) => _check());
    _lifecycle = AppLifecycleListener(onResume: _check);
    _check();
  }

  @override
  void dispose() {
    _connectivity?.cancel();
    _lifecycle?.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    if (_checking || _update != null) return;
    _checking = true;
    try {
      // Wi-Fi only: the APK is tens of MB and inspectors may be on mobile data.
      final networks = await Connectivity().checkConnectivity();
      if (!networks.contains(ConnectivityResult.wifi)) return;

      final response = await http
          .get(Uri.parse(_manifestUrl))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return;

      final update = AppUpdate.parse(
        response.body,
        currentBuild: _currentBuild,
        abi: await OtaUpdate().getAbi() ?? '',
      );
      if (update == null || update.build == _snoozedBuild || !mounted) return;
      setState(() => _update = update);
    } catch (e) {
      // A failed check is not the inspector's problem; the next Wi-Fi change
      // or app resume tries again.
      debugPrint('Update check failed: $e');
    } finally {
      _checking = false;
    }
  }

  void _install() {
    final update = _update!;
    setState(() {
      _percent = 0;
      _error = null;
    });
    // A new OtaUpdate each attempt: an instance replays its first stream, so
    // reusing one would make Retry a no-op.
    OtaUpdate()
        .execute(
          update.url,
          destinationFilename: 'inspectra-update.apk',
          sha256checksum: update.sha256,
        )
        .listen((event) {
      if (!mounted) return;
      setState(() {
        switch (event.status) {
          case OtaStatus.DOWNLOADING:
            _percent = int.tryParse(event.value ?? '') ?? _percent;
          case OtaStatus.INSTALLING:
          case OtaStatus.INSTALLATION_DONE:
            // The system installer is up. If it is cancelled, the prompt is
            // still here to tap again.
            _percent = null;
          default:
            _percent = null;
            _error = 'Update failed (${event.status.name}). '
                'Check the Wi-Fi connection and try again.';
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final update = _update;
    return Stack(
      children: [
        widget.child,
        if (update != null) ...[
          const ModalBarrier(dismissible: false, color: Colors.black54),
          AlertDialog(
            title: const Text('Update available'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Inspectra ${update.version} (build ${update.build}), '
                  '${update.megabytes} MB.',
                ),
                if (update.notes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(update.notes),
                ],
                const SizedBox(height: 8),
                const Text(
                  'Finish any open inspection first. The app closes to '
                  'install. Saved and unsynced inspections are kept.',
                ),
                if (_percent != null) ...[
                  const SizedBox(height: 16),
                  LinearProgressIndicator(value: _percent! / 100),
                  const SizedBox(height: 4),
                  Text('Downloading... $_percent%'),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
            actions: _percent != null
                ? null
                : [
                    TextButton(
                      onPressed: () => setState(() {
                        _snoozedBuild = update.build;
                        _update = null;
                        _error = null;
                      }),
                      child: const Text('Later'),
                    ),
                    FilledButton(
                      onPressed: _install,
                      child: Text(_error == null ? 'Update' : 'Retry'),
                    ),
                  ],
          ),
        ],
      ],
    );
  }
}
