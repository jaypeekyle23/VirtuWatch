import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../constants/app_knowledge.dart';
import '../constants/watch_colors.dart';
import '../utils/match_score_color.dart';
import 'recommendation_service.dart';

/// A single turn in the conversation, in the order it was said.
/// A button the assistant can offer under a reply (e.g. "Measure my
/// wrist"). The assistant only suggests it: the customer taps it, and the
/// app does the actual navigation or change.
class ChatAction {
  static const String measureWrist = 'measure_wrist';
  static const String scanOutfit = 'scan_outfit';
  static const String editPreferences = 'edit_preferences';
  static const String tryOn = 'try_on';
  static const String saveWatch = 'save_watch';
  static const String viewSaved = 'view_saved';

  static const Set<String> types = {
    measureWrist,
    scanOutfit,
    editPreferences,
    tryOn,
    saveWatch,
    viewSaved,
  };

  /// Actions that are about one specific watch and so need a [watchId].
  static const Set<String> _watchTypes = {tryOn, saveWatch};

  final String type;
  final String? watchId;

  const ChatAction({required this.type, this.watchId});

  bool get needsWatch => _watchTypes.contains(type);

  Map<String, dynamic> toJson() => {
        'type': type,
        if (watchId != null) 'watchId': watchId,
      };

  /// Null for anything that isn't a known action type.
  static ChatAction? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final type = raw['type'];
    if (type is! String || !types.contains(type)) return null;
    final watchId = raw['watchId'];
    final needsWatch = _watchTypes.contains(type);
    return ChatAction(
      type: type,
      watchId: needsWatch && watchId is String && watchId.isNotEmpty
          ? watchId
          : null,
    );
  }
}

class ChatMessage {
  final String role; // 'user' or 'model'
  final String text;

  /// IDs of watches the assistant pointed to in this message, shown as
  /// tappable cards under the text bubble. Always empty for user
  /// messages and for chats that don't support cards.
  final List<String> watchIds;

  /// Buttons the assistant offered with this message. Always empty for
  /// user messages and for chats that don't support actions.
  final List<ChatAction> actions;

  const ChatMessage({
    required this.role,
    required this.text,
    this.watchIds = const [],
    this.actions = const [],
  });
}

/// What [ChatService.sendMessage] returns: the reply text plus any
/// watches the assistant wants to show as cards. [watchIds] has already
/// been checked against the watches the assistant was actually given, so
/// every ID in it is real.
class ChatReply {
  final String text;
  final List<String> watchIds;

  /// Already checked: every type is known and every watch ID is real.
  final List<ChatAction> actions;

  const ChatReply({
    required this.text,
    this.watchIds = const [],
    this.actions = const [],
  });
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

  /// How many ranked watches the recommendations prompt includes. Also
  /// the set of watches the assistant is allowed to show as cards.
  static const int _maxPromptWatches = 60;

  /// The most cards one reply can show, however many IDs the model sends.
  static const int _maxCardsPerReply = 3;

  /// Added to the end of the latest customer message (in the request only,
  /// never saved or shown) when replies are structured.
  static const String _formatReminder =
      '\n\n[Reminder: reply as JSON. Set "watchIds" to [] and "actions" to [] '
      'unless this message specifically asks to see, open, find, or try on a '
      'watch, asks for a recommendation, asks for another, more, or '
      'different watches, asks for photos, or asks to set '
      'something up in the app. Greetings, thanks, small talk, and general '
      'or app questions need no card. Answering a question, even about a '
      'watch already on screen, needs no card.]';

  /// The most action buttons one reply can show.
  static const int _maxActionsPerReply = 2;

  final String Function() _buildSystemPrompt;
  final List<ChatMessage> _history = [];

  /// When non-null, replies are requested as structured JSON
  /// (`{"text": ..., "watchIds": [...]}`) and any returned watch ID not in
  /// this set is dropped. Null means plain-text replies with no cards.
  Set<String>? _allowedWatchIds;

  /// The ranked list the recommendations prompt is built from. Replaced by
  /// [updateRecommendations] after the customer changes their profile, so
  /// the next message is answered with fresh scores. Null for chats that
  /// aren't about the recommendation list.
  RecommendationResult? _result;

  ChatService._({
    required String Function() systemPromptBuilder,
    Set<String>? allowedWatchIds,
  })  : _buildSystemPrompt = systemPromptBuilder,
        _allowedWatchIds = allowedWatchIds;

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
    late final ChatService service;
    service = ChatService._(
      // Read the result lazily so [updateRecommendations] takes effect on
      // the very next message.
      systemPromptBuilder: () => _buildRecommendationsPrompt(
        service._result ?? result,
        savedWatches,
      ),
      allowedWatchIds: _watchIdsFor(result),
    ).._result = result;
    return service;
  }

  static Set<String> _watchIdsFor(RecommendationResult result) => result
      .recommendations
      .take(_maxPromptWatches)
      .map((r) => r.watchId)
      .toSet();

  /// Swaps in a freshly scored list (e.g. after the customer measured
  /// their wrist or scanned an outfit from an action button), so the
  /// assistant's next answer uses the new scores.
  void updateRecommendations(RecommendationResult result) {
    if (_result == null) return;
    _result = result;
    _allowedWatchIds = _watchIdsFor(result);
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

  /// Formats the rest of a watch's spec sheet (the fields the single-watch
  /// chat already gets) as one compact line for the recommendations
  /// prompt. Only fields the merchant actually filled in are included, so
  /// anything missing from this line is genuinely not on file.
  static String _specsLine(Map<String, dynamic> data) {
    final parts = <String>[];
    void add(String label, Object? value, {String suffix = ''}) {
      if (value == null) return;
      final text = value.toString().trim();
      if (text.isEmpty) return;
      parts.add('$label $text$suffix');
    }

    add('case thickness', data['caseThicknessMm'], suffix: 'mm');
    add('band width', data['bandWidthMm'], suffix: 'mm');
    add('movement', data['movementType']);
    add('water resistance', data['waterResistance']);
    add('case material', data['caseMaterial']);
    add('band material', data['bandMaterial']);

    if (parts.isEmpty) return 'Specs: no further specs listed.';
    return 'Specs: ${parts.join(', ')}.';
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
- For any question about water, swimming, showering, rain, sweat, mud, or what activities a watch can handle, follow the WATER RESISTANCE GUIDANCE above strictly. Quote the listed rating, then answer plainly from the guidance. Lean cautious: if the activity is beyond the rating, or the rating is not listed, say it is not suitable or that you cannot confirm it. Never call a watch waterproof.
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
      result.stylePreferences.isNotEmpty
          ? '- Style preferences: ${result.stylePreferences.join(', ')}'
          : '- Style preferences: not set yet',
      result.outfitColors.isNotEmpty
          ? '- Outfit scan: done (colors on file)'
          : '- Outfit scan: not done yet',
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
    final topRecs = result.recommendations.take(_maxPromptWatches);

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
      return '- "$name" [id: ${rec.watchId}] by $brand — ${price != null ? 'PHP $price' : 'price not listed'}, '
          '$style style, $colors, suited for: $gender'
          '${caseDiameter != null ? ', ${caseDiameter}mm case' : ''}'
          // Lug-to-lug is the number the fit score is actually computed
          // from (case diameter is just visual size) — without it here,
          // the assistant could state the fitNote verdict but had no
          // raw number to back it up if asked "by how much" or "what's
          // the actual lug-to-lug".
          '${lugToLugMm != null ? ', ${lugToLugMm}mm lug-to-lug' : ''}. '
          '${_specsLine(data)} '
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
- Each watch's "Specs:" part is its spec sheet (case thickness, band width, movement, water resistance, case and band material), together with the case size and lug-to-lug given earlier in its line. Answer spec questions from these exactly. If a spec is not in a watch's line, it is not on file: say you don't have it for that watch rather than guessing.
- Only discuss specific watches from the list above — never invent specs/prices for a watch not on this list. If asked about a specific watch not on this list, say you can only discuss their current recommendations and suggest they browse the full catalog or search for it directly. Questions about the app itself or the general domain (see above) are welcome, not off-topic.
- If asked about color (e.g. "do you have a red watch", "which ones are rose gold"), check the color(s) listed with each watch above and answer from that exactly — if none match, say so plainly rather than guessing or suggesting the closest thing as if it matched.
- Describe colors in plain language only (e.g. "burgundy", "teal") — never state a hex code like "#6F1011" to the customer, even if they ask for one; explain you don't expose technical color codes and give the plain-language name instead.
- If asked which watches are for men, women, or unisex, use each watch's "suited for" value exactly. If it says "Not specified", say plainly that watch hasn't been categorized yet — never guess based on its name, size, or color.
- When asked "which is best for X", pick from the list using the match scores, fit notes, and budget as your basis, and explain briefly why.
- When you state a watch's match score, if it has a confidence caveat noted (e.g. "Based on style only"), mention that caveat too — don't present a high percentage as full confidence when it's actually based on one or two signals.
- Be honest about match quality, using the label next to each score above: "Great match" and "Good match" can be recommended normally; "Fair match" should be presented as only a partial fit, naming the weak signal; "Weak match" and "Poor match" must NOT be recommended as good for the customer — say plainly it's a poor match and why, and steer them to a higher-scoring watch instead. Never round a low score up into a positive recommendation just to be agreeable.
- For any question about water, swimming, showering, rain, sweat, mud, or what activities a watch can handle, follow the WATER RESISTANCE GUIDANCE above strictly. Quote the listed rating, then answer plainly from the guidance. Lean cautious: if the activity is beyond the rating, or the rating is not listed, say it is not suitable or that you cannot confirm it. Never call a watch waterproof.
- Keep replies short and conversational — a few sentences, not an essay. Use watch names so the customer can find them on screen.
- If asked something not covered by the data above (stock, warranty, exact availability), say you don't have that info and suggest using each watch's "Inquire via Urbane Time" button.

RESPONSE FORMAT: always reply with a JSON object that has exactly three fields.
- "text": your normal conversational reply, written exactly as you would have written it before (short, friendly, same rules as above).
- "watchIds": a list of watch IDs to show as tappable cards under your reply. An ID is the value after "id:" in the watch list above.
- "actions": a list of buttons to show under your reply. Each button is an object with a "type" and, only for watch-specific types, a "watchId".
Rules for "watchIds":
- Include a watch's ID only when the customer's latest message itself asks to see, open, find, or look at a watch, asks you to recommend or compare watches, or asks for photos or pictures. Never volunteer cards the customer did not ask for. Greetings (like "hi" or "hello"), thanks, small talk, and questions about the app or the general domain always get an empty list. Include at most 3 IDs.
- Questions ABOUT a watch (its color, size, materials, water resistance, price, fit, how it compares, whether it suits them) get an empty list. The customer can already see the watch, so do not attach a card to a follow-up answer.
- A request for more or different watches counts as asking for watches. If the customer says things like "another", "another one", "more", "other options", "something different", "what else", "next", or asks for a cheaper or similar alternative, show 1 to 3 watches from the list that you have NOT shown earlier in this conversation, and say they are shown below. If every fitting watch was already shown, say so in words and leave the list empty.
- Never repeat a card for a watch you already showed earlier in this conversation, unless the customer asks to see it again. Your earlier replies are shown to you as JSON, so check their "watchIds" to see what was already shown.
- Cards are how you show photos. Each card displays the watch's photo and opens its full detail screen when tapped. So never say you cannot show photos or images. When you do show a card, say the watch is shown below.
- If the customer asks for photos or pictures without naming a watch, show the watches you were just discussing. If none were being discussed, show the top 3 matches from the list.
- Only use IDs copied exactly from the list above. Never invent or guess an ID.
- Never write an ID, or the word "id", inside "text". Name the watch in plain words instead.
- Every watch whose ID you include must also be named in "text", so the reply still makes sense on its own.
Rules for "actions" (the customer taps these buttons themselves; you only offer them, you never do the action):
- "measure_wrist": opens the wrist measurement screen. Offer it when wrist width is "not provided" and the customer asks about fit, or asks how to measure or re-measure their wrist.
- "scan_outfit": opens the outfit scan screen. Offer it when the outfit scan is "not done yet" and the customer asks about color matching, or asks to scan or redo their outfit.
- "edit_preferences": opens their profile to change style preferences and budget. Offer it when style preferences are "not set yet" and the customer asks about style, or asks to change their style or budget.
- "try_on" (needs "watchId"): opens AR try-on with that watch. Offer it when the customer asks to try a watch on, see it on their wrist, or use AR.
- "save_watch" (needs "watchId"): saves that watch to their wishlist. Offer it when the customer says they like a watch or want to save, shortlist, or keep it.
- "view_saved": opens their saved watches. Offer it when they ask about their saved or wishlist watches.
- If wrist width is "not provided" and the customer asks which watches fit (or will fit) their wrist, do NOT show any watch cards and do not rank or name watches by fit. Every fit score is only a neutral placeholder until the wrist is measured. Say you need their wrist measurement first, and offer "measure_wrist".
- Offer an action only when it directly helps with what the customer just asked. Most replies should have an empty "actions" list. Offer at most 2 actions.
- Do not offer the same action again if one of your recent replies already did, unless the customer asks for it again. Your earlier replies are shown to you as JSON, so check their "actions".
- Only use "watchId" values copied exactly from the list above. Never write that you have already measured, scanned, saved, or opened something. You only offer the button.
EXAMPLES (customer message, then your JSON reply):
- Customer: "how does the scoring work?" -> {"text": "<short explanation>", "watchIds": [], "actions": []}
- Customer: "hi" -> {"text": "<short friendly greeting that asks what they would like help with>", "watchIds": [], "actions": []}
- Customer: "thanks!" -> {"text": "<short friendly reply>", "watchIds": [], "actions": []}
- Customer: "another" (after you showed a watch) -> {"text": "<names a different watch you have not shown yet, shown below>", "watchIds": ["<ID of a watch not shown earlier>"], "actions": []}
- Customer: "really?" -> {"text": "<short answer>", "watchIds": [], "actions": []}
- Customer: "which watch is best for work?" -> {"text": "<names the best match, shown below>", "watchIds": ["<ID copied from the list>"], "actions": []}
- Customer: "is it waterproof?" (about a watch already shown) -> {"text": "<answer from its specs>", "watchIds": [], "actions": []}
- Customer: "show me a rose gold watch" -> {"text": "<names the watch>, shown below.", "watchIds": ["<ID copied from the list>"], "actions": []}
- Customer: "will these fit me?" while wrist width is "not provided" -> {"text": "<explain you need their wrist width>", "watchIds": [], "actions": [{"type": "measure_wrist"}]}
- Customer: "i like the first one" -> {"text": "<short reply naming that watch>", "watchIds": [], "actions": [{"type": "save_watch", "watchId": "<ID copied from the list>"}]}
- Customer: "can I try it on?" -> {"text": "Yes! Tap the button below to try it on in AR.", "watchIds": [], "actions": [{"type": "try_on", "watchId": "<ID copied from the list>"}]}
- Customer: "can I save it?" -> {"text": "Tap the Save button below to add it to your wishlist.", "watchIds": [], "actions": [{"type": "save_watch", "watchId": "<ID copied from the list>"}]}
You cannot save, measure, scan, or open anything yourself. Never say "I have saved it" or similar. Say to tap the button below instead.
''';
  }

  /// Sends [userText] and returns the model's reply, appending both to
  /// the in-memory conversation history.
  Future<ChatReply> sendMessage(String userText) async {
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
      'contents': [
        for (var i = 0; i < _history.length; i++)
          {
            'role': _history[i].role,
            'parts': [
              {
                'text': _historyText(_history[i]) +
                    // Restated on the latest message only: a small model
                    // follows the most recent text far more closely than
                    // the system prompt, and tends to copy the card
                    // pattern of its own earlier replies otherwise.
                    (_allowedWatchIds != null && i == _history.length - 1
                        ? _formatReminder
                        : ''),
              },
            ],
          },
      ],
      if (_allowedWatchIds != null)
        'generationConfig': {
          'responseMimeType': 'application/json',
          'responseSchema': {
            'type': 'OBJECT',
            'properties': {
              'text': {
                'type': 'STRING',
                'description': 'Your short, friendly reply to the customer.',
              },
              'watchIds': {
                'type': 'ARRAY',
                'description': 'Watch IDs to show as cards. Use an empty '
                    'list unless the latest customer message itself asks '
                    'to see, open, find, or get photos of a watch, asks for '
                    'a recommendation, or asks for another, more, or '
                    'different watches (use watches not shown yet). '
                    'Greetings, thanks, small talk, questions about a '
                    'watch already shown, and general questions always '
                    'get an empty list.',
                'items': {'type': 'STRING'},
              },
              'actions': {
                'type': 'ARRAY',
                'description': 'Buttons to offer. Use an empty list unless '
                    'a button directly helps with what the customer just '
                    'asked.',
                'items': {
                  'type': 'OBJECT',
                  'properties': {
                    'type': {'type': 'STRING'},
                    'watchId': {'type': 'STRING'},
                  },
                  'required': ['type'],
                },
              },
            },
            'required': ['text'],
          },
        },
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

      final allowed = _allowedWatchIds;
      if (allowed != null && kDebugMode) {
        debugPrint('ChatService raw reply: $reply');
      }
      final parsed = allowed == null
          ? ChatReply(text: reply)
          : _withIntentActions(
              _withFitGuard(
                _resolveActionWatches(
                  _withoutRepeatedCards(
                    _withoutCardsOnSmallTalk(
                      _parseStructuredReply(reply, allowed),
                      userText,
                    ),
                    userText,
                  ),
                ),
                userText,
              ),
              userText,
            );
      _history.add(ChatMessage(
        role: 'model',
        text: parsed.text,
        watchIds: parsed.watchIds,
        actions: parsed.actions,
      ));
      return parsed;
    } catch (e) {
      // Roll back the user message so a failed turn doesn't pollute
      // history sent on the next attempt.
      _history.removeLast();
      if (e is String) rethrow;
      throw 'Could not reach the assistant. Check your connection and try again.';
    }
  }

  // A message that is ONLY a greeting, thanks, or other small talk. This
  // is deliberately narrow: people ask for watches in too many ways to
  // list ("give me", "where is it", "got any"...), so cards are only
  // stripped for messages that clearly are not requests at all.
  static final RegExp _smallTalk = RegExp(
    r'^\s*(hi+|hello+|hey+|heya|yo|hola|sup|good\s+(morning|afternoon|'
    r'evening|day)|thanks?|thank\s+you|thx|ty|ok(ay)?|k|cool|nice|great|'
    r'awesome|got\s+it|bye|goodbye|salamat|kumusta|kamusta)'
    r'(\s+(there|po|ai|so\s+much|a\s+lot|virtuwatch(\s+ai)?))?'
    r'[\s!.?,]*$',
    caseSensitive: false,
  );

  // The reply text promises cards ("shown below").
  static final RegExp _pointsBelow = RegExp(r'\bbelow\b', caseSensitive: false);

  /// App-side safety net behind the prompt rules: a small model tends to
  /// attach its top matches to a plain "hi", so cards are removed when the
  /// customer's whole message is just a greeting or thanks. Anything else
  /// is left to the model. If the reply text itself says the watch is
  /// "shown below", the cards stay, so a reply never promises a card and
  /// then shows nothing. The text and action buttons are left as written.
  ChatReply _withoutCardsOnSmallTalk(ChatReply reply, String userText) {
    if (reply.watchIds.isEmpty ||
        !_smallTalk.hasMatch(userText) ||
        _pointsBelow.hasMatch(reply.text)) {
      return reply;
    }
    return ChatReply(
      text: reply.text,
      watchIds: const [],
      actions: reply.actions,
    );
  }

  // Follow-up requests for other watches ("another", "more", "what else").
  static final RegExp _asksForMore = RegExp(
    r'\b(another|other|others|more|next|different|else|alternative|'
    r'alternatives|similar|instead|iba|ibang)\b|\b(what|how) about\b',
    caseSensitive: false,
  );

  static final RegExp _asksToShow = RegExp(
    r'\b(show|see|again|ulit|photo|photos|picture|pictures|pic|pics|image|'
    r'images|larawan|litrato|open|look|display|where|give)\b',
    caseSensitive: false,
  );

  /// App-side safety net behind the prompt rules: a watch that already
  /// appeared as a card earlier in this chat is not shown again unless the
  /// customer's message asks to see things ("show", "again", "photo"...).
  /// Without this, a small model that has shown a card once tends to
  /// attach it to every later reply.
  ChatReply _withoutRepeatedCards(ChatReply reply, String userText) {
    if (reply.watchIds.isEmpty || _asksToShow.hasMatch(userText)) return reply;
    final shownBefore = {
      for (final m in _history)
        if (m.role == 'model') ...m.watchIds,
    };
    final fresh =
        reply.watchIds.where((id) => !shownBefore.contains(id)).toList();
    if (fresh.length == reply.watchIds.length) return reply;
    // Dropping every pick would leave a reply that says "shown below"
    // with nothing below it (or answer "another" with nothing). Better to
    // keep the model's pick than to show an empty reply.
    if (fresh.isEmpty &&
        (_asksForMore.hasMatch(userText) || _pointsBelow.hasMatch(reply.text))) {
      return reply;
    }
    return ChatReply(
      text: reply.text,
      watchIds: fresh,
      actions: reply.actions,
    );
  }

  /// Fills in a missing watch for "try on" / "save" buttons. Models often
  /// send `{"type": "try_on"}` with no watchId when the customer says
  /// "can I try them on?". The watch is clear from context: the cards in
  /// this same reply, or else the most recent cards shown in the chat. One
  /// button is made per watch (up to the per-reply cap).
  ChatReply _resolveActionWatches(ChatReply reply) {
    final needsFill =
        reply.actions.any((a) => a.needsWatch && a.watchId == null);
    if (!needsFill) return reply;

    var candidates = reply.watchIds;
    if (candidates.isEmpty) {
      for (final m in _history.reversed) {
        if (m.role == 'model' && m.watchIds.isNotEmpty) {
          candidates = m.watchIds;
          break;
        }
      }
    }

    final resolved = <ChatAction>[];
    void addUnique(ChatAction action) {
      final duplicate = resolved.any(
        (a) => a.type == action.type && a.watchId == action.watchId,
      );
      if (!duplicate) resolved.add(action);
    }

    for (final action in reply.actions) {
      if (action.needsWatch && action.watchId == null) {
        for (final id in candidates) {
          addUnique(ChatAction(type: action.type, watchId: id));
        }
      } else {
        addUnique(action);
      }
    }

    return ChatReply(
      text: reply.text,
      watchIds: reply.watchIds,
      actions: resolved.take(_maxActionsPerReply).toList(),
    );
  }

  // A question about whether watches fit the customer's wrist. "Which fits
  // my budget" is not one, so budget/price/style/color words are excluded.
  static final RegExp _fitIntent = RegExp(
    r'\b(fit|fits|fitting)\b.{0,20}\bwrist\b'
    r'|\bwrist\b.{0,20}\b(fit|fits|size|sizes)\b'
    r'|\b(will|do|does|would|can|should)\b.{0,20}\b(fit|fits)\b'
    r'(?!.{0,10}\b(budget|price|style|outfit|color|colour)\b)'
    r'|\btoo (big|large|small|wide)\b|\bwrist size\b|\bkasya\b',
    caseSensitive: false,
  );

  static final RegExp _tryOnIntent = RegExp(
    r'\btry(ing)?\b.{0,20}\b(on|it|them|this|that|these)\b'
    r'|\b(ar|augmented reality)\b|subukan|isukat',
    caseSensitive: false,
  );
  // Wanting to save a watch is often said without the word "save":
  // "I like it", "love this one", "gusto ko ito". Only phrases that point
  // at a specific watch count, so "I like dress watches" does not.
  static final RegExp _saveIntent = RegExp(
    r'\b(save|wishlist|shortlist|bookmark)\b|\bi-?save\b'
    r'|\b(i|we)\s+(really\s+|do\s+|just\s+)?(like|love|want)\s+'
    r'(it|that|this|these|them|the\b.{0,25}\bone)\b'
    r'|\bgusto ko (ito|yan|iyan)\b',
    caseSensitive: false,
  );
  static final RegExp _viewSavedIntent = RegExp(
    r'\b(my|view|show|open|see)\b.{0,15}\b(saved|wishlist)\b',
    caseSensitive: false,
  );
  static final RegExp _measureIntent = RegExp(
    r'\b(re-?measure|measure)\b.{0,25}\bwrist\b'
    r'|\bwrist\b.{0,25}\b(re-?measure|measure)\b',
    caseSensitive: false,
  );
  static final RegExp _scanIntent = RegExp(
    r'\b(re-?scan|scan)\b.{0,25}\boutfit\b'
    r'|\boutfit\b.{0,25}\b(re-?scan|scan)\b',
    caseSensitive: false,
  );
  static final RegExp _prefsIntent = RegExp(
    r'\b(change|update|edit)\b.{0,25}\b(preferences?|style|budget)\b',
    caseSensitive: false,
  );

  /// When the customer has no wrist measurement, every watch's fit score is
  /// just a neutral placeholder (so every watch shows the same ~50%).
  /// Showing watch cards as the answer to "which fits my wrist?" would
  /// look like a real ranking, so for fit questions in that state the app
  /// removes the cards and makes sure the "Measure my wrist" button is
  /// there, whatever the model sent.
  ChatReply _withFitGuard(ChatReply reply, String userText) {
    final result = _result;
    if (result == null || result.wristWidthMm != null) return reply;
    if (!_fitIntent.hasMatch(userText)) return reply;

    final hasMeasure =
        reply.actions.any((a) => a.type == ChatAction.measureWrist);
    final actions = hasMeasure
        ? reply.actions
        : [
            const ChatAction(type: ChatAction.measureWrist),
            ...reply.actions,
          ].take(_maxActionsPerReply).toList();
    return ChatReply(text: reply.text, actions: actions);
  }

  /// Safety net for action buttons. A small model sometimes says "tap the
  /// button below" without actually sending one. When the model sent no
  /// buttons at all, the app looks at the customer's own message for a
  /// clear, direct request ("try them on", "can I save it", "how do I
  /// measure my wrist") and adds the matching button itself. Buttons the
  /// model did send always win; this never adds to them.
  ChatReply _withIntentActions(ChatReply reply, String userText) {
    if (reply.actions.isNotEmpty) return reply;

    final actions = <ChatAction>[];
    void add(ChatAction action) {
      final duplicate = actions.any(
        (a) => a.type == action.type && a.watchId == action.watchId,
      );
      if (!duplicate && actions.length < _maxActionsPerReply) {
        actions.add(action);
      }
    }

    if (_measureIntent.hasMatch(userText)) {
      add(const ChatAction(type: ChatAction.measureWrist));
    }
    if (_scanIntent.hasMatch(userText)) {
      add(const ChatAction(type: ChatAction.scanOutfit));
    }
    if (_prefsIntent.hasMatch(userText)) {
      add(const ChatAction(type: ChatAction.editPreferences));
    }

    final asksForSavedList = _viewSavedIntent.hasMatch(userText);
    if (asksForSavedList) add(const ChatAction(type: ChatAction.viewSaved));

    final wantsTryOn = _tryOnIntent.hasMatch(userText);
    final wantsSave = !asksForSavedList && _saveIntent.hasMatch(userText);
    if (wantsTryOn || wantsSave) {
      for (final id in _watchesInContext(reply, userText)) {
        if (wantsTryOn) add(ChatAction(type: ChatAction.tryOn, watchId: id));
        if (wantsSave) add(ChatAction(type: ChatAction.saveWatch, watchId: id));
      }
    }

    if (actions.isEmpty) return reply;
    return ChatReply(
      text: reply.text,
      watchIds: reply.watchIds,
      actions: actions,
    );
  }

  /// The watch(es) a customer is most likely talking about: the cards in
  /// this reply, else the most recent cards shown in the chat. If their
  /// message names one of them (by a word from its name), only that one.
  List<String> _watchesInContext(ChatReply reply, String userText) {
    var candidates = reply.watchIds;
    if (candidates.isEmpty) {
      for (final m in _history.reversed) {
        if (m.role == 'model' && m.watchIds.isNotEmpty) {
          candidates = m.watchIds;
          break;
        }
      }
    }
    if (candidates.length < 2) return candidates;

    final text = userText.toLowerCase();
    final named = candidates.where((id) {
      final name = _watchName(id)?.toLowerCase() ?? '';
      return name
          .split(RegExp(r'\W+'))
          .where((word) => word.length >= 4)
          .any(text.contains);
    }).toList();
    return named.isNotEmpty ? named : candidates;
  }

  String? _watchName(String watchId) {
    final recs = _result?.recommendations;
    if (recs == null) return null;
    for (final r in recs) {
      if (r.watchId == watchId) return r.data['name'] as String?;
    }
    return null;
  }

  /// How a past message is replayed to the model. In structured mode the
  /// assistant's earlier replies go back as the same JSON shape it is
  /// asked to produce, so it can see which watches it already showed as
  /// cards (and doesn't repeat them on every turn).
  String _historyText(ChatMessage m) {
    if (_allowedWatchIds == null || m.role != 'model') return m.text;
    return jsonEncode({
      'text': m.text,
      'watchIds': m.watchIds,
      'actions': m.actions.map((a) => a.toJson()).toList(),
    });
  }

  /// Reads the model's JSON reply. Never throws: if the reply isn't the
  /// expected JSON, the raw text is shown as-is with no cards, so a
  /// formatting slip by the model costs a card, not the whole answer.
  /// Watch IDs not in [allowed] are dropped, duplicates are removed, and
  /// the list is capped at [_maxCardsPerReply]. Actions are held to the
  /// same standard: unknown types and unknown watches are dropped, and the
  /// list is capped at [_maxActionsPerReply].
  static ChatReply _parseStructuredReply(String raw, Set<String> allowed) {
    try {
      var json = raw.trim();
      if (json.startsWith('```')) {
        json = json
            .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
            .replaceFirst(RegExp(r'\s*```$'), '');
      }
      final decoded = jsonDecode(json);
      if (decoded is! Map) return ChatReply(text: raw);

      final text = (decoded['text'] as String? ?? '').trim();
      final ids = <String>[];
      for (final id in (decoded['watchIds'] as List? ?? const [])) {
        if (id is String && allowed.contains(id) && !ids.contains(id)) {
          ids.add(id);
        }
        if (ids.length == _maxCardsPerReply) break;
      }

      final actions = <ChatAction>[];
      for (final rawAction in (decoded['actions'] as List? ?? const [])) {
        final action = ChatAction.fromJson(rawAction);
        if (action == null) continue;
        // A watch-specific action that names a watch must name one the
        // assistant was actually given. One with no watch named at all is
        // kept here and filled in by [_resolveActionWatches].
        if (action.needsWatch &&
            action.watchId != null &&
            !allowed.contains(action.watchId)) {
          continue;
        }
        final duplicate = actions.any(
          (a) => a.type == action.type && a.watchId == action.watchId,
        );
        if (duplicate) continue;
        actions.add(action);
        if (actions.length == _maxActionsPerReply) break;
      }

      if (text.isEmpty && ids.isEmpty && actions.isEmpty) {
        return ChatReply(text: raw);
      }
      return ChatReply(
        text: text.isEmpty ? 'Here you go:' : text,
        watchIds: ids,
        actions: actions,
      );
    } catch (_) {
      debugPrint('ChatService: reply was not valid JSON, showing as plain text: $raw');
      return ChatReply(text: raw);
    }
  }
}