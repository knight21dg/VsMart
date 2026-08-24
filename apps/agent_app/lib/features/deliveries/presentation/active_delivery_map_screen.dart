import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/route_service.dart';
import '../../../core/ui.dart';
import '../data/deliveries_data.dart';
import 'deliveries_providers.dart';

/// Full-screen live navigation view for the delivery in hand.
///
/// Opens when the agent goes OUT FOR DELIVERY (and from the detail screen while
/// the trip is active): the whole screen is the map — destination pin, the real
/// road route from the backend `/geo/route` proxy, and the rider's live position
/// with a follow camera — with the trip's operations on a bottom card: call the
/// customer, hand off to Google Maps turn-by-turn, and "I've Arrived" (the 50 m
/// geofence stays server-enforced). Once arrival is confirmed the handover steps
/// (OTP → proof photo → complete) continue on the detail screen, which stays
/// right below this one.
class ActiveDeliveryMapScreen extends ConsumerStatefulWidget {
  const ActiveDeliveryMapScreen({
    super.key,
    required this.taskId,
    required this.onArrive,
  });

  final String taskId;

  /// The detail screen's arrive handler (GPS fix + `/arrive` + error surface) —
  /// the map screen drives it, the owner keeps the single implementation.
  final Future<void> Function() onArrive;

  @override
  ConsumerState<ActiveDeliveryMapScreen> createState() =>
      _ActiveDeliveryMapScreenState();
}

class _ActiveDeliveryMapScreenState
    extends ConsumerState<ActiveDeliveryMapScreen> {
  GoogleMapController? _map;
  StreamSubscription<Position>? _positions;
  Timer? _routeTimer;

  LatLng? _me;
  LatLng? _lastRouteOrigin;
  RouteResult _route = const RouteResult();
  bool _follow = true;
  bool _busy = false;

  // The road ahead shrinks as the rider moves — refresh the drawn route (and
  // the ETA chip) as they actually cover ground, not on a fixed clock. A
  // flat 45s timer either lagged well behind a fast-moving rider or wastefully
  // re-fetched (a real, billed Directions call) someone stuck at a signal.
  // The 90s backstop only covers a rider who hasn't moved — traffic-driven ETA
  // drift with no GPS movement at all.
  static const _routeRefreshMeters = 120.0;

  @override
  void initState() {
    super.initState();
    _startFollowingMyPosition();
    _routeTimer = Timer.periodic(
        const Duration(seconds: 90), (_) => _loadRoute());
  }

  @override
  void dispose() {
    _positions?.cancel();
    _routeTimer?.cancel();
    _map?.dispose();
    super.dispose();
  }

  AgentDelivery? get _delivery =>
      ref.read(deliveryDetailProvider(widget.taskId)).valueOrNull;

  Future<void> _startFollowingMyPosition() async {
    final ok = await ref.read(locationServiceProvider).ready();
    if (!ok || !mounted) return;
    _positions = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 8, // metres between updates — smooth but not chatty
      ),
    ).listen((p) {
      if (!mounted) return;
      final here = LatLng(p.latitude, p.longitude);
      final first = _me == null;
      setState(() => _me = here);
      final origin = _lastRouteOrigin;
      final moved = origin == null ||
          Geolocator.distanceBetween(
                origin.latitude, origin.longitude, here.latitude, here.longitude,
              ) >= _routeRefreshMeters;
      if (first || moved) _loadRoute();
      if (_follow) {
        _map?.animateCamera(CameraUpdate.newCameraPosition(
          CameraPosition(target: here, zoom: 16.5),
        ));
      }
    });
  }

  Future<void> _loadRoute() async {
    final d = _delivery;
    final me = _me;
    if (d == null || me == null || d.destLat == null || d.destLng == null) {
      return;
    }
    _lastRouteOrigin = me;
    final r = await ref.read(routeServiceProvider).route(
          originLat: me.latitude,
          originLng: me.longitude,
          destLat: d.destLat!,
          destLng: d.destLng!,
        );
    if (mounted && r.hasPath) setState(() => _route = r);
  }

  Future<void> _arrive() async {
    setState(() => _busy = true);
    try {
      await widget.onArrive();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _navigateExternal(AgentDelivery d) async {
    if (d.destLat == null || d.destLng == null) return;
    // google.navigation launches true turn-by-turn; fall back to the maps URL.
    final nav = Uri.parse('google.navigation:q=${d.destLat},${d.destLng}');
    if (await canLaunchUrl(nav)) {
      await launchUrl(nav);
      return;
    }
    final opened = await launchUrl(
      Uri.parse('https://www.google.com/maps/dir/?api=1'
          '&destination=${d.destLat},${d.destLng}'),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      showToast(context, 'Could not open navigation for this delivery', error: true);
    }
  }

  Future<void> _call(AgentDelivery d) async {
    final uri = Uri.parse('tel:${d.customerPhone}');
    if (!await launchUrl(uri)) {
      if (mounted) {
        showToast(context, 'Could not start a call to ${d.customerPhone}',
            error: true);
      }
    }
  }

  void _fitBoth(AgentDelivery d) {
    final me = _me;
    final map = _map;
    if (map == null || me == null || d.destLat == null || d.destLng == null) {
      return;
    }
    setState(() => _follow = false);
    map.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(
          me.latitude < d.destLat! ? me.latitude : d.destLat!,
          me.longitude < d.destLng! ? me.longitude : d.destLng!,
        ),
        northeast: LatLng(
          me.latitude > d.destLat! ? me.latitude : d.destLat!,
          me.longitude > d.destLng! ? me.longitude : d.destLng!,
        ),
      ),
      72,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(deliveryDetailProvider(widget.taskId));
    final d = async.valueOrNull;
    if (d == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final dest = (d.destLat != null && d.destLng != null)
        ? LatLng(d.destLat!, d.destLng!)
        : null;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: dest == null
                ? _NoDestination(address: d.address)
                : GoogleMap(
                    initialCameraPosition:
                        CameraPosition(target: _me ?? dest, zoom: 15),
                    onMapCreated: (c) => _map = c,
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    compassEnabled: true,
                    zoomControlsEnabled: false,
                    // A drag means the rider wants to look around — stop
                    // snapping the camera back until they re-enable follow.
                    onCameraMoveStarted: () {
                      if (_follow) setState(() => _follow = false);
                    },
                    markers: {
                      Marker(
                        markerId: const MarkerId('dest'),
                        position: dest,
                        infoWindow: InfoWindow(
                            title: d.customerName, snippet: d.address),
                      ),
                    },
                    polylines: {
                      if (_route.hasPath)
                        Polyline(
                          polylineId: const PolylineId('route'),
                          points: _route.points,
                          width: 5,
                          color: AgentColors.brand,
                          startCap: Cap.roundCap,
                          endCap: Cap.roundCap,
                        ),
                    },
                  ),
          ),

          // ── Top bar: back + live trip chip ──
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _RoundButton(
                    icon: Icons.arrow_back,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  if (_route.durationText.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: const [
                          BoxShadow(
                              color: Colors.black26, blurRadius: 6),
                        ],
                      ),
                      child: Text(
                        '${_route.durationText}'
                        '${_route.distanceText.isNotEmpty ? ' · ${_route.distanceText}' : ''}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ── Map controls ──
          Positioned(
            right: 12,
            bottom: 236,
            child: Column(
              children: [
                _RoundButton(
                  icon: Icons.zoom_out_map,
                  onTap: () => _fitBoth(d),
                ),
                const SizedBox(height: 10),
                _RoundButton(
                  icon: _follow ? Icons.gps_fixed : Icons.gps_not_fixed,
                  active: _follow,
                  onTap: () {
                    setState(() => _follow = true);
                    final me = _me;
                    if (me != null) {
                      _map?.animateCamera(CameraUpdate.newCameraPosition(
                        CameraPosition(target: me, zoom: 16.5),
                      ));
                    }
                  },
                ),
              ],
            ),
          ),

          // ── Bottom operations card ──
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 10),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor:
                              AgentColors.brand.withValues(alpha: 0.12),
                          child: const Icon(Icons.person_pin_circle_outlined,
                              color: AgentColors.brand),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(d.customerName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15)),
                              Text(
                                d.address,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: Colors.grey.shade700, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => _call(d),
                          icon: const Icon(Icons.call_outlined),
                          style: IconButton.styleFrom(
                            backgroundColor:
                                AgentColors.brand.withValues(alpha: 0.1),
                            foregroundColor: AgentColors.brand,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _navigateExternal(d),
                            icon: const Icon(Icons.navigation_outlined),
                            label: const Text('Navigate'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: switch (d.status) {
                            'out_for_delivery' => FilledButton.icon(
                                onPressed: _busy ? null : _arrive,
                                icon: _busy
                                    ? const SizedBox(
                                        height: 16,
                                        width: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white),
                                      )
                                    : const Icon(
                                        Icons.where_to_vote_outlined),
                                label: const Text("I've Arrived"),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(48),
                                  backgroundColor: AgentColors.brand,
                                ),
                              ),
                            'reached' => FilledButton.icon(
                                // OTP + proof photo + complete live on the
                                // detail screen right below this one.
                                onPressed: () =>
                                    Navigator.of(context).pop(),
                                icon: const Icon(
                                    Icons.assignment_turned_in_outlined),
                                label: const Text('Handover'),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(48),
                                  backgroundColor: AgentColors.brand,
                                ),
                              ),
                            _ => FilledButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(48),
                                ),
                                child: const Text('Back to details'),
                              ),
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton(
      {required this.icon, required this.onTap, this.active = false});

  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? AgentColors.brand : Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          height: 44,
          width: 44,
          child: Icon(icon,
              size: 20, color: active ? Colors.white : Colors.black87),
        ),
      ),
    );
  }
}

class _NoDestination extends StatelessWidget {
  const _NoDestination({required this.address});

  final String address;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey.shade100,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.location_off_outlined,
              size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          const Text('This address has no map pin',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(address,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700)),
        ],
      ),
    );
  }
}
