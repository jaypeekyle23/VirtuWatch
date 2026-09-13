import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/chat_service.dart';
import '../theme/app_theme.dart';

/// Opens the "Ask about this watch" chat as a scrollable bottom sheet.
Future<void> showWatchChatSheet(
  BuildContext context, {
  required String watchId,
  required Map<String, dynamic> watchData,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => WatchChatSheet(watchId: watchId, watchData: watchData),
  );
}

class WatchChatSheet extends StatefulWidget {
  final String watchId;
  final Map<String, dynamic> watchData;

  const WatchChatSheet({
    super.key,
    required this.watchId,
    required this.watchData,
  });

  @override
  State<WatchChatSheet> createState() => _WatchChatSheetState();
}

class _WatchChatSheetState extends State<WatchChatSheet> {
  ChatService? _chatService;
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isSending = false;
  bool _isLoadingProfile = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initChatService();
  }

  /// Loads the current user's profile (wrist width, style preferences,
  /// budget) so the assistant can answer fit/style questions using data
  /// the user already saved, instead of asking for it again.
  Future<void> _initChatService() async {
    Map<String, dynamic>? userProfile;
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        userProfile = doc.data();
      }
    } catch (_) {
      // If the profile can't be loaded, fall back to chatting without
      // it rather than blocking the whole feature.
    }

    if (!mounted) return;
    setState(() {
      _chatService = ChatService(
        watchData: widget.watchData,
        userProfile: userProfile,
      );
      _isLoadingProfile = false;
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isSending = false;
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.watchData['name'] as String? ?? 'this watch';
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
                        'Ask about $name',
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: AppTheme.surface, height: 1),
              Expanded(
                child: _isLoadingProfile
                    ? const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : (_messages.isEmpty && !_isSending)
                        ? _emptyState(name)
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

  Widget _emptyState(String name) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Ask anything about $name — fit, materials, style, or how to '
          'wear it.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
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
        child: Text(
          message.text,
          style: TextStyle(
            color: isUser ? const Color(0xFF0E1A2B) : AppTheme.textPrimary,
            fontSize: 13,
          ),
        ),
      ),
    );
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
            onPressed: (_isSending || _isLoadingProfile) ? null : _send,
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