import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../data/models/establishment.dart';
import '../../data/services/offline_service.dart';

// [REF: FIELD_MAP]
//
// Real basemap (OpenFreeMap vector tiles: free, no API key) with the
// inspector's live GPS dot and compass heading, plus one pin per establishment
// that carries coordinates ([REF: ESTABLISHMENT_COORDINATES]). "Save offline"
// caches the Batangas City tiles on the device so the map still draws without
// signal; the GPS dot never needed signal in the first place.

const _style = MapLibreStyles.openfreemapLiberty;
const _cityCenter = LatLng(13.76, 121.055);
// Same extent the web GIS page frames.
final _cityBounds = LatLngBounds(
  southwest: const LatLng(13.68, 120.98),
  northeast: const LatLng(13.88, 121.16),
);

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  MapLibreMapController? _controller;
  bool _locationGranted = false;
  bool _offlineReady = false;
  // 0–100 while a download runs, null otherwise.
  double? _downloadPercent;
  List<Establishment> _all = const [];
  List<Establishment> _pinned = const [];
  String _query = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // shortcut: read once; the tab stays alive in the shell, so a sync that
    // lands later shows on the map after an app restart. Re-read on tab focus
    // when inspectors notice.
    _all = OfflineService.getLocalEstablishments();
    _pinned = _all.where((e) => e.hasLocation).toList();
    Permission.locationWhenInUse.request().then((s) {
      if (mounted) setState(() => _locationGranted = s.isGranted);
    });
    getListOfRegions().then((regions) {
      if (mounted) setState(() => _offlineReady = regions.isNotEmpty);
    }).catchError((_) {});
  }

  Future<void> _addPins() async {
    final c = _controller;
    if (c == null || _pinned.isEmpty) return;
    await c.addCircles(
      [
        for (final e in _pinned)
          CircleOptions(
            geometry: LatLng(e.latitude!, e.longitude!),
            circleRadius: 9,
            circleColor: '#D32F2F',
            circleStrokeWidth: 2,
            circleStrokeColor: '#FFFFFF',
          ),
      ],
      [for (final e in _pinned) {'id': e.id}],
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Establishment> get _matches {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    // Same fields the Establishments list searches.
    return _all
        .where((e) =>
            e.name.toLowerCase().contains(q) ||
            e.ownerName.toLowerCase().contains(q) ||
            e.fullAddress.toLowerCase().contains(q))
        .take(8)
        .toList();
  }

  Future<void> _goTo(Establishment est) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _query = '';
      _searchController.clear();
    });
    if (!est.hasLocation) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${est.name} has no map location yet')),
      );
      return;
    }
    await _controller?.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(est.latitude!, est.longitude!), 17),
    );
    if (mounted) _showSheet(est);
  }

  void _onPinTapped(Circle circle) {
    final id = circle.data?['id'];
    final est = _pinned.cast<Establishment?>().firstWhere((e) => e!.id == id, orElse: () => null);
    if (est == null) return;
    _showSheet(est);
  }

  void _showSheet(Establishment est) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(est.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(est.fullAddress, style: TextStyle(color: Colors.grey.shade700)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  // Same entry point as the establishments list.
                  context.push('/inspection', extra: est);
                },
                child: const Text('Start inspection'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveOffline() async {
    setState(() => _downloadPercent = 0);
    try {
      await downloadOfflineRegion(
        OfflineRegionDefinition(
          bounds: _cityBounds,
          mapStyleUrl: _style,
          minZoom: 10,
          // shortcut: zoom 15 keeps the city under ~30 MB; raise to 16 if
          // inspectors need building outlines offline.
          maxZoom: 15,
        ),
        metadata: const {'name': 'Batangas City'},
        onEvent: (status) {
          if (!mounted) return;
          if (status is InProgress) setState(() => _downloadPercent = status.progress);
          if (status is Success) setState(() { _downloadPercent = null; _offlineReady = true; });
          if (status is Error) {
            setState(() => _downloadPercent = null);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Offline map download failed')));
          }
        },
      );
    } catch (_) {
      if (mounted) {
        setState(() => _downloadPercent = null);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Offline map download failed')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pct = _downloadPercent;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Map'),
        actions: [
          if (pct != null)
            Padding(
              padding: const EdgeInsets.all(14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, value: pct > 0 ? pct / 100 : null),
              ),
            )
          else
            IconButton(
              tooltip: _offlineReady ? 'Offline map saved' : 'Save map offline',
              icon: Icon(_offlineReady ? Icons.offline_pin : Icons.download_for_offline_outlined),
              onPressed: _offlineReady ? null : _saveOffline,
            ),
        ],
      ),
      body: Stack(
        children: [
          MapLibreMap(
            styleString: _style,
            initialCameraPosition: const CameraPosition(target: _cityCenter, zoom: 12),
            myLocationEnabled: _locationGranted,
            myLocationTrackingMode:
                _locationGranted ? MyLocationTrackingMode.trackingCompass : MyLocationTrackingMode.none,
            myLocationRenderMode:
                _locationGranted ? MyLocationRenderMode.compass : MyLocationRenderMode.normal,
            onMapCreated: (c) {
              _controller = c;
              c.onCircleTapped.add(_onPinTapped);
            },
            onStyleLoadedCallback: _addPins,
          ),
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Column(
              children: [
                Material(
                  elevation: 3,
                  borderRadius: BorderRadius.circular(14),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: 'Search establishments',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => setState(() {
                                _query = '';
                                _searchController.clear();
                              }),
                            ),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                if (_matches.isNotEmpty)
                  Material(
                    elevation: 3,
                    borderRadius: BorderRadius.circular(14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final e in _matches)
                          ListTile(
                            dense: true,
                            leading: Icon(
                              e.hasLocation ? Icons.place : Icons.location_off_outlined,
                              color: e.hasLocation ? Colors.red.shade700 : Colors.grey,
                            ),
                            title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(e.fullAddress, maxLines: 1, overflow: TextOverflow.ellipsis),
                            onTap: () => _goTo(e),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (_pinned.isEmpty)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                elevation: 3,
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('No establishments have map coordinates yet.', textAlign: TextAlign.center),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
