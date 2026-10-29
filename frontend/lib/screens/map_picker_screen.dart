import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_service.dart';
import '../services/hub_service.dart';
import '../theme/dm_surfaces.dart';
import '../theme/dm_theme.dart';
import '../widgets/dm_buttons.dart';
import '../widgets/dm_fields.dart';
import '../widgets/dm_screen.dart';

class ChosenPlace {
  final String address;
  final double latitude;
  final double longitude;
  const ChosenPlace(
      {required this.address, required this.latitude, required this.longitude});
}

class DmMapTesting {
  /// Disable network raster requests in widget tests only; gestures/coordinates
  /// still work. Never enabled by production app code.
  @visibleForTesting
  static bool disableNetworkTiles = false;
}

class MapPickerScreen extends StatefulWidget {
  final String title;
  final ChosenPlace? initial;
  const MapPickerScreen(
      {super.key, this.title = 'Choose pickup', this.initial});
  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  final _map = MapController();
  final _query = TextEditingController();
  final _address = TextEditingController();
  ChosenPlace? _pin;
  List<Map<String, dynamic>> _results = [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pin = widget.initial;
    _address.text = widget.initial?.address ?? '';
  }

  @override
  void dispose() {
    _map.dispose();
    _query.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_busy || _query.text.trim().length < 3) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final rows = await HubService.search(_query.text.trim());
      if (mounted) {
        setState(() {
          _results = rows;
          _busy = false;
          if (rows.isEmpty) {
            _error = 'No result. Tap a pin and enter the address manually.';
          }
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  void _select(LatLng point, {String address = ''}) {
    setState(() {
      _pin = ChosenPlace(
          address: address,
          latitude: point.latitude,
          longitude: point.longitude);
      _address.text = address;
      _results = [];
      _error = null;
    });
  }

  Future<void> _locate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw ApiException('Turn on phone Location, or choose a pin manually.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw ApiException(
            'Location permission was not granted. You can still choose a pin manually.');
      }
      final p = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 15)));
      if (!mounted) return;
      _map.move(LatLng(p.latitude, p.longitude), 16);
      _select(LatLng(p.latitude, p.longitude));
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is ApiException
            ? e.message
            : 'Could not obtain GPS. Tap the map to choose a location.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _lookupPin() async {
    final pin = _pin;
    if (pin == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final rows = await HubService.reverse(pin.latitude, pin.longitude);
      if (mounted && rows.isNotEmpty) {
        setState(() => _address.text = rows.first['address'].toString());
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final pin = _pin;
    return DmScreen(
        showBack: true,
        scroll: true,
        padding: EdgeInsets.zero,
        child: Column(children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title, style: dmHeading(size: 24)),
                    const SizedBox(height: 6),
                    Text('OpenStreetMap • search explicitly or tap a pin',
                        style: dmCaption()),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                          child: DmField(
                              controller: _query,
                              hint: 'Search area, landmark or address',
                              icon: Icons.search_rounded)),
                      const SizedBox(width: 8),
                      IconButton.filled(
                          onPressed: _busy ? null : _search,
                          icon: const Icon(Icons.search_rounded),
                          tooltip: 'Search places')
                    ]),
                    if (_error != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(_error!,
                              style: const TextStyle(fontSize: 11, color: danger))),
                  ])),
          if (_results.isNotEmpty)
            ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 160),
                child: ListView(shrinkWrap: true, children: [
                  for (final r in _results)
                    ListTile(
                        dense: true,
                        leading: const Icon(Icons.place_outlined),
                        title: Text(r['address'].toString(),
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        onTap: () {
                          final p = LatLng((r['latitude'] as num).toDouble(),
                              (r['longitude'] as num).toDouble());
                          _map.move(p, 16);
                          _select(p, address: r['address'].toString());
                        }),
                ])),
          SizedBox(
              height:
                  (MediaQuery.sizeOf(context).height * 0.43).clamp(230, 430),
              child: Stack(children: [
                FlutterMap(
                    mapController: _map,
                    options: MapOptions(
                        initialCenter: pin == null
                            ? const LatLng(22.7, 79.0)
                            : LatLng(pin.latitude, pin.longitude),
                        initialZoom: pin == null ? 4 : 15,
                        minZoom: 3,
                        maxZoom: 19,
                        onTap: (_, point) => _select(point)),
                    children: [
                      if (!DmMapTesting.disableNetworkTiles)
                        const OsmTiles(),
                      if (pin != null)
                        MarkerLayer(markers: [
                          Marker(
                              point: LatLng(pin.latitude, pin.longitude),
                              width: 48,
                              height: 55,
                              child: const Icon(Icons.location_pin,
                                  color: red, size: 48))
                        ]),
                    ]),
                Positioned(
                    top: 12,
                    right: 12,
                    child: FloatingActionButton.small(
                        heroTag: 'locate',
                        onPressed: _busy ? null : _locate,
                        tooltip: 'Use phone location',
                        child: const Icon(Icons.my_location_rounded))),
                const Positioned(bottom: 5, right: 6, child: OsmAttribution()),
                if (_busy)
                  const Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: LinearProgressIndicator()),
              ])),
          Container(
              padding: const EdgeInsets.fromLTRB(20, 13, 20, 18),
              decoration: dmSurface(radius: 0),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        pin == null
                            ? 'Tap the map to choose a location'
                            : '${pin.latitude.toStringAsFixed(5)}, ${pin.longitude.toStringAsFixed(5)}',
                        style: dmCaption(size: 11)),
                    const SizedBox(height: 8),
                    DmField(
                        controller: _address,
                        hint: 'Confirm address / landmark',
                        icon: Icons.edit_location_alt_outlined,
                        onChanged: (_) => setState(() {})),
                    if (pin != null)
                      TextButton(
                          onPressed: _busy ? null : _lookupPin,
                          child: const Text('Look up this pin’s address')),
                    const SizedBox(height: 8),
                    DmPrimaryButton(
                        label: 'Confirm location',
                        onPressed: pin != null &&
                                _address.text.trim().length >= 4 &&
                                !_busy
                            ? () => Navigator.pop(
                                context,
                                ChosenPlace(
                                    address: _address.text.trim(),
                                    latitude: pin.latitude,
                                    longitude: pin.longitude))
                            : null),
                  ])),
        ]));
  }
}

class OsmAttribution extends StatelessWidget {
  const OsmAttribution({super.key});
  @override
  Widget build(BuildContext context) => Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(5),
      child: InkWell(
          onTap: () => launchUrl(
              Uri.parse('https://www.openstreetmap.org/copyright'),
              mode: LaunchMode.externalApplication),
          child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              child: Text('© OpenStreetMap contributors',
                  style: TextStyle(color: Colors.black, fontSize: 9)))));
}

class TripMapPanel extends StatelessWidget {
  final double latitude;
  final double longitude;
  final double? driverLatitude;
  final double? driverLongitude;
  const TripMapPanel(
      {super.key,
      required this.latitude,
      required this.longitude,
      this.driverLatitude,
      this.driverLongitude});
  @override
  Widget build(BuildContext context) => ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
          height: 230,
          child: Stack(children: [
            FlutterMap(
                options: MapOptions(
                    initialCenter: LatLng(latitude, longitude),
                    initialZoom: 14,
                    maxZoom: 19,
                    interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all & ~InteractiveFlag.rotate)),
                children: [
                  if (!DmMapTesting.disableNetworkTiles)
                    const OsmTiles(),
                  MarkerLayer(markers: [
                    Marker(
                        point: LatLng(latitude, longitude),
                        width: 42,
                        height: 48,
                        child: const Icon(Icons.location_pin,
                            color: red, size: 42)),
                    if (driverLatitude != null && driverLongitude != null)
                      Marker(
                          point: LatLng(driverLatitude!, driverLongitude!),
                          width: 42,
                          height: 42,
                          child: Container(
                              decoration: BoxDecoration(
                                  color: Colors.black,
                                  borderRadius: BorderRadius.circular(12)),
                              child: const Icon(Icons.drive_eta_rounded,
                                  color: Colors.white, size: 25)))
                  ]),
                ]),
            const Positioned(bottom: 5, right: 5, child: OsmAttribution()),
          ])));
}


class OsmTiles extends StatelessWidget {
  const OsmTiles({super.key});
  @override Widget build(BuildContext context) {
    Theme.of(context);
    final layer=TileLayer(urlTemplate:'https://tile.openstreetmap.org/{z}/{x}/{y}.png',userAgentPackageName:'in.drivemate.app');
    if(!DmAppearance.instance.dark)return layer;
    // Client-side night palette, preserving attribution and original tile data.
    return ColorFiltered(colorFilter:const ColorFilter.matrix([
       .574,-1.43,-.144,0,255,
       -.426,-.43,-.144,0,255,
       -.426,-1.43,.856,0,255,
       0,0,0,1,0,
    ]),child:layer);
  }
}
