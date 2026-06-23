import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../domain/entities/order_enums.dart';

/// Clean, muted "Swiggy-style" Google Maps style (fewer POIs/labels, soft land,
/// highlighted water). Applied to the map so it reads calm, not busy.
const String kCleanMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#f5f5f5"}]},
  {"elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#8a8a8a"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#f5f5f5"}]},
  {"featureType":"administrative.land_parcel","stylers":[{"visibility":"off"}]},
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#e6f0e0"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#ffffff"}]},
  {"featureType":"road.arterial","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#ffe9c7"}]},
  {"featureType":"road.local","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#bcdffb"}]}
]
''';

/// Live delivery map. Renders a styled Google Map with a curved store→address
/// route, an animated rotating rider, a completed(brand)/remaining(grey)
/// polyline split, a pulsing rider halo, and a camera that follows the rider.
///
/// Route + movement are simulated locally (a smooth curve + progress driven by
/// the order status). Swap [store]/[destination]/progress for a real Directions
/// polyline + live GPS when that backend exists.
class OrderTrackingMap extends StatefulWidget {
  const OrderTrackingMap({
    super.key,
    required this.store,
    required this.destination,
    required this.status,
    this.agentPosition,
    this.bottomPadding = 0,
  });

  final LatLng store;
  final LatLng destination;
  final OrderStatus status;

  /// Real, backend-streamed agent coordinates. When present the rider marker is
  /// pinned to this live position instead of the simulated route position.
  final LatLng? agentPosition;

  /// Extra bottom map padding so the rider sits above the bottom sheet.
  final double bottomPadding;

  @override
  State<OrderTrackingMap> createState() => _OrderTrackingMapState();
}

class _OrderTrackingMapState extends State<OrderTrackingMap>
    with TickerProviderStateMixin {
  GoogleMapController? _map;
  late List<LatLng> _route = _buildRoute(widget.store, widget.destination);
  bool _iconsReady = false;
  late final AnimationController _ride = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 38),
  );
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  BitmapDescriptor? _riderIcon;
  BitmapDescriptor? _storeIcon;
  BitmapDescriptor? _homeIcon;
  DateTime _lastCam = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _ride.addListener(_onTick);
    _driveForStatus();
    _loadDirections();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_iconsReady) {
      _iconsReady = true;
      _prepareIcons(MediaQuery.devicePixelRatioOf(context));
    }
  }

  @override
  void didUpdateWidget(covariant OrderTrackingMap old) {
    super.didUpdateWidget(old);
    if (old.status != widget.status) _driveForStatus();
  }

  void _driveForStatus() {
    switch (widget.status) {
      case OrderStatus.delivered:
        _ride.value = 1.0;
      case OrderStatus.outForDelivery:
        if (!_ride.isAnimating) {
          _ride.animateTo(0.92,
              duration: const Duration(seconds: 38), curve: Curves.easeInOut);
        }
      case OrderStatus.packed:
        _ride.value = 0.12;
      default:
        _ride.value = 0.04;
    }
  }

  Future<void> _prepareIcons(double dpr) async {
    // Small, minimalist markers (logical dp sizes; rendered at dpr for crispness).
    final rider = await _circleGlyph(
        Icons.two_wheeler_rounded, AppColors.vsGreen, 44, dpr);
    final store = await _circleGlyph(
        Icons.storefront_rounded, AppColors.offerOrange, 34, dpr);
    final home = await _circleGlyph(
        Icons.home_rounded, AppColors.trustBlue, 34, dpr);
    if (!mounted) return;
    setState(() {
      _riderIcon = rider;
      _storeIcon = store;
      _homeIcon = home;
    });
  }

  /// Fetch a real road-following route from the Google Directions API (key via
  /// `--dart-define=MAPS_API_KEY`). Falls back to the local curved path on any
  /// failure (no key, key restricted to Android apps, network error, etc.).
  Future<void> _loadDirections() async {
    const key = String.fromEnvironment('MAPS_API_KEY');
    if (key.isEmpty) return;
    try {
      final res = await Dio().get<dynamic>(
        'https://maps.googleapis.com/maps/api/directions/json',
        queryParameters: {
          'origin': '${widget.store.latitude},${widget.store.longitude}',
          'destination':
              '${widget.destination.latitude},${widget.destination.longitude}',
          'mode': 'driving',
          'key': key,
        },
      );
      final data = res.data;
      if (data is Map && data['status'] == 'OK') {
        final routes = data['routes'] as List?;
        String? enc;
        if (routes != null && routes.isNotEmpty) {
          final poly = (routes.first as Map?)?['overview_polyline'] as Map?;
          enc = poly?['points'] as String?;
        }
        if (enc != null && enc.isNotEmpty) {
          final pts = _decodePolyline(enc);
          if (pts.length > 1 && mounted) setState(() => _route = pts);
        }
      }
    } catch (_) {/* keep the curved fallback */}
  }

  /// Decode a Google "encoded polyline" string into coordinates.
  static List<LatLng> _decodePolyline(String encoded) {
    final points = <LatLng>[];
    var index = 0, lat = 0, lng = 0;
    while (index < encoded.length) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }

  void _onTick() {
    setState(() {});
    // Throttle camera follow so we don't spam animateCamera every frame.
    if (widget.status == OrderStatus.outForDelivery) {
      final now = DateTime.now();
      if (now.difference(_lastCam).inMilliseconds > 700) {
        _lastCam = now;
        _map?.animateCamera(CameraUpdate.newLatLng(_riderPos()));
      }
    }
  }

  int get _idx {
    final i = (_ride.value * (_route.length - 1)).floor();
    return i.clamp(0, _route.length - 2);
  }

  LatLng _riderPos() {
    final i = _idx;
    final frac = (_ride.value * (_route.length - 1)) - i;
    return _lerp(_route[i], _route[i + 1], frac);
  }

  @override
  void dispose() {
    _ride.dispose();
    _pulse.dispose();
    _map?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Pin the rider to the real backend position when streaming; else animate.
    final rider = widget.agentPosition ?? _riderPos();
    final i = _idx;
    final riderBearing = widget.agentPosition != null
        ? _bearing(widget.agentPosition!, widget.destination)
        : _bearing(_route[i], _route[i + 1]);
    final completed = _route.sublist(0, i + 2);
    final remaining = _route.sublist(i + 1);

    return GoogleMap(
      style: kCleanMapStyle,
      initialCameraPosition: CameraPosition(
        target: _mid(widget.store, widget.destination),
        zoom: 13.5,
      ),
      onMapCreated: (c) {
        _map = c;
        _fitRoute();
      },
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: false,
      padding: EdgeInsets.only(bottom: widget.bottomPadding, top: 60),
      markers: {
        Marker(
          markerId: const MarkerId('store'),
          position: widget.store,
          icon: _storeIcon ?? BitmapDescriptor.defaultMarker,
          anchor: const Offset(0.5, 0.5),
        ),
        Marker(
          markerId: const MarkerId('home'),
          position: widget.destination,
          icon: _homeIcon ?? BitmapDescriptor.defaultMarker,
          anchor: const Offset(0.5, 0.5),
        ),
        if (widget.status != OrderStatus.delivered)
          Marker(
            markerId: const MarkerId('rider'),
            position: rider,
            icon: _riderIcon ?? BitmapDescriptor.defaultMarker,
            anchor: const Offset(0.5, 0.5),
            rotation: riderBearing,
            flat: true,
          ),
      },
      circles: {
        if (widget.status == OrderStatus.outForDelivery)
          Circle(
            circleId: const CircleId('pulse'),
            center: rider,
            radius: 18 + 26 * _pulse.value,
            fillColor: AppColors.vsGreen.withValues(alpha: 0.18 * (1 - _pulse.value)),
            strokeColor: AppColors.vsGreen.withValues(alpha: 0.4 * (1 - _pulse.value)),
            strokeWidth: 1,
          ),
      },
      polylines: {
        Polyline(
          polylineId: const PolylineId('remaining'),
          points: remaining,
          color: AppColors.disabled,
          width: 6,
          patterns: [PatternItem.dash(18), PatternItem.gap(10)],
        ),
        Polyline(
          polylineId: const PolylineId('completed'),
          points: completed,
          color: AppColors.vsGreen,
          width: 7,
        ),
      },
    );
  }

  void _fitRoute() {
    final sw = LatLng(
      math.min(widget.store.latitude, widget.destination.latitude),
      math.min(widget.store.longitude, widget.destination.longitude),
    );
    final ne = LatLng(
      math.max(widget.store.latitude, widget.destination.latitude),
      math.max(widget.store.longitude, widget.destination.longitude),
    );
    Future.delayed(const Duration(milliseconds: 300), () {
      _map?.animateCamera(
        CameraUpdate.newLatLngBounds(
            LatLngBounds(southwest: sw, northeast: ne), 64),
      );
    });
  }

  // ── geometry helpers ──
  static LatLng _lerp(LatLng a, LatLng b, double t) => LatLng(
        a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t,
      );

  static LatLng _mid(LatLng a, LatLng b) => _lerp(a, b, 0.5);

  static double _bearing(LatLng a, LatLng b) {
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  /// A gentle curved path (quadratic Bézier with a perpendicular control offset)
  /// so the route doesn't look like a straight line.
  static List<LatLng> _buildRoute(LatLng a, LatLng b, {int n = 90}) {
    final mLat = (a.latitude + b.latitude) / 2;
    final mLng = (a.longitude + b.longitude) / 2;
    final dLat = b.latitude - a.latitude;
    final dLng = b.longitude - a.longitude;
    final cLat = mLat - dLng * 0.16; // perpendicular offset → curve
    final cLng = mLng + dLat * 0.16;
    double bez(double p0, double p1, double p2, double t) {
      final u = 1 - t;
      return u * u * p0 + 2 * u * t * p1 + t * t * p2;
    }

    return [
      for (var i = 0; i <= n; i++)
        LatLng(bez(a.latitude, cLat, b.latitude, i / n),
            bez(a.longitude, cLng, b.longitude, i / n)),
    ];
  }

  /// Renders a MaterialIcons glyph inside a small coloured circle → a minimalist
  /// map-marker bitmap (no asset). [sizeDp] is the on-screen size; the bitmap is
  /// drawn at [dpr]× for crispness and tagged with imagePixelRatio so it shows
  /// at [sizeDp].
  static Future<BitmapDescriptor> _circleGlyph(
      IconData icon, Color color, double sizeDp, double dpr) async {
    final px = sizeDp * dpr;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final c = Offset(px / 2, px / 2);
    canvas.drawCircle(c, px / 2, Paint()..color = Colors.white);
    canvas.drawCircle(c, px / 2 - dpr * 2, Paint()..color = color);
    final tp = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: px * 0.5,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: Colors.white,
        ),
      )
      ..layout();
    tp.paint(canvas, Offset((px - tp.width) / 2, (px - tp.height) / 2));
    final img =
        await recorder.endRecording().toImage(px.round(), px.round());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List(),
        imagePixelRatio: dpr);
  }
}
