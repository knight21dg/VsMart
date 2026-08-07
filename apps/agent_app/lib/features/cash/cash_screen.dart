import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/net_errors.dart';
import '../../core/ui.dart';
import 'cash_data.dart';
import 'cash_providers.dart';

/// Cash tab — what the agent is holding, and how they hand it over.
///
/// Closes the last gap in the cash chain: money was collected from customers
/// and the credit ledger repaid, but nothing recorded what happened to the
/// physical notes afterwards. Until it's handed over and counted, it shows here
/// as the agent's responsibility.
class CashScreen extends ConsumerWidget {
  const CashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(cashSummaryProvider);
    return Scaffold(
      backgroundColor: AgentColors.bg,
      appBar: AppBar(title: const Text('Cash')),
      body: async.when(
        loading: () => const Loading(),
        error: (e, _) => ErrorRetry(
          message: describeFailure(e, fallback: 'Could not load your cash.').display,
          onRetry: () => ref.invalidate(cashSummaryProvider),
        ),
        data: (summary) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(cashSummaryProvider),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              _InHandCard(summary: summary),
              const SizedBox(height: 20),
              if (summary.collections.isNotEmpty) ...[
                const SectionHeader('Not yet handed over'),
                for (final c in summary.collections) _HeldRow(item: c),
                const SizedBox(height: 20),
              ],
              const SectionHeader('Hand-over history'),
              if (summary.deposits.isEmpty)
                const AppCard(
                  child: Text(
                    "You haven't handed over any cash yet.",
                    style: TextStyle(color: AgentColors.label),
                  ),
                )
              else
                for (final d in summary.deposits) _DepositRow(deposit: d),
            ],
          ),
        ),
      ),
    );
  }
}

class _InHandCard extends ConsumerWidget {
  const _InHandCard({required this.summary});

  final CashSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final holding = summary.inHand > 0;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Cash with you',
              style: TextStyle(color: AgentColors.label, fontSize: 13)),
          const SizedBox(height: 4),
          Text(agentMoney(summary.inHand),
              style: const TextStyle(
                  fontSize: 30, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            holding
                ? 'From ${summary.collections.length} collection'
                    '${summary.collections.length == 1 ? '' : 's'}. '
                    'Hand it over so it stops showing against you.'
                : 'All collected cash has been handed over.',
            style: const TextStyle(color: AgentColors.label, fontSize: 13),
          ),
          if (holding) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.account_balance_rounded, size: 18),
                label: const Text('Hand over cash'),
                onPressed: () => _openDeclareSheet(context, ref, summary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

void _openDeclareSheet(BuildContext context, WidgetRef ref, CashSummary s) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AgentColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (_) => _DeclareSheet(summary: s),
  );
}

/// Declare a hand-over: pick which collections are being banked, say how.
class _DeclareSheet extends ConsumerStatefulWidget {
  const _DeclareSheet({required this.summary});

  final CashSummary summary;

  @override
  ConsumerState<_DeclareSheet> createState() => _DeclareSheetState();
}

enum _Channel { cash, online }

class _DeclareSheetState extends ConsumerState<_DeclareSheet>
    with WidgetsBindingObserver {
  late final Set<String> _selected = {
    for (final c in widget.summary.collections) c.id,
  };
  _Channel _channel = _Channel.cash;
  bool _busy = false;

  /// Set once an online hand-over has been started — the sheet then shows the
  /// pay-and-confirm step instead of the picker.
  OnlineHandover? _pending;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Coming back from the payment page: check the link once, silently. If the
  /// money moved, the sheet completes itself — no "I've paid" tap needed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _pending != null &&
        !_busy) {
      _confirmOnline(silent: true);
    }
  }

  /// The amount is the sum of what's ticked — never free text. A typed figure
  /// that disagrees with the collections it covers is exactly how cash goes
  /// missing without anyone noticing.
  num get _total => widget.summary.collections
      .where((c) => _selected.contains(c.id))
      .fold<num>(0, (sum, c) => sum + c.amount);

  // ── physical cash ──
  Future<void> _submitCash() async {
    setState(() => _busy = true);
    try {
      await ref.read(cashApiProvider).declare(
            amount: _total,
            method: 'office', // physical notes handed to the store
            collectionIds: _selected.toList(),
          );
      ref.invalidate(cashSummaryProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      showToast(context,
          'Hand-over recorded. The store will confirm once it is counted.');
    } catch (e) {
      _showError(e, 'Could not record the hand-over.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── online transfer ──
  Future<void> _startOnline() async {
    setState(() => _busy = true);
    try {
      final handover = await ref
          .read(cashApiProvider)
          .declareOnline(collectionIds: _selected.toList());
      ref.invalidate(cashSummaryProvider); // cash is now reserved out of hand
      if (!mounted) return;
      if (handover.confirmed) {
        Navigator.of(context).pop();
        showToast(context, 'Online hand-over received. Thank you.');
        return;
      }
      setState(() => _pending = handover);
      await _openLink(handover.shortUrl);
    } catch (e) {
      _showError(e, 'Could not start the online hand-over.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openLink(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    // IN-APP browser (Custom Tab): the payment page opens over the app and
    // closing it lands the agent straight back on this sheet — the external
    // browser stranded them in another app with no way "back" into the flow.
    try {
      await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    } catch (_) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _confirmOnline({bool silent = false}) async {
    final pending = _pending;
    if (pending == null) return;
    setState(() => _busy = true);
    try {
      final deposit =
          await ref.read(cashApiProvider).confirmOnline(pending.depositId);
      ref.invalidate(cashSummaryProvider);
      if (!mounted) return;
      if (deposit.status == DepositStatus.verified) {
        Navigator.of(context).pop();
        showToast(context, 'Online hand-over received. Thank you.');
      } else if (!silent) {
        // Gateway hasn't seen the money yet — keep the pay step open.
        showToast(context,
            "We haven't seen the payment yet. Finish paying, then try again.");
      }
    } catch (e) {
      if (silent) return; // background check — never disrupt on a blip
      // A cancelled/expired link (CASH_ONLINE_FAILED) frees the cash again.
      ref.invalidate(cashSummaryProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      _showError(e, 'The online hand-over could not be completed.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Explicitly abandon the unpaid hand-over: link cancelled server-side, the
  /// cash returns to IN HAND at once, and the sheet closes on the fresh state.
  Future<void> _cancelOnline() async {
    final pending = _pending;
    if (pending == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(cashApiProvider).cancelOnline(pending.depositId);
      ref.invalidate(cashSummaryProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      showToast(context,
          'Hand-over cancelled — the cash is back in your hand.');
    } catch (e) {
      _showError(e, 'Could not cancel the hand-over.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(Object e, String fallback) {
    if (!mounted) return;
    showToast(context, describeFailure(e, fallback: fallback).display, error: true);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
        child: _pending != null ? _payStep() : _pickStep(),
      ),
    );
  }

  Widget _pickStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Hand over cash',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text(
          'Tick what you are handing over, then choose how. The amount is '
          'worked out from what you tick.',
          style: TextStyle(color: AgentColors.label, fontSize: 13),
        ),
        const SizedBox(height: 12),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (final c in widget.summary.collections)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: _selected.contains(c.id),
                    onChanged: (v) => setState(() {
                      if (v ?? false) {
                        _selected.add(c.id);
                      } else {
                        _selected.remove(c.id);
                      }
                    }),
                    title:
                        Text(c.customerName.isEmpty ? 'Customer' : c.customerName),
                    subtitle: Text(agentMoney(c.amount)),
                  ),
              ],
            ),
          ),
        ),
        const Divider(height: 24),
        Row(
          children: [
            const Text('Handing over',
                style: TextStyle(color: AgentColors.label)),
            const Spacer(),
            Text(agentMoney(_total),
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 12),
        _ChannelChoice(
          value: _channel,
          onChanged: (c) => setState(() => _channel = c),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: (_busy || _total <= 0)
                ? null
                : (_channel == _Channel.cash ? _submitCash : _startOnline),
            child: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_channel == _Channel.cash
                    ? 'Give ${agentMoney(_total)} cash'
                    : 'Send ${agentMoney(_total)} online'),
          ),
        ),
      ],
    );
  }

  Widget _payStep() {
    final pending = _pending!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Complete your online payment',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(
          'Pay ${agentMoney(pending.amount)} on the Razorpay page to send this '
          'money to your store. Once you have paid, tap "I\'ve paid".',
          style: const TextStyle(color: AgentColors.label, fontSize: 13),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _openLink(pending.shortUrl),
          icon: const Icon(Icons.open_in_new_rounded, size: 18),
          label: const Text('Open payment page again'),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : _confirmOnline,
            child: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text("I've paid — check now"),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: _busy ? null : _cancelOnline,
            style: TextButton.styleFrom(foregroundColor: AgentColors.danger),
            child: const Text('Cancel — keep the cash in hand'),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            'Paying opens inside the app; when you come back we check '
            'automatically. Cancelling frees the cash immediately.',
            style: TextStyle(color: AgentColors.label.withValues(alpha: 0.8),
                fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

/// The cash-vs-online choice.
class _ChannelChoice extends StatelessWidget {
  const _ChannelChoice({required this.value, required this.onChanged});

  final _Channel value;
  final ValueChanged<_Channel> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ChannelCard(
            icon: Icons.payments_rounded,
            title: 'Give cash',
            subtitle: 'Hand notes to the store',
            selected: value == _Channel.cash,
            onTap: () => onChanged(_Channel.cash),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ChannelCard(
            icon: Icons.smartphone_rounded,
            title: 'Send online',
            subtitle: 'Pay the store via UPI',
            selected: value == _Channel.online,
            onTap: () => onChanged(_Channel.online),
          ),
        ),
      ],
    );
  }
}

class _ChannelCard extends StatelessWidget {
  const _ChannelCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AgentColors.brand;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? accent : AgentColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: selected ? accent : AgentColors.label),
            const SizedBox(height: 8),
            Text(title,
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: selected ? accent : AgentColors.textPrimary)),
            const SizedBox(height: 2),
            Text(subtitle,
                style: const TextStyle(
                    fontSize: 11, color: AgentColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _HeldRow extends StatelessWidget {
  const _HeldRow({required this.item});

  final HeldCollection item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const LeadingIcon(
                icon: Icons.payments_rounded, color: AgentColors.amber),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.customerName.isEmpty ? 'Customer' : item.customerName,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Text(agentMoney(item.amount),
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _DepositRow extends ConsumerStatefulWidget {
  const _DepositRow({required this.deposit});

  final CashDeposit deposit;

  @override
  ConsumerState<_DepositRow> createState() => _DepositRowState();
}

class _DepositRowState extends ConsumerState<_DepositRow> {
  bool _cancelling = false;

  CashDeposit get deposit => widget.deposit;

  // Cancelling here (from the persisted history list) is the only way back
  // once the in-flight hand-over sheet (CashScreen's _DeclareSheet, which has
  // its own live Cancel button) is gone — e.g. the agent's payment failed for
  // some reason that never returns them to the app (no network, insufficient
  // balance, they just closed it) and they only notice later that this row is
  // still sitting "Awaiting payment". Without this the cash stays reserved
  // out of their hands indefinitely with no way to back out.
  Future<void> _cancel() async {
    if (_cancelling) return;
    setState(() => _cancelling = true);
    try {
      await ref.read(cashApiProvider).cancelOnline(deposit.id);
      ref.invalidate(cashSummaryProvider);
      if (mounted) {
        showToast(context, 'Hand-over cancelled — the cash is back in your hand.');
      }
    } catch (e) {
      if (mounted) {
        showToast(context,
            describeFailure(e, fallback: 'Could not cancel the hand-over.').display,
            error: true);
      }
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  Color get _tone => switch (deposit.status) {
        DepositStatus.verified => AgentColors.green,
        DepositStatus.short => AgentColors.danger,
        DepositStatus.rejected => AgentColors.danger,
        DepositStatus.cancelled => AgentColors.textSecondary,
        DepositStatus.pending => AgentColors.amber,
        DepositStatus.initiated => AgentColors.blue,
      };

  @override
  Widget build(BuildContext context) {
    final short = deposit.shortfall > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(agentMoney(deposit.amount),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                const Spacer(),
                StatusPill(label: deposit.status.label, color: _tone),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  deposit.isOnline
                      ? Icons.smartphone_rounded
                      : Icons.payments_rounded,
                  size: 13,
                  color: AgentColors.label,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    [
                      deposit.isOnline ? 'Online' : 'Cash',
                      if (deposit.depositedOn != null)
                        '${deposit.depositedOn!.day}/${deposit.depositedOn!.month}/'
                            '${deposit.depositedOn!.year}',
                      deposit.reference.isEmpty ? null : deposit.reference,
                    ].whereType<String>().join(' · '),
                    style: const TextStyle(color: AgentColors.label, fontSize: 12),
                  ),
                ),
              ],
            ),
            if (short) ...[
              const SizedBox(height: 6),
              Text(
                'Counted ${agentMoney(deposit.verifiedAmount ?? 0)} — '
                '${agentMoney(deposit.shortfall)} short.',
                style: const TextStyle(
                    color: AgentColors.danger,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ],
            if (deposit.status == DepositStatus.rejected &&
                deposit.notes.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(deposit.notes,
                  style: const TextStyle(
                      color: AgentColors.danger, fontSize: 12)),
            ],
            if (deposit.status == DepositStatus.initiated) ...[
              const SizedBox(height: 8),
              const Text(
                "Payment didn't go through? You can cancel and keep the cash.",
                style: TextStyle(color: AgentColors.label, fontSize: 11.5),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _cancelling ? null : _cancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AgentColors.danger,
                    side: const BorderSide(color: AgentColors.danger),
                    minimumSize: const Size.fromHeight(38),
                  ),
                  icon: _cancelling
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AgentColors.danger),
                        )
                      : const Icon(Icons.close_rounded, size: 16),
                  label: const Text('Cancel — keep the cash in hand'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
