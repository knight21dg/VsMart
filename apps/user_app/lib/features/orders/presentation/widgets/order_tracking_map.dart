import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../location/data/route_service.dart';
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

/// Live delivery map — REAL data only.
///
/// This used to run a locally-simulated trip: a fabricated Bézier "route" with a
/// pretend rider driving it on a 38-second animation loop, every time the screen
/// opened, regardless of where the real rider was. A tracking screen that
/// animates fiction is worse than no tracking at all — so now:
///
///  • the route line is the actual road path from the backend `/geo/route`
///    proxy (a light dashed direct line stands in only until it resolves);
///  • the rider marker exists ONLY at real, backend-streamed GPS coordinates —
///    no position, no rider on the map;
///  • movement between real fixes is a short tween (the same smoothing real
///    courier apps use) — interpolation of truth, never invention;
///  • while a rider is live, the drawn route re-resolves from the rider's
///    position so the path ahead shrinks as they approach.
class OrderTrackingMap extends ConsumerStatefulWidget {
  const OrderTrackingMap({
    super.key,
    required this.store,
    required this.destination,
    required this.status,
    this.agentPosition,
    this.bottomPadding = 0,
    this.onEta,
  });

  /// The pickup point. NULL when the serving store has no coordinates — we then
  /// draw no pickup marker rather than inventing one.
  final LatLng? store;
  final LatLng destination;
  final OrderStatus status;

  /// Real, backend-streamed rider coordinates. The ONLY source of the rider
  /// marker — when null, no rider is drawn.
  final LatLng? agentPosition;

  /// Extra bottom map padding so the focus area sits above the bottom sheet.
  final double bottomPadding;

  /// Called with the live driving ETA text (e.g. "18 min") whenever the real
  /// route (re)resolves, so the screen can surface it. No-op if null.
  final void Function(String etaText)? onEta;

  @override
  ConsumerState<OrderTrackingMap> createState() => _OrderTrackingMapState();
}

class _OrderTrackingMapState extends ConsumerState<OrderTrackingMap>
    with TickerProviderStateMixin {
  GoogleMapController? _map;
  bool _iconsReady = false;

  /// The real road path (empty until `/geo/route` answers).
  List<LatLng> _road = const [];

  /// Tween between the previous and latest REAL rider fix — GPS arrives every
  /// ~15 s; snapping the marker across the gap looks broken, gliding it looks
  /// like the apps people know. The endpoints are always genuine coordinates.
  late final AnimationController _glide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..addListener(() => setState(() {}));
  LatLng? _glideFrom;
  LatLng? _glideTo;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  BitmapDescriptor? _riderIcon;
  BitmapDescriptor? _storeIcon;
  BitmapDescriptor? _homeIcon;

  DateTime _lastFollow = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastRouteLoad = DateTime.fromMillisecondsSinceEpoch(0);
  LatLng? _routeOrigin;

  @override
  void initState() {
    super.initState();
    _loadRoute();
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
    final pos = widget.agentPosition;
    if (pos != null && pos != old.agentPosition) {
      _onRiderFix(pos);
    }
  }

  /// A fresh REAL fix arrived: glide the marker there, gently follow with the
  /// camera, and re-resolve the road ahead when the rider has moved enough.
  void _onRiderFix(LatLng pos) {
    _glideFrom = _riderNow() ?? pos;
    _glideTo = pos;
    _glide.forward(from: 0);

    final now = DateTime.now();
    if (now.difference(_lastFollow).inSeconds >= 3) {
      _lastFollow = now;
      _map?.animateCamera(CameraUpdate.newLatLng(pos));
    }
    final movedM = _routeOrigin == null
        ? double.infinity
        : _distanceM(_routeOrigin!, pos);
    if (movedM > 120 && now.difference(_lastRouteLoad).inSeconds > 30) {
      _loadRoute();
    }
  }

  /// The rider's current display position — interpolated between the last two
  /// REAL fixes, never fabricated.
  LatLng? _riderNow() {
    final to = _glideTo ?? widget.agentPosition;
    if (to == null) return null;
    final from = _glideFrom;
    if (from == null || !_glide.isAnimating) return to;
    final t = Curves.easeInOut.transform(_glide.value);
    return LatLng(
      from.latitude + (to.latitude - from.latitude) * t,
      from.longitude + (to.longitude - from.longitude) * t,
    );
  }

  /// Road path + ETA from the backend. Origin = the live rider when present
  /// (the path AHEAD), else the store, else nothing worth drawing.
  Future<void> _loadRoute() async {
    final origin = widget.agentPosition ?? widget.store;
    if (origin == null) return;
    _lastRouteLoad = DateTime.now();
    _routeOrigin = origin;
    final r = await ref.read(routeServiceProvider).route(
          originLat: origin.latitude,
          originLng: origin.longitude,
          destLat: widget.destination.latitude,
          destLng: widget.destination.longitude,
        );
    if (!mounted) return;
    if (r.hasPath) {
      final pts = _decodePolyline(r.encodedPolyline);
      if (pts.length > 1) {
        setState(() => _road = pts);
        _fitOnce(pts);
      }
    }
    if (r.durationText.isNotEmpty) widget.onEta?.call(r.durationText);
  }

  bool _fitted = false;
  void _fitOnce(List<LatLng> pts) {
    if (_fitted || _map == null || pts.length < 2) return;
    _fitted = true;
    var minLat = pts.first.latitude, maxLat = pts.first.latitude;
    var minLng = pts.first.longitude, maxLng = pts.first.longitude;
    for (final p in pts) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }
    _map?.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      ),
      64,
    ));
  }

  Future<void> _prepareIcons(double dpr) async {
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

  @override
  void dispose() {
    _glide.dispose();
    _pulse.dispose();
    _map?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final rider = _riderNow();
    final anchor = rider ?? store ?? widget.destination;

    return GoogleMap(
      style: kCleanMapStyle,
      initialCameraPosition: CameraPosition(
        target: LatLng(
          (anchor.latitude + widget.destination.latitude) / 2,
          (anchor.longitude + widget.destination.longitude) / 2,
        ),
        zoom: 14,
      ),
      onMapCreated: (c) {
        _map = c;
        if (_road.length > 1) _fitOnce(_road);
      },
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: false,
      padding: EdgeInsets.only(bottom: widget.bottomPadding, top: 60),
      markers: {
        if (store != null)
          Marker(
            markerId: const MarkerId('store'),
            position: store,
            icon: _storeIcon ?? BitmapDescriptor.defaultMarker,
            anchor: const Offset(0.5, 0.5),
          ),
        Marker(
          markerId: const MarkerId('home'),
          position: widget.destination,
          icon: _homeIcon ?? BitmapDescriptor.defaultMarker,
          anchor: const Offset(0.5, 0.5),
        ),
        // The rider exists on this map ONLY at real coordinates.
        if (rider != null && widget.status != OrderStatus.delivered)
          Marker(
            markerId: const MarkerId('rider'),
            position: rider,
            icon: _riderIcon ?? BitmapDescriptor.defaultMarker,
            anchor: const Offset(0.5, 0.5),
            rotation: _glideFrom != null && _glideTo != null
                ? _bearing(_glideFrom!, _glideTo!)
                : _bearing(rider, widget.destination),
            flat: true,
          ),
      },
      circles: {
        if (rider != null && widget.status == OrderStatus.outForDelivery)
          Circle(
            circleId: const CircleId('pulse'),
            center: rider,
            radius: 16 + 22 * _pulse.value,
            fillColor:
                AppColors.vsGreen.withValues(alpha: 0.16 * (1 - _pulse.value)),
            strokeColor:
                AppColors.vsGreen.withValues(alpha: 0.35 * (1 - _pulse.value)),
            strokeWidth: 1,
          ),
      },
      polylines: {
        if (_road.length > 1)
          Polyline(
            polylineId: const PolylineId('road'),
            points: _road,
            color: AppColors.vsGreen,
            width: 5,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
          )
        else if (store != null || rider != null)
          // Honest placeholder while the road resolves: a light DASHED direct
          // line (clearly schematic), never a solid curve pretending to be one.
          Polyline(
            polylineId: const PolylineId('direct'),
            points: [rider ?? store!, widget.destination],
            color: AppColors.disabled,
            width: 3,
            patterns: [PatternItem.dash(14), PatternItem.gap(10)],
          ),
      },
    );
  }

  // ── geometry helpers ──
  static double _distanceM(LatLng a, LatLng b) {
    const r = 6371000.0;
    final p1 = a.latitude * math.pi / 180;
    final p2 = b.latitude * math.pi / 180;
    final dp = (b.latitude - a.latitude) * math.pi / 180;
    final dl = (b.longitude - a.longitude) * math.pi / 180;
    final h = math.sin(dp / 2) * math.sin(dp / 2) +
        math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
    return r * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  static double _bearing(LatLng a, LatLng b) {
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
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
