import 'package:flutter/material.dart';

import '../../../core/ui.dart';
import '../../kyc/presentation/kyc_queue_screen.dart';
import '../../notifications/presentation/notification_bell.dart';
import 'verification_tasks_screen.dart';

/// The "Verify" bottom-nav tab: a TabBar with two sub-tabs —
/// "Field Tasks" (field-verification visits) and "KYC Review" (the document
/// review queue). The notifications bell lives in this app bar too.
class VerifyScreen extends StatelessWidget {
  const VerifyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Verify'),
          actions: const [NotificationBell()],
          bottom: const TabBar(
            labelColor: AgentColors.brand,
            unselectedLabelColor: AgentColors.textSecondary,
            indicatorColor: AgentColors.brand,
            tabs: [
              Tab(text: 'Field Tasks'),
              Tab(text: 'KYC Review'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            VerificationTasksScreen(),
            KycQueueBody(),
          ],
        ),
      ),
    );
  }
}
