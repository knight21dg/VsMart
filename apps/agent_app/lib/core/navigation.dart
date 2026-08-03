import 'package:flutter/material.dart';

/// Lets code outside the widget tree (a push-notification tap) open a screen
/// regardless of which tab is currently active — there's no go_router here,
/// so this is the app's only handle on navigation from PushController.
final rootNavigatorKey = GlobalKey<NavigatorState>();
