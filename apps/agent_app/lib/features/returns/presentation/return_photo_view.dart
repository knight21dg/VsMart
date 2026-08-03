import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth_image.dart';
import '../../../core/providers.dart';
import '../../../core/ui.dart';
import '../data/returns_data.dart';

/// Square thumbnail for a return photo. The endpoint is permission-gated, so it
/// goes through [AuthImage] (a plain Image.network would 403).
class ReturnPhotoThumb extends ConsumerWidget {
  const ReturnPhotoThumb({super.key, required this.photo});
  final ReturnPhoto photo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Stack(
      fit: StackFit.expand,
      children: [
        AuthImage(
          api: ref.read(apiProvider),
          path: photo.path,
          height: 96,
        ),
        Positioned(
          left: 4,
          bottom: 4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: (photo.isCustomer ? AgentColors.brand : AgentColors.green)
                  .withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              photo.isCustomer ? 'CUSTOMER' : 'YOURS',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }
}

/// Full-screen view of a single return photo.
class ReturnPhotoView extends ConsumerWidget {
  const ReturnPhotoView({super.key, required this.photo});
  final ReturnPhoto photo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(photo.isCustomer ? "Customer's photo" : 'Your photo'),
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 4,
          child: AuthImage(
            api: ref.read(apiProvider),
            path: photo.path,
            height: MediaQuery.of(context).size.height * 0.7,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
