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
        _messages.add(ChatMessage(role: 'model', text: reply));
        _isSending = false;
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
                    : _messages.isEmpty
                        ? _emptyState(name)
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(16),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) =>
                                _bubble(_messages[index]),
                          ),
              ),
              if (_isSending)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
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