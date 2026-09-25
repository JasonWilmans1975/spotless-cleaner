import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api_client.dart';
import '../format.dart';
import '../ui/layout.dart';
import '../ui/tiles.dart';

const kCleanerQuickReplies = ['On my way', 'Running 10 minutes late', 'All done — thanks!'];

/// "Today", "Yesterday", or e.g. "Tue, 29 Sep" — chat day separators.
String chatDayLabel(DateTime day, DateTime now) => switch (daysUntil(now, day)) {
      0 => 'Today',
      1 => 'Yesterday',
      _ => shortDate(day),
    };

/// Chat with the customer about one job, live via Supabase Realtime — the
/// cleaner's side of the customer app's MessagesScreen.
class ChatScreen extends StatefulWidget {
  final CleanerBooking booking;
  const ChatScreen({super.key, required this.booking});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _api = ApiClient();
  final _input = TextEditingController();
  late final Stream<List<ChatMessage>> _stream = _api.watchChat(widget.booking.id);
  bool _sending = false;
  int _seenUnread = 0;

  CleanerBooking get b => widget.booking;
  String get _first {
    final f = b.customerName.trim().split(' ').first;
    return f.isEmpty ? 'the customer' : f;
  }

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  /// Marks the customer's messages read whenever new unread ones arrive on screen.
  void _markRead(List<ChatMessage> messages) {
    final unread = messages.where((m) => m.unreadByCleaner).length;
    if (unread == 0 || unread == _seenUnread) return;
    _seenUnread = unread;
    _api.markMessagesRead(b.id).ignore();
  }

  Future<void> _send([String? quick]) async {
    final text = (quick ?? _input.text).trim();
    if (text.isEmpty || _sending) return;
    HapticFeedback.selectionClick();
    setState(() => _sending = true);
    if (quick == null) _input.clear();
    try {
      await _api.sendMessage(b.id, text);
    } catch (e) {
      if (!mounted) return;
      if (quick == null && _input.text.isEmpty) _input.text = text; // don't lose what they typed
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    final date = DateTime.tryParse(b.date);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: Column(children: [
          DecoratedBox(
            decoration: BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: s.line))),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                child: Row(children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(LucideIcons.chevronLeft, size: 20),
                  ),
                  const SizedBox(width: 12),
                  InitialsAvatar(name: b.customerName, size: 42, background: s.accentSoft, foreground: s.accentDeep),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(b.customerName.trim().isEmpty ? 'Customer' : b.customerName.trim(),
                          style: s.heading(17), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text('Customer', style: TextStyle(fontSize: 12.5, color: s.muted)),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: _stream,
              builder: (context, snapshot) {
                final messages = snapshot.data;
                if (messages != null) WidgetsBinding.instance.addPostFrameCallback((_) => _markRead(messages));
                return ListView(
                  // Reversed so it opens at, and stays pinned to, the newest message.
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    ..._bubbles(messages, snapshot.error).reversed,
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: s.primarySofter,
                        border: Border.all(color: s.primarySoft),
                        borderRadius: BorderRadius.circular(s.radiusMd),
                      ),
                      child: Row(children: [
                        Icon(LucideIcons.calendar, size: 16, color: context.colors.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text.rich(
                            TextSpan(children: [
                              TextSpan(text: b.serviceName, style: const TextStyle(fontWeight: FontWeight.w700)),
                              TextSpan(text: ' · ${date == null ? b.date : shortDate(date)}, ${b.startTime}'),
                            ]),
                            style: const TextStyle(fontSize: 13.5),
                          ),
                        ),
                      ]),
                    ),
                  ],
                );
              },
            ),
          ),
          _composer(),
        ]),
      ),
    );
  }

  /// Day separators + bubbles, oldest first.
  List<Widget> _bubbles(List<ChatMessage>? messages, Object? error) {
    final s = context.tokens;
    if (messages == null) {
      return [
        if (error != null)
          EmptyState(icon: LucideIcons.wifiOff, title: "Couldn't load messages", message: error.toString())
        else
          const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
      ];
    }
    if (messages.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            'Say hello to $_first — confirm access, parking or anything to bring.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, color: s.muted),
          ),
        ),
      ];
    }
    final now = DateTime.now();
    final out = <Widget>[];
    String? day;
    for (final m in messages) {
      final label = chatDayLabel(m.createdAt, now);
      if (label != day) {
        day = label;
        out.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: s.muted)),
        ));
      }
      out.add(_Bubble(message: m));
    }
    return out;
  }

  Widget _composer() {
    final s = context.tokens;
    final p = context.colors.primary;
    if (b.status == 'cancelled') {
      return StickyBottomBar(
        child: Text('This booking was cancelled, so the chat is closed.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, color: s.muted)),
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        height: 46,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          itemCount: kCleanerQuickReplies.length,
          separatorBuilder: (context, _) => const SizedBox(width: 8),
          itemBuilder: (context, n) => OutlinedButton(
            onPressed: _sending ? null : () => _send(kCleanerQuickReplies[n]),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              foregroundColor: p,
              side: BorderSide(color: p),
              textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
            child: Text(kCleanerQuickReplies[n]),
          ),
        ),
      ),
      DecoratedBox(
        decoration: BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: s.line))),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 2000,
                  buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: 'Message $_first…',
                    fillColor: context.colors.surface,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: s.line)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: s.line)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: p, width: 1.5)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                tooltip: 'Send',
                onPressed: _input.text.trim().isEmpty || _sending ? null : _send,
                style: IconButton.styleFrom(
                  backgroundColor: p,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: s.primarySoft,
                  disabledForegroundColor: Colors.white,
                  side: BorderSide.none,
                ),
                icon: const Icon(LucideIcons.sendHorizontal, size: 19),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    final mine = message.fromCleaner;
    const r = Radius.circular(20), tail = Radius.circular(6);
    final t = message.createdAt;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .72),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: mine ? context.colors.primary : Colors.white,
              border: Border.all(color: mine ? context.colors.primary : s.line),
              borderRadius: BorderRadius.only(topLeft: r, topRight: r, bottomLeft: mine ? r : tail, bottomRight: mine ? tail : r),
            ),
            child: Text(message.body, style: TextStyle(fontSize: 14.5, height: 1.45, color: mine ? Colors.white : null)),
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text('${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
              style: TextStyle(fontSize: 11, color: s.muted)),
        ),
      ]),
    );
  }
}
