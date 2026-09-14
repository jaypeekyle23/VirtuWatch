import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/chat_history_service.dart';
import '../services/chat_service.dart';
import '../theme/app_theme.dart';

/// Opens [ChatSheet] as a scrollable bottom sheet. Both the single-watch
/// chat (Watch Detail screen) and the recommendations-wide chat
/// (Recommended For You screen) go through this — only [title],
/// [emptyStateHint], how [createChatService] builds its ChatService, and
/// [threadKey] (for persisting history) differ between them.
Future<void> showChatSheet(
  BuildContext context, {
  required String title,
  required String emptyStateHint,
  required Future<ChatService> Function() createChatService,
  required String threadKey,
  List<String> suggestedQuestions = const [],
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ChatSheet(
      title: title,
      emptyStateHint: emptyStateHint,
      createChatService: createChatService,
      threadKey: threadKey,
      suggestedQuestions: suggestedQuestions,
    ),
  );
}

class ChatSheet extends StatefulWidget {
  final String title;
  final String emptyStateHint;
  final Future<ChatService> Function() createChatService;
  final String threadKey;
  final List<String> suggestedQuestions;

  const ChatSheet({
    super.key,
    required this.title,
    required this.emptyStateHint,
    required this.createChatService,
    required this.threadKey,
    this.suggestedQuestions = const [],
  });

  @override
  State<ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends State<ChatSheet> {
  final _historyService = ChatHistoryService();
  ChatService? _chatService;
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isSending = false;
  bool _isInitializing = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    ChatService? service;
    List<ChatMessage> savedMessages = [];
    try {
      service = await widget.createChatService();
      savedMessages = await _historyService.load(widget.threadKey);
      service.seedHistory(savedMessages);
    } catch (_) {
      // Fall through with whatever we managed to get; _send() below
      // no-ops if service is null rather than crashing the sheet.
    }
    if (!mounted) return;
    setState(() {
      _chatService = service;
      _messages.addAll(savedMessages);
      _isInitializing = false;
    });
    if (savedMessages.isNotEmpty) _scrollToBottom(animate: false);
  }

  Future<void> _clearHistory() async {
    setState(() {
      _messages.clear();
      _error = null;
    });
    _chatService?.seedHistory(const []);
    await _historyService.clear(widget.threadKey);
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send({String? overrideText}) async {
    final text = overrideText ?? _inputController.text.trim();
    if (text.isEmpty || _isSending || _chatService == null) return;

    setState(() {
      _messages.add(ChatMessage(role: 'user', text: text));
      _isSending = true;
      _error = null;
    });
    _inputController.clear();
    _scrollToBottom();

    try {
      final reply = await _chatService!.sendMessage(text);
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _messages.add(ChatMessage(role: 'model', text: reply));
      });
      _scrollToBottom();
      // Fire-and-forget: don't block the UI on the persistence write.
      unawaited(_historyService.save(widget.threadKey, _messages));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isSending = false;
      });
    }
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (animate) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 100),
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: FractionallySizedBox(
        heightFactor: 0.85,
        child: Container(
          decoration: const BoxDecoration(
            color: AppTheme.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.textSecondary.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                child: Row(
                  children: [
                    const Icon(Icons.chat_bubble_outline,
                        color: AppTheme.gold, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_messages.isNotEmpty)
                      IconButton(
                        onPressed: _clearHistory,
                        icon: const Icon(Icons.delete_outline,
                            color: AppTheme.textSecondary, size: 20),
                        tooltip: 'Clear chat',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                  ],
                ),
              ),
              const Divider(color: AppTheme.surface, height: 1),
              Expanded(
                child: _isInitializing
                    ? const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : (_messages.isEmpty && !_isSending)
                        ? _emptyState()
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(16),
                            itemCount:
                                _messages.length + (_isSending ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == _messages.length) {
                                // Trailing "typing" bubble while waiting
                                // for a reply.
                                return const _AnimatedBubbleEntrance(
                                  key: ValueKey('typing_indicator'),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: _TypingIndicator(),
                                  ),
                                );
                              }
                              return _AnimatedBubbleEntrance(
                                key: ValueKey('msg_$index'),
                                child: _bubble(_messages[index]),
                              );
                            },
                          ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                        color: Colors.orangeAccent, fontSize: 12),
                  ),
                ),
              _inputBar(),
              SizedBox(height: MediaQuery.of(context).padding.bottom),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.emptyStateHint,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            if (widget.suggestedQuestions.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: widget.suggestedQuestions.map((q) {
                  return ActionChip(
                    label: Text(q, style: const TextStyle(fontSize: 12)),
                    backgroundColor: AppTheme.surface,
                    side: BorderSide(color: AppTheme.gold.withValues(alpha: 0.3)),
                    labelStyle: const TextStyle(color: AppTheme.textPrimary),
                    onPressed:
                        (_isSending || _isInitializing) ? null : () => _send(overrideText: q),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _bubble(ChatMessage message) {
    final isUser = message.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isUser ? AppTheme.gold : AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: _formattedMessageText(
          message.text,
          color: isUser ? const Color(0xFF0E1A2B) : AppTheme.textPrimary,
        ),
      ),
    );
  }

  /// The model replies in lightweight markdown (**bold**, "* " bullet
  /// lines) since that's how Gemini naturally formats structured
  /// answers. Rendering it as plain text left the raw asterisks visible,
  /// which looked broken rather than intentional — this turns it into
  /// actual bold spans and bullet characters instead. Only bold + bullets
  /// are handled (not italics, links, headers, etc.) since that covers
  /// everything the chat prompts' reply style actually produces.
  Widget _formattedMessageText(String text, {required Color color}) {
    final baseStyle = GoogleFonts.inter(color: color, fontSize: 13, height: 1.4);
    final lines = text.split('\n');

    return RichText(
      text: TextSpan(
        style: baseStyle,
        children: [
          for (var i = 0; i < lines.length; i++) ...[
            if (i > 0) const TextSpan(text: '\n'),
            ..._parseInlineBold(_stripBulletMarker(lines[i]), baseStyle),
          ],
        ],
      ),
    );
  }

  /// Turns a leading "* " or "- " (Markdown's plain bullet syntax) into
  /// a proper bullet character, so lists don't show the literal marker.
  String _stripBulletMarker(String line) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('* ') || trimmed.startsWith('- ')) {
      final indent = line.substring(0, line.length - trimmed.length);
      return '$indent• ${trimmed.substring(2)}';
    }
    return line;
  }

  /// Splits `**bold**` segments out of [line] into bold TextSpans,
  /// leaving everything else in [baseStyle].
  List<TextSpan> _parseInlineBold(String line, TextStyle baseStyle) {
    final pattern = RegExp(r'\*\*(.+?)\*\*');
    final spans = <TextSpan>[];
    var lastEnd = 0;

    for (final match in pattern.allMatches(line)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: line.substring(lastEnd, match.start)));
      }
      spans.add(TextSpan(
        text: match.group(1),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ));
      lastEnd = match.end;
    }
    if (lastEnd < line.length) {
      spans.add(TextSpan(text: line.substring(lastEnd)));
    }
    return spans;
  }

  Widget _inputBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputController,
              style: const TextStyle(color: AppTheme.textPrimary),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: const InputDecoration(
                hintText: 'Ask a question…',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: (_isSending || _isInitializing) ? null : _send,
            icon: const Icon(Icons.send, color: AppTheme.gold),
          ),
        ],
      ),
    );
  }
}

/// Plays a one-time fade + slide-up entrance for its [child] the first
/// time it's built, then stays put. Because each bubble in the message
/// list gets a stable [ValueKey] tied to its position, Flutter keeps this
/// widget's State alive across rebuilds — so the animation runs once per
/// message (when it's newly added) rather than replaying on every
/// setState.
class _AnimatedBubbleEntrance extends StatefulWidget {
  final Widget child;

  const _AnimatedBubbleEntrance({super.key, required this.child});

  @override
  State<_AnimatedBubbleEntrance> createState() =>
      _AnimatedBubbleEntranceState();
}

class _AnimatedBubbleEntranceState extends State<_AnimatedBubbleEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

/// Three dots that pulse in sequence, shown in a bubble matching the
/// assistant's own message style — signals "thinking" rather than a
/// generic loading spinner.
class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _dotScale(int index) {
    // Stagger each dot's pulse by a third of the cycle.
    final t = (_controller.value + (index * 0.2)) % 1.0;
    // Simple triangular pulse: scale up then back down.
    final pulse = (t < 0.5) ? (t / 0.5) : (1 - (t - 0.5) / 0.5);
    return 0.5 + (pulse * 0.5);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              return Padding(
                padding: EdgeInsets.only(right: i < 2 ? 5 : 0),
                child: Transform.scale(
                  scale: _dotScale(i),
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: AppTheme.gold,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}