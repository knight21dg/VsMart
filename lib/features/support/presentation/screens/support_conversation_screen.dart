import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../auth/presentation/providers/current_user_provider.dart';
import '../../data/support_data.dart';
import '../providers/support_providers.dart';

/// Support chat thread for a ticket. Renders the real message thread from
/// `GET /support/tickets/{code}` and posts replies via
/// `POST /support/tickets/{code}/messages`.
///
/// Opened with a ticket [code] (from ticket details) to continue a thread, or
/// with no code as a fresh conversation — the first message then creates a
/// general support ticket on the backend.
class SupportConversationScreen extends ConsumerStatefulWidget {
  const SupportConversationScreen({super.key, this.code});

  final String? code;

  @override
  ConsumerState<SupportConversationScreen> createState() =>
      _SupportConversationScreenState();
}

class _SupportConversationScreenState
    extends ConsumerState<SupportConversationScreen> {
  static const List<String> _quickReplies = [
    'Still facing issue',
    'Resolved, thanks',
    'Need a callback',
  ];

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  String? _code;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _code = widget.code;
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _controller.text).trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final ds = ref.read(supportDataSourceProvider);
    try {
      var code = _code;
      if (code == null) {
        // Fresh conversation → open a general ticket from the first message.
        final subject = text.length > 60 ? '${text.substring(0, 57)}…' : text;
        final ticket =
            await ds.createTicket(category: 'General', subject: subject);
        code = ticket.id;
      }
      await ds.sendMessage(code, text);
      _controller.clear();
      ref
        ..invalidate(ticketProvider(code))
        ..invalidate(ticketsProvider);
      if (mounted) {
        setState(() {
          _code = code;
          _sending = false;
        });
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (_) {
      if (mounted) setState(() => _sending = false);
      if (mounted) context.showSnack('Could not send message.', isError: true);
    }
  }

  void _showTicketDetails(SupportTicket ticket) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: AppSpacing.screen,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ticket VS-TKT-${ticket.id}',
                  style: AppTypography.titleLarge),
              AppSpacing.vGapMd,
              _detailRow('Status', _statusLabel(ticket.status)),
              _detailRow('Priority', _titleCase(ticket.priority)),
              _detailRow('Category', ticket.category),
              if (ticket.orderCode != null && ticket.orderCode!.isNotEmpty)
                _detailRow('Order', ticket.orderCode!),
              _detailRow('Opened', _fmtDate(ticket.createdAt)),
              AppSpacing.vGapMd,
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: AppTypography.bodyMedium
                    .copyWith(color: context.vsColors.textSecondary)),
            Text(value, style: AppTypography.labelLarge),
          ],
        ),
      );

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final code = _code;
    final myName = (ref.watch(currentUserProvider)?.name ?? '').trim();

    // Fresh conversation (no ticket yet) — invite the first message.
    if (code == null) {
      return Scaffold(
        appBar: const VSAppBar(
          titleWidget: _ConversationTitle(
            title: 'New Conversation',
            subtitle: 'We typically reply within 2 hours',
          ),
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              const Expanded(
                child: VSEmptyState(
                  icon: Icons.support_agent_rounded,
                  title: 'Start a conversation',
                  message:
                      'Describe your issue and our support team will get back '
                      'to you. Sending creates a support ticket.',
                ),
              ),
              _QuickReplies(replies: _quickReplies, onTap: _send),
              _Composer(
                controller: _controller,
                focusNode: _focusNode,
                sending: _sending,
                onSend: _send,
              ),
            ],
          ),
        ),
      );
    }

    final ticketAsync = ref.watch(ticketProvider(code));
    return Scaffold(
      appBar: VSAppBar(
        titleWidget: _ConversationTitle(
          title: 'Support',
          subtitle: ticketAsync.maybeWhen(
            data: (t) => 'Ticket VS-TKT-${t.id} • ${_statusLabel(t.status)}',
            orElse: () => 'Ticket VS-TKT-$code',
          ),
        ),
        actions: [
          ticketAsync.maybeWhen(
            data: (t) => IconButton(
              icon: const Icon(Icons.info_outline_rounded),
              color: context.vsColors.brand,
              onPressed: () => _showTicketDetails(t),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ticketAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => VSErrorView(
            message: "Couldn't load this conversation.",
            onRetry: () => ref.invalidate(ticketProvider(code)),
          ),
          data: (ticket) => Column(
            children: [
              Expanded(child: _Thread(ticket: ticket, myName: myName, scrollController: _scrollController)),
              _QuickReplies(replies: _quickReplies, onTap: _send),
              _Composer(
                controller: _controller,
                focusNode: _focusNode,
                sending: _sending,
                onSend: _send,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _statusLabel(String s) => switch (s) {
      'in_progress' => 'In Progress',
      'resolved' => 'Resolved',
      'closed' => 'Closed',
      _ => 'Open',
    };

String _titleCase(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

const _months = [
  '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

String _fmtDate(DateTime d) => '${d.day} ${_months[d.month]} ${d.year}';

String _fmtTime(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
}

/// Renders the ticket's message thread with per-day separators. The first
/// message is the issue description; subsequent ones are the conversation.
class _Thread extends StatelessWidget {
  const _Thread({
    required this.ticket,
    required this.myName,
    required this.scrollController,
  });

  final SupportTicket ticket;
  final String myName;
  final ScrollController scrollController;

  bool _isMe(TicketMessage m) =>
      myName.isNotEmpty && m.senderName.trim().toLowerCase() == myName.toLowerCase();

  @override
  Widget build(BuildContext context) {
    final messages = ticket.messages;
    if (messages.isEmpty) {
      return const VSEmptyState(
        icon: Icons.forum_outlined,
        title: 'No messages yet',
        message: 'Send a message to start the conversation.',
      );
    }

    // Build a flat list: a date separator whenever the day changes, then bubbles.
    final items = <Widget>[];
    DateTime? lastDay;
    items.add(_DateSeparator(label: 'Ticket VS-TKT-${ticket.id} opened'));
    for (final m in messages) {
      final day = DateTime(m.at.year, m.at.month, m.at.day);
      if (lastDay == null || day != lastDay) {
        items.add(_DateSeparator(label: _fmtDate(m.at)));
        lastDay = day;
      }
      items.add(_MessageBubble(
        text: m.body,
        time: _fmtTime(m.at),
        isMe: _isMe(m),
        senderName: m.senderName,
      ));
    }

    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: items.length,
      separatorBuilder: (_, __) => AppSpacing.vGapMd,
      itemBuilder: (_, i) => items[i],
    );
  }
}

/// App bar title showing the support avatar, a title and a subtitle.
class _ConversationTitle extends StatelessWidget {
  const _ConversationTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: vs.brandTint,
          child: Icon(Icons.support_agent_rounded, color: vs.brand, size: 22),
        ),
        AppSpacing.hGapMd,
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.titleLarge),
              const SizedBox(height: 2),
              Text(subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmall.copyWith(color: vs.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }
}

/// A centered, pill-shaped date/system separator.
class _DateSeparator extends StatelessWidget {
  const _DateSeparator({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: AppRadius.brPill,
          border: Border.all(color: vs.border),
        ),
        child: Text(
          label,
          style: AppTypography.labelSmall.copyWith(color: vs.textSecondary),
        ),
      ),
    );
  }
}

/// A single text message bubble — brand on the right for the customer, surface
/// with border on the left for the support agent.
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.text,
    required this.time,
    required this.isMe,
    required this.senderName,
  });

  final String text;
  final String time;
  final bool isMe;
  final String senderName;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;

    final bubble = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: isMe ? vs.brand : context.colors.surface,
        borderRadius: _bubbleRadius(isMe),
        border: isMe ? null : Border.all(color: vs.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe && senderName.isNotEmpty) ...[
            Text(
              senderName,
              style: AppTypography.labelSmall.copyWith(color: vs.brand),
            ),
            const SizedBox(height: 2),
          ],
          Text(
            text,
            style: AppTypography.bodyMedium.copyWith(
              color: isMe ? AppColors.white : context.colors.onSurface,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          _MetaRow(time: time, isMe: isMe),
        ],
      ),
    );

    return Row(
      mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!isMe) ...[
          _AgentAvatar(),
          AppSpacing.hGapSm,
        ],
        Flexible(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: context.screenWidth * 0.74),
            child: bubble,
          ),
        ),
      ],
    );
  }
}

/// Timestamp (and read indicator for the customer's own messages).
class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.time, required this.isMe});

  final String time;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final metaColor =
        isMe ? AppColors.white.withValues(alpha: 0.85) : vs.textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(time, style: AppTypography.labelSmall.copyWith(color: metaColor)),
        if (isMe) ...[
          AppSpacing.hGapSm,
          Icon(Icons.done_all_rounded, size: 14, color: metaColor),
        ],
      ],
    );
  }
}

/// Small circular avatar shown beside agent messages.
class _AgentAvatar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return CircleAvatar(
      radius: 14,
      backgroundColor: vs.brandTint,
      child: Icon(Icons.support_agent_rounded, color: vs.brand, size: 16),
    );
  }
}

/// Horizontally scrollable quick-reply chips above the composer.
class _QuickReplies extends StatelessWidget {
  const _QuickReplies({required this.replies, required this.onTap});

  final List<String> replies;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        itemCount: replies.length,
        separatorBuilder: (_, __) => AppSpacing.hGapSm,
        itemBuilder: (context, index) {
          final reply = replies[index];
          return Align(
            child: InkWell(
              borderRadius: AppRadius.brPill,
              onTap: () => onTap(reply),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  borderRadius: AppRadius.brPill,
                  border: Border.all(color: vs.border),
                ),
                child: Text(
                  reply,
                  style: AppTypography.labelMedium.copyWith(color: vs.brand),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Bottom message composer: text field + send button.
class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final ValueChanged<String?> onSend;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(top: BorderSide(color: vs.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: vs.border.withValues(alpha: 0.3),
                  borderRadius: AppRadius.brPill,
                  border: Border.all(color: vs.border),
                ),
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(null),
                  style: AppTypography.bodyMedium,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText: 'Type your message...',
                    hintStyle: AppTypography.bodyMedium
                        .copyWith(color: vs.textSecondary),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.md,
                    ),
                  ),
                ),
              ),
            ),
            AppSpacing.hGapSm,
            Material(
              color: vs.brand,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: sending ? null : () => onSend(null),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: sending
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation(AppColors.white),
                          ),
                        )
                      : const Icon(
                          Icons.send_rounded,
                          color: AppColors.white,
                          size: 22,
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

BorderRadius _bubbleRadius(bool isMe) {
  const r = Radius.circular(AppRadius.lg);
  const tight = Radius.circular(AppRadius.xs);
  return BorderRadius.only(
    topLeft: r,
    topRight: r,
    bottomLeft: isMe ? r : tight,
    bottomRight: isMe ? tight : r,
  );
}
