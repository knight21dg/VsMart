import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../features/deliveries/presentation/deliveries_providers.dart'
    show locationServiceProvider;
import 'route_service.dart';
import 'ui.dart';

/// A small embedded Google Map for a single destination (a delivery drop or a
/// collection visit). Draws the **real road route** from the agent's current
/// location to the target (via the backend `/geo/route` proxy) with a live ETA +
/// distance chip, plus the target marker and the agent's live-location dot. Falls
/// back to a marker-only view when the route can't be resolved (no key / offline /
/// no GPS). Turn-by-turn still hands off to the Google Maps app from the screen.
class DestinationMap extends ConsumerStatefulWidget {
  const DestinationMap({
    super.key,
    required this.lat,
    required this.lng,
    this.label = 'Destination',
    this.height = 180,
  });

  final double lat;
  final double lng;
  final String label;
  final double height;

  @override
  ConsumerState<DestinationMap> createState() => _DestinationMapState();
}

class _DestinationMapState extends ConsumerState<DestinationMap> {
  GoogleMapController? _controller;
  RouteResult _route = const RouteResult();

  @override
  void initState() {
    super.initState();
    _loadRoute();
  }

  Future<void> _loadRoute() async {
    final fix = await ref.read(locationServiceProvider).current();
    if (fix == null || !mounted) return;
    final r = await ref.read(routeServiceProvider).route(
          originLat: fix.latitude,
          originLng: fix.longitude,
          destLat: widget.lat,
          destLng: widget.lng,
        );
    if (!mounted || !r.hasPath) return;
    setState(() => _route = r);
    _fitRoute(r.points);
  }

  void _fitRoute(List<LatLng> pts) {
    final c = _controller;
    if (c == null || pts.length < 2) return;
    var minLat = pts.first.latitude, maxLat = pts.first.latitude;
    var minLng = pts.first.longitude, maxLng = pts.first.longitude;
    for (final p in pts) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    c.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      ),
      40,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final target = LatLng(widget.lat, widget.lng);
    final eta = [
      if (_route.durationText.isNotEmpty) _route.durationText,
      if (_route.distanceText.isNotEmpty) _route.distanceText,
    ].join('  ·  ');

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(target: target, zoom: 15),
              markers: {
                Marker(
                  markerId: const MarkerId('dest'),
                  position: target,
                  icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                  infoWindow: InfoWindow(title: widget.label),
                ),
              },
              polylines: {
                if (_route.hasPath)
                  Polyline(
                    polylineId: const PolylineId('route'),
                    points: _route.points,
                    color: AgentColors.brand,
                    width: 5,
                  ),
              },
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              compassEnabled: false,
              onMapCreated: (c) {
                _controller = c;
                if (_route.hasPath) _fitRoute(_route.points);
              },
            ),
            if (eta.isNotEmpty)
              Positioned(
                left: 10,
                top: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AgentColors.brand,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 2)),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.navigation_rounded, size: 14, color: Colors.white),
                      const SizedBox(width: 5),
                      Text(eta,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
