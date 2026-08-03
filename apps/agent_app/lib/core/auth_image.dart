import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';

/// Loads an image from an **auth-gated** endpoint (bearer token via [Api]) and
/// renders it — used for KYC document images, which are served only to reviewers
/// on a protected path (a plain `Image.network` would 403). Bytes are fetched
/// once and cached for the widget's lifetime.
class AuthImage extends StatefulWidget {
  const AuthImage({
    super.key,
    required this.api,
    required this.path,
    this.height = 180,
    this.fit = BoxFit.cover,
  });

  final Api api;
  final String path;
  final double height;
  final BoxFit fit;

  @override
  State<AuthImage> createState() => _AuthImageState();
}

class _AuthImageState extends State<AuthImage> {
  late Future<Uint8List> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Uint8List> _load() async =>
      Uint8List.fromList(await widget.api.bytes(widget.path));

  void _retry() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: FutureBuilder<Uint8List>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const _Box(child: CircularProgressIndicator(strokeWidth: 2));
          }
          if (snap.hasError || snap.data == null || snap.data!.isEmpty) {
            return _Box(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.broken_image_outlined,
                      color: AgentColors.textSecondary),
                  TextButton(onPressed: _retry, child: const Text('Retry')),
                ],
              ),
            );
          }
          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(snap.data!, fit: widget.fit,
                width: double.infinity, height: widget.height),
          );
        },
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: AgentColors.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AgentColors.border),
        ),
        alignment: Alignment.center,
        child: child,
      );
}
