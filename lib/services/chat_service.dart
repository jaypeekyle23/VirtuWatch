import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../constants/app_knowledge.dart';
import '../constants/watch_colors.dart';
import '../utils/match_score_color.dart';
import 'recommendation_service.dart';

/// A single turn in the conversation, in the order it was said.
class ChatMessage {
  final String role; // 'user' or 'model'
  final String text;

  const ChatMessage({required this.role, required this.text});
}

/// Handles chat grounded in real VirtuWatch data — either a single watch
/// (via [ChatService.forWatch]) or the user's current recommendation
/// list (via [ChatService.forRecommendations]) — so the model answers
/// from actual specs/scores instead of guessing or inventing details.
///
/// SECURITY NOTE: this calls the Gemini API directly from the client with
/// an API key embedded below. That is only safe because the key MUST be
/// restricted in Google Cloud Console to:
///   1. API restriction -> Generative Language API only
///   2. Application restriction -> your Android package name (+ SHA-1)
///      and/or iOS bundle ID
/// Do not ship this with an unrestricted key.
class ChatService {
  // Injected at build/run time via --dart-define-from-file=.env
  // (see env.example for the expected format). Never hardcode the real
  // key here — that's exactly what this mechanism avoids.
  static const String _apiKey = String.fromEnvironment('GEMINI_API_KEY');

  static const String _model = 'gemini-3.5-flash-lite';
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  final String Function() _buildSystemPrompt;
  final List<ChatMessage> _history = [];

  ChatService._({required String Function() systemPromptBuilder})
      : _buildSystemPrompt = systemPromptBuilder;

  /// Chat scoped to ONE watch — used from the Watch Detail screen.
  ///
  /// [recommendation] is this watch's own [WatchRecommendation] (the same
  /// object backing the on-screen match card, from
  /// [RecommendationService.scoreWatch]) — passing it in means the
  /// chatbot's fit/color/style/match-score answers use the exact same
  /// scoring the customer already sees, instead of only knowing about fit
  /// (as this used to before color/style were wired in here too).
  factory ChatService.forWatch({
    required Map<String, dynamic> watchData,
    Map<String, dynamic>? userProfile,
    List<Map<String, dynamic>>? savedWatches,
    WatchRecommendation? recommendation,
  }) {
    return ChatService._(
      systemPromptBuilder: () => _buildWatchPrompt(
        watchData,
        userProfile,
        savedWatches,
        recommendation,
      ),
    );
  }

  /// Chat scoped to the user's current recommendation list — used from
  /// the "Recommended For You" screen. The assistant can discuss and
  /// compare any watch already ranked for this user, using the exact
  /// same scores/notes already shown on-screen.
  factory ChatService.forRecommendations(
    RecommendationResult result, {
    List<Map<String, dynamic>>? savedWatches,
  }) {
    return ChatService._(
      systemPromptBuilder: () =>
          _buildRecommendationsPrompt(result, savedWatches),
    );
  }

  List<ChatMessage> get history => List.unmodifiable(_history);

  /// Replaces the in-memory conversation with previously saved messages,
  /// so a reloaded chat continues with full context rather than the
  /// model losing track of everything said before the sheet was closed.
  /// Must be called before the first [sendMessage].
  void seedHistory(List<ChatMessage> messages) {
    _history
      ..clear()
      ..addAll(messages);
  }

  /// Formats the customer's saved/wishlist watches (if any) as a compact
  /// context line for the system prompt — lets the assistant reference
  /// "you've also saved X" or compare against them without the customer
  /// having to re-list what they're interested in.
  static String? _savedWatchesLine(List<Map<String, dynamic>>? savedWatches) {
    if (savedWatches == null || savedWatches.isEmpty) return null;
    final items = savedWatches.map((w) {
      final name = w['name'] as String? ?? 'Unnamed watch';
      final brand = w['brand'] as String? ?? '';
      final price = w['price'];
      return '$name${brand.isNotEmpty ? ' by $brand' : ''}'
          '${price != null ? ' (PHP $price)' : ''}';
    }).join(', ');
    return '- Saved/wishlist watches: $items';
  }

  /// Formats a watch's actual color(s) as a readable string for the
  /// prompt — e.g. "Rose Gold" when it matches a standard palette swatch,
  /// or a plain-language description (e.g. "burgundy") for a custom
  /// color outside the palette, via [describeHexColor]. Mirrors the
  /// exact colorHex/colorHexes fallback RecommendationService uses for
  /// scoring, so the colors the AI describes are always the same ones
  /// actually being scored. Never surfaces a raw hex code — that's
  /// meaningless read out loud in a chat conversation.
  static String _colorsLine(Map<String, dynamic> watchData) {
    final colorHex = watchData['colorHex'] as String?;
    final colorHexesRaw = (watchData['colorHexes'] as List?)?.cast<String>();
    final colorHexes = (colorHexesRaw != null && colorHexesRaw.isNotEmpty)
        ? colorHexesRaw
        : (colorHex != null ? [colorHex] : const <String>[]);

    if (colorHexes.isEmpty) return 'Not listed';
    return colorHexes
        .map((hex) => paletteNameForHex(hex) ?? describeHexColor(hex))
        .join(', ');
  }

  /// Formats a watch's target-gender category for the prompt. Returns
  /// null (rather than a string) when unset, so callers can decide
  /// whether to include the line at all — a watch with no gender set
  /// yet should read as "not specified" if it comes up, never guessed
  /// from the name/case size/color the way this was considered and
  /// deliberately rejected in favor of a real, merchant-set field.
  static String _genderLine(Map<String, dynamic> watchData) {
    final gender = watchData['targetGender'] as String?;
    return gender ?? 'Not specified';
  }

  static String _buildWatchPrompt(
    Map<String, dynamic> watchData,
    Map<String, dynamic>? userProfile,
    List<Map<String, dynamic>>? savedWatches,
    WatchRecommendation? recommendation,
  ) {
    final name = watchData['name'] as String? ?? 'this watch';
    final brand = watchData['brand'] as String? ?? 'Unknown';
    final price = watchData['price'];
    final style = watchData['styleCategory'] as String? ?? 'Unknown';
    final colors = _colorsLine(watchData);
    final gender = _genderLine(watchData);
    final caseDiameter = watchData['caseDiameterMm'];
    final caseThickness = watchData['caseThicknessMm'];
    final lugToLugMm = watchData['lugToLugMm'];
    final bandWidth = watchData['bandWidthMm'];
    final movementType = watchData['movementType'] as String? ?? 'Unknown';
    final waterResistance =
        watchData['waterResistance'] as String? ?? 'Unknown';
    final bandMaterial = watchData['bandMaterial'] as String? ?? 'Unknown';
    final caseMaterial = watchData['caseMaterial'] as String? ?? 'Unknown';

    final stylePreferences =
        (userProfile?['stylePreferences'] as List?)?.cast<String>() ?? [];
    final budgetMin = (userProfile?['budgetMin'] as num?)?.toDouble();
    final budgetMax = (userProfile?['budgetMax'] as num?)?.toDouble();

    // Use the SAME scoring RecommendationService already computed for this
    // watch (the exact numbers behind the on-screen match card) — never
    // let the model recompute or contradict fit, color, style, or the
    // overall match score itself.
    final matchLines = <String>[];
    if (recommendation != null) {
      final pct = recommendation.matchPercent;
      matchLines.add(
        '- Overall match score: $pct%'
        '${recommendation.confidenceNote != null ? ' (${recommendation.confidenceNote})' : ''}'
        ' — verdict: ${matchVerdictGuidance(pct, signalCount: recommendation.signalCount)}',
      );
      matchLines.add('- Fit: ${recommendation.fitNote}');
      if (recommendation.colorNote != null) {
        matchLines.add('- Color match: ${recommendation.colorNote}');
      }
    } else {
      matchLines.add(
        '- Match score not available — if fit/color/style comes up, say '
        'you don\'t have scoring data for this rather than guessing',
      );
    }

    final userContextLines = <String>[
      ...matchLines,
      if (stylePreferences.isNotEmpty)
        '- Style preferences: ${stylePreferences.join(', ')}',
      if (budgetMin != null && budgetMax != null)
        '- Budget range: PHP $budgetMin–$budgetMax',
      if (_savedWatchesLine(savedWatches) != null)
        _savedWatchesLine(savedWatches)!,
    ];

    return '''
You are a friendly, knowledgeable watch specialist inside the VirtuWatch app, helping a customer with questions about ONE specific watch, the VirtuWatch app itself, or general questions in this domain (wrist sizing, computer vision, AR, watch fit/buying guidance).

$appKnowledgeBlock

Here is the ONLY factual data you know about THIS watch — never invent specs, price, stock, or details beyond what's listed here:
- Name: $name
- Brand: $brand
- Price: ${price != null ? 'PHP $price' : 'Not listed'}
- Style category: $style
- Color(s): $colors
- Suited for: $gender
- Case diameter: ${caseDiameter != null ? '${caseDiameter}mm' : 'Not listed'}
- Case thickness: ${caseThickness != null ? '${caseThickness}mm' : 'Not listed'}
- Lug-to-lug: ${lugToLugMm != null ? '${lugToLugMm}mm' : 'Not listed'}
- Band width: ${bandWidth != null ? '${bandWidth}mm' : 'Not listed'}
- Movement: $movementType
- Water resistance: $waterResistance
- Band material: $bandMaterial
- Case material: $caseMaterial

What you know about the CUSTOMER you're talking to (use this — don't ask for info you already have here):
${userContextLines.join('\n')}

Rules:
- If the customer's wrist width is known, use it directly to answer fit questions (e.g. compare it to the lug-to-lug measurement above) instead of asking them for it.
- If asked HOW fit was determined: it's based on the lug-to-lug measurement as a proportion of the customer's wrist width, NOT a flat millimeter difference — roughly 75-95% of wrist width is the well-proportioned "classic" sweet spot and scores highest; below ~60% the watch reads as running small/dainty; 95-105% is a "bold" fit that fills the wrist with barely any overhang; past ~105% the lugs start to overhang the wrist edge, more noticeably past ~120%. Explain it this way if asked — don't invent a flat millimeter cutoff or a different method.
- If asked about this watch's color, answer using the Color(s) listed above exactly — never guess or invent a color that isn't listed there.
- Describe colors in plain language only (e.g. "burgundy", "teal") — never state a hex code like "#6F1011" to the customer, even if they ask for one; explain you don't expose technical color codes and give the plain-language name instead.
- If asked whether this watch is for men, women, or unisex, answer using "Suited for" above exactly. If it says "Not specified", say plainly that the merchant hasn't categorized it yet — never guess based on the name, size, or color.
- Be honest about the match score, following the verdict above exactly — do not soften, round up, or talk up a low score into a recommendation just to be agreeable. A middling or poor score means you should say so plainly and explain why (fit, color, or style), not reassure the customer it would still be good for them.
- If asked something not covered by the data above (e.g. exact stock, warranty terms, discounts), say you don't have that info and suggest they use the "Inquire via Urbane Time" button to ask the seller directly.
- Keep replies short and conversational — a few sentences, not an essay.
- Do not discuss other specific watches' prices or specs (you only have this one watch's data) or unrelated topics outside this domain; gently redirect those back to this watch or to browsing the catalog. Questions about the app itself or the general domain (see above) are welcome, not off-topic.
''';
  }

  static String _buildRecommendationsPrompt(
    RecommendationResult result,
    List<Map<String, dynamic>>? savedWatches,
  ) {
    final userContextLines = <String>[
      result.wristWidthMm != null
          ? '- Wrist width: ${result.wristWidthMm!.toStringAsFixed(1)}mm'
          : '- Wrist width: not provided',
      if (result.stylePreferences.isNotEmpty)
        '- Style preferences: ${result.stylePreferences.join(', ')}',
      '- Budget range: PHP ${result.budgetMin.toStringAsFixed(0)}–${result.budgetMax.toStringAsFixed(0)}',
      if (_savedWatchesLine(savedWatches) != null)
        _savedWatchesLine(savedWatches)!,
    ];

    // Send the customer's ENTIRE ranked catalog, not just a top slice —
    // capped only as a safety ceiling in case the catalog grows very
    // large someday. Previously this took only the top 15, which meant
    // the assistant genuinely had no data for lower-scoring watches
    // (e.g. it couldn't correctly answer "what's my lowest score watch"
    // once the catalog passed 15 items) — this fixes that.
    final topRecs = result.recommendations.take(60);

    final watchLines = topRecs.map((rec) {
      final data = rec.data;
      final name = data['name'] as String? ?? 'Unnamed watch';
      final brand = data['brand'] as String? ?? 'Unknown brand';
      final price = data['price'];
      final style = data['styleCategory'] as String? ?? 'Unknown style';
      final colors = _colorsLine(data);
      final gender = _genderLine(data);
      final caseDiameter = data['caseDiameterMm'];
      final lugToLugMm = data['lugToLugMm'];
      return '- "$name" by $brand — ${price != null ? 'PHP $price' : 'price not listed'}, '
          '$style style, $colors, suited for: $gender'
          '${caseDiameter != null ? ', ${caseDiameter}mm case' : ''}'
          // Lug-to-lug is the number the fit score is actually computed
          // from (case diameter is just visual size) — without it here,
          // the assistant could state the fitNote verdict but had no
          // raw number to back it up if asked "by how much" or "what's
          // the actual lug-to-lug".
          '${lugToLugMm != null ? ', ${lugToLugMm}mm lug-to-lug' : ''}. '
          'Match score: ${rec.matchPercent}% (${matchVerdictLabel(rec.matchPercent, signalCount: rec.signalCount)})'
          '${rec.confidenceNote != null ? ' (${rec.confidenceNote})' : ''}. '
          'Fit: ${rec.fitNote}.'
          '${rec.colorNote != null ? ' Color match: ${rec.colorNote}.' : ''}';
    }).join('\n');

    return '''
You are a friendly, knowledgeable watch specialist inside the VirtuWatch app, helping a customer browse their personalized watch recommendations. You can discuss, compare, and recommend from the list below — never invent watches, specs, or prices beyond what's listed here. You can also answer questions about the app itself or the general domain it's built on (see below).

$appKnowledgeBlock

What you know about the CUSTOMER:
${userContextLines.join('\n')}

The customer's current recommended watches, already ranked and scored by the app, listed from BEST match to WORST match (never recompute or contradict these match/fit scores — state them as-is; if asked for the lowest-scoring watch, it's the last one in this list):
$watchLines

HOW THE MATCH SCORE ACTUALLY WORKS (explain this accurately if asked "why is this a good match" or "how does scoring work" — don't make up a different explanation):
- Three signals feed the match score: Fit (55% weight), Style (30% weight), Color (15% weight). "Suited for" (gender) is shown for reference only and does NOT factor into the match score.
- Fit compares the watch's lug-to-lug measurement against the customer's wrist width as a PROPORTION (lug-to-lug ÷ wrist width), not a flat millimeter gap — roughly 75-95% of wrist width is the well-proportioned sweet spot and scores highest; below that it reads as running small, above it the fit gets "bold" then the lugs increasingly overhang the wrist the further past 105% the ratio goes.
- Color compares the watch's actual color(s), listed with each watch above, against the colors detected in the customer's last outfit scan, using how visually close the colors are — closer colors score higher.
- Style is a simple yes/no: does the watch's style category (e.g. minimalist, sporty, formal) match one of the customer's saved style preferences.
- If the customer hasn't provided a signal yet (no wrist measurement, no outfit scan, no style preferences saved), that signal is left out of the score entirely rather than counted against the watch — the remaining signals are re-weighted so an incomplete profile doesn't unfairly lower every score.
- The percentage shown is this weighted blend, not a simple average, and not something you should recompute — just explain the reasoning behind the number already given.

Rules:
- Only discuss specific watches from the list above — never invent specs/prices for a watch not on this list. If asked about a specific watch not on this list, say you can only discuss their current recommendations and suggest they browse the full catalog or search for it directly. Questions about the app itself or the general domain (see above) are welcome, not off-topic.
- If asked about color (e.g. "do you have a red watch", "which ones are rose gold"), check the color(s) listed with each watch above and answer from that exactly — if none match, say so plainly rather than guessing or suggesting the closest thing as if it matched.
- Describe colors in plain language only (e.g. "burgundy", "teal") — never state a hex code like "#6F1011" to the customer, even if they ask for one; explain you don't expose technical color codes and give the plain-language name instead.
- If asked which watches are for men, women, or unisex, use each watch's "suited for" value exactly. If it says "Not specified", say plainly that watch hasn't been categorized yet — never guess based on its name, size, or color.
- When asked "which is best for X", pick from the list using the match scores, fit notes, and budget as your basis, and explain briefly why.
- When you state a watch's match score, if it has a confidence caveat noted (e.g. "Based on style only"), mention that caveat too — don't present a high percentage as full confidence when it's actually based on one or two signals.
- Be honest about match quality, using the label next to each score above: "Great match" and "Good match" can be recommended normally; "Fair match" should be presented as only a partial fit, naming the weak signal; "Weak match" and "Poor match" must NOT be recommended as good for the customer — say plainly it's a poor match and why, and steer them to a higher-scoring watch instead. Never round a low score up into a positive recommendation just to be agreeable.
- Keep replies short and conversational — a few sentences, not an essay. Use watch names so the customer can find them on screen.
- If asked something not covered by the data above (stock, warranty, exact availability), say you don't have that info and suggest using each watch's "Inquire via Urbane Time" button.
''';
  }

  /// Sends [userText] and returns the model's reply, appending both to
  /// the in-memory conversation history.
  Future<String> sendMessage(String userText) async {
    if (_apiKey.isEmpty) {
      throw 'Chat is not configured. Run with '
          '--dart-define-from-file=.env (see env.example).';
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
        debugPrint('Gemini API error ${response.statusCode}: ${response.body}');
        if (response.statusCode == 429) {
          throw 'You\'re sending messages a bit fast — please wait a '
              'moment and try again.';
        }
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