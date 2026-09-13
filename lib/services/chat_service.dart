import 'dart:convert';
import 'package:http/http.dart' as http;

/// A single turn in the conversation, in the order it was said.
class ChatMessage {
  final String role; // 'user' or 'model'
  final String text;

  const ChatMessage({required this.role, required this.text});
}

/// Handles chat about a single watch, grounded in that watch's actual
/// Firestore data so the model answers from real specs instead of
/// guessing or inventing details.
///
/// SECURITY NOTE: this calls the Gemini API directly from the client with
/// an API key embedded below. That is only safe because the key MUST be
/// restricted in Google Cloud Console to:
///   1. API restriction -> Generative Language API only
///   2. Application restriction -> your Android package name (+ SHA-1)
///      and/or iOS bundle ID
/// Do not ship this with an unrestricted key.
class ChatService {
  // Injected at build/run time via --dart-define-from-file=.env.json
  // (see env.example.json for the expected format). Never hardcode the
  // real key here — that's exactly what this mechanism avoids.
  static const String _apiKey = String.fromEnvironment('GEMINI_API_KEY');

  static const String _model = 'gemini-2.5-flash-lite';
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  final Map<String, dynamic> watchData;

  /// The current user's profile fields relevant to fit/style advice
  /// (wristWidthMm, stylePreferences, budgetMin/Max), pulled from their
  /// Firestore user doc. Null/empty fields are simply omitted from the
  /// prompt rather than treated as zero.
  final Map<String, dynamic>? userProfile;

  final List<ChatMessage> _history = [];

  ChatService({required this.watchData, this.userProfile});

  List<ChatMessage> get history => List.unmodifiable(_history);

  /// Builds the system instruction that grounds every reply in this
  /// watch's actual data, so the model doesn't invent specs, prices, or
  /// availability it doesn't actually know.
  String _buildSystemPrompt() {
    final name = watchData['name'] as String? ?? 'this watch';
    final brand = watchData['brand'] as String? ?? 'Unknown';
    final price = watchData['price'];
    final style = watchData['styleCategory'] as String? ?? 'Unknown';
    final caseDiameter = watchData['caseDiameterMm'];
    final caseThickness = watchData['caseThicknessMm'];
    final lugToLug = watchData['lugToLugMm'];
    final bandWidth = watchData['bandWidthMm'];
    final movementType = watchData['movementType'] as String? ?? 'Unknown';
    final waterResistance =
        watchData['waterResistance'] as String? ?? 'Unknown';
    final bandMaterial = watchData['bandMaterial'] as String? ?? 'Unknown';
    final caseMaterial = watchData['caseMaterial'] as String? ?? 'Unknown';

    final wristWidthMm = (userProfile?['wristWidthMm'] as num?)?.toDouble();
    final stylePreferences =
        (userProfile?['stylePreferences'] as List?)?.cast<String>() ?? [];
    final budgetMin = (userProfile?['budgetMin'] as num?)?.toDouble();
    final budgetMax = (userProfile?['budgetMax'] as num?)?.toDouble();

    final userContextLines = <String>[
      if (wristWidthMm != null)
        '- Wrist width: ${wristWidthMm.toStringAsFixed(1)}mm'
      else
        '- Wrist width: not provided — if fit comes up, ask for it instead of assuming',
      if (stylePreferences.isNotEmpty)
        '- Style preferences: ${stylePreferences.join(', ')}',
      if (budgetMin != null && budgetMax != null)
        '- Budget range: PHP $budgetMin–$budgetMax',
    ];

    return '''
You are a friendly, knowledgeable watch specialist inside the VirtuWatch app, helping a customer with questions about ONE specific watch. Stay focused on this watch and general watch-buying guidance (fit, style, care, occasions to wear it).

Here is the ONLY factual data you know about this watch — never invent specs, price, stock, or details beyond what's listed here:
- Name: $name
- Brand: $brand
- Price: ${price != null ? 'PHP $price' : 'Not listed'}
- Style category: $style
- Case diameter: ${caseDiameter != null ? '${caseDiameter}mm' : 'Not listed'}
- Case thickness: ${caseThickness != null ? '${caseThickness}mm' : 'Not listed'}
- Lug-to-lug: ${lugToLug != null ? '${lugToLug}mm' : 'Not listed'}
- Band width: ${bandWidth != null ? '${bandWidth}mm' : 'Not listed'}
- Movement: $movementType
- Water resistance: $waterResistance
- Band material: $bandMaterial
- Case material: $caseMaterial

What you know about the CUSTOMER you're talking to (use this — don't ask for info you already have here):
${userContextLines.join('\n')}

Rules:
- If the customer's wrist width is known, use it directly to answer fit questions (e.g. compare it to the lug-to-lug measurement above) instead of asking them for it.
- If asked something not covered by the data above (e.g. exact stock, warranty terms, discounts), say you don't have that info and suggest they use the "Inquire via Urbane Time" button to ask the seller directly.
- Keep replies short and conversational — a few sentences, not an essay.
- Do not discuss other watches, other brands' pricing, or unrelated topics; gently redirect back to this watch.
''';
  }

  /// Sends [userText] and returns the model's reply, appending both to
  /// the in-memory conversation history.
  Future<String> sendMessage(String userText) async {
    if (_apiKey.isEmpty) {
      throw 'Chat is not configured. Run with '
          '--dart-define-from-file=.env.json (see env.example.json).';
    }

    _history.add(ChatMessage(role: 'user', text: userText));

    final uri = Uri.parse(
      '$_baseUrl/$_model:generateContent?key=$_apiKey',
    );

    final body = {
      'system_instruction': {
        'parts': [
          {'text': _buildSystemPrompt()},
        ],
      },
      'contents': _history
          .map((m) => {
                'role': m.role,
                'parts': [
                  {'text': m.text},
                ],
              })
          .toList(),
    };

    try {
      http.Response? response;
      // Gemini occasionally returns a transient 503 (model overloaded).
      // Retry a couple of times with a short backoff before giving up.
      for (var attempt = 0; attempt < 3; attempt++) {
        response = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        );
        if (response.statusCode != 503) break;
        await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }

      if (response!.statusCode != 200) {
        // ignore: avoid_print
        print('Gemini API error ${response.statusCode}: ${response.body}');
        throw 'The assistant is unavailable right now (${response.statusCode}). Please try again.';
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = data['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) {
        throw 'The assistant didn\'t return a response. Please try again.';
      }

      final parts = (candidates.first
          as Map<String, dynamic>)['content']?['parts'] as List?;
      final reply = parts
              ?.map((p) => (p as Map<String, dynamic>)['text'] as String? ?? '')
              .join()
              .trim() ??
          '';

      if (reply.isEmpty) {
        throw 'The assistant didn\'t return a response. Please try again.';
      }

      _history.add(ChatMessage(role: 'model', text: reply));
      return reply;
    } catch (e) {
      // Roll back the user message so a failed turn doesn't pollute
      // history sent on the next attempt.
      _history.removeLast();
      if (e is String) rethrow;
      throw 'Could not reach the assistant. Check your connection and try again.';
    }
  }
}