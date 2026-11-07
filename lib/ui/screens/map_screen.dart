import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../data/models/establishment.dart';
import '../../data/services/offline_service.dart';
import '../widgets/establishment_sheet.dart';

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
  StreamSubscription<BoxEvent>? _boxSub;
  Timer? _reloadDebounce;

  @override
  void initState() {
    super.initState();
    _all = OfflineService.getLocalEstablishments();
    _pinned = _all.where((e) => e.hasLocation).toList();
    // A sync writes thousands of rows and a pin writes one; both land on the
    // map through this, debounced so the sync redraws once.
    _boxSub = Hive.box<Establishment>(OfflineService.establishmentsBoxName).watch().listen((_) {
      _reloadDebounce?.cancel();
      _reloadDebounce = Timer(const Duration(milliseconds: 600), _reloadPins);
    });
    Permission.locationWhenInUse.request().then((s) {
      if (mounted) setState(() => _locationGranted = s.isGranted);
    });
    getListOfRegions().then((regions) {
      if (mounted) setState(() => _offlineReady = regions.isNotEmpty);
    }).catchError((_) {});
  }

  bool _reloading = false;
  bool _reloadQueued = false;

  /// One redraw at a time: overlapping clear/add pairs leave duplicate pins.
  Future<void> _reloadPins() async {
    if (_reloading) {
      _reloadQueued = true;
      return;
    }
    _reloading = true;
    try {
      if (!mounted) return;
      setState(() {
        _all = OfflineService.getLocalEstablishments();
        _pinned = _all.where((e) => e.hasLocation).toList();
      });
      await _controller?.clearCircles();
      await _addPins();
    } catch (e) {
      debugPrint('pin redraw failed: $e');
    } finally {
      _reloading = false;
    }
    if (_reloadQueued) {
      _reloadQueued = false;
      await _reloadPins();
    }
  }

  /// Pans to the GPS dot. Tracking is off (see the map options), so the camera
  /// only moves when the inspector asks.
  Future<void> _recenter() async {
    LatLng? here;
    try {
      here = await _controller?.requestMyLocationLatLng();
      if (here != null) await _controller?.animateCamera(CameraUpdate.newLatLngZoom(here, 16));
    } catch (_) {
      here = null; // style still loading or location component not up yet
    }
    if (here == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No GPS fix yet. Move to an open space and try again.')),
      );
    }
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
    _boxSub?.cancel();
    _reloadDebounce?.cancel();
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
    if (mounted) showEstablishmentSheet(context, est);
  }

  void _onPinTapped(Circle circle) {
    final id = circle.data?['id'];
    final est = _pinned.cast<Establishment?>().firstWhere((e) => e!.id == id, orElse: () => null);
    if (est == null) return;
    showEstablishmentSheet(context, est);
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
            // Never track: a tracking camera snaps back to the GPS dot after
            // every pan and every animateCamera() to a pin, which read as the
            // map "bouncing". The locate button below pans on request instead.
            myLocationTrackingMode: MyLocationTrackingMode.none,
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
          if (_locationGranted)
            Positioned(
              right: 16,
              bottom: 16 + MediaQuery.paddingOf(context).bottom,
              child: FloatingActionButton.small(
                heroTag: 'map-locate',
                tooltip: 'My location',
                onPressed: _recenter,
                child: const Icon(Icons.my_location),
              ),
            ),
          if (_pinned.isEmpty)
            Positioned(
              left: 16,
              right: 72,
              // The shell extends the body under its bar; Scaffold reports the
              // bar height as bottom padding here.
              bottom: 16 + MediaQuery.paddingOf(context).bottom,
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
