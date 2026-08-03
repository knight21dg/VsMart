import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/ui.dart';
import '../data/batch_data.dart';

/// An embedded Google Map of the agent's trip: the store pickup, the sequenced
/// stops (coloured by status), a dashed line in route order, and the agent's live
/// location. Navigation itself still hands off to the Google Maps app from each
/// stop; this gives the rider the whole route at a glance.
class RouteMap extends StatefulWidget {
  const RouteMap({super.key, required this.batch, this.height = 220});

  final RouteBatch batch;
  final double height;

  @override
  State<RouteMap> createState() => _RouteMapState();
}

class _RouteMapState extends State<RouteMap> {
  GoogleMapController? _controller;

  @override
  Widget build(BuildContext context) {
    final b = widget.batch;
    final markers = <Marker>{};
    final points = <LatLng>[];

    if (b.storeLat != null && b.storeLng != null) {
      final p = LatLng(b.storeLat!, b.storeLng!);
      points.add(p);
      markers.add(Marker(
        markerId: const MarkerId('store'),
        position: p,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: InfoWindow(title: 'Pickup: ${b.storeName}'),
      ));
    }

    for (final s in b.stops) {
      if (s.lat == null || s.lng == null) continue;
      final p = LatLng(s.lat!, s.lng!);
      points.add(p);
      final hue = s.status == 'done'
          ? BitmapDescriptor.hueGreen
          : s.status == 'failed'
              ? BitmapDescriptor.hueRed
              : BitmapDescriptor.hueOrange;
      markers.add(Marker(
        markerId: MarkerId('stop-${s.sequence}'),
        position: p,
        icon: BitmapDescriptor.defaultMarkerWithHue(hue),
        infoWindow: InfoWindow(
          title: '${s.sequence}. ${s.isDelivery ? s.label : 'Collect ${s.label}'}',
          snippet: s.address.isNotEmpty ? s.address : null,
        ),
      ));
    }

    if (points.isEmpty) return const SizedBox.shrink();

    final routeLine = <LatLng>[
      if (b.storeLat != null && b.storeLng != null) LatLng(b.storeLat!, b.storeLng!),
      for (final s in b.stops)
        if (s.lat != null && s.lng != null) LatLng(s.lat!, s.lng!),
    ];
    final polylines = <Polyline>{
      if (routeLine.length >= 2)
        Polyline(
          polylineId: const PolylineId('route'),
          points: routeLine,
          color: AgentColors.brand,
          width: 4,
          patterns: [PatternItem.dash(20), PatternItem.gap(10)],
        ),
    };

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: widget.height,
        child: GoogleMap(
          initialCameraPosition: CameraPosition(target: points.first, zoom: 12),
          markers: markers,
          polylines: polylines,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          compassEnabled: false,
          onMapCreated: (c) {
            _controller = c;
            _fitBounds(points);
          },
        ),
      ),
    );
  }

  void _fitBounds(List<LatLng> points) {
    final c = _controller;
    if (c == null || points.isEmpty) return;
    if (points.length == 1) {
      c.moveCamera(CameraUpdate.newLatLngZoom(points.first, 14));
      return;
    }
    var minLat = points.first.latitude, maxLat = points.first.latitude;
    var minLng = points.first.longitude, maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
    // Padding in logical pixels around the bounded points.
    c.animateCamera(CameraUpdate.newLatLngBounds(bounds, 48));
  }
}
