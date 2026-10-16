import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../constants/watch_colors.dart';
import '../services/cloudinary_service.dart';
import '../theme/app_theme.dart';
import '../utils/ar_readiness.dart';
import '../utils/form_validators.dart';
import 'luxe.dart';
import 'network_photo.dart';
import 'watch_color_picker.dart';
import 'watch_color_wheel_picker.dart';

TextStyle get _muted =>

    TextStyle(color: AppTheme.textSecondary, fontSize: 12);

/// Every field of a watch listing, shared by the add and edit screens.
///
/// Pass the watch's saved fields as [initialData] to edit it, or nothing to
/// start a new one. The screen owns the save button and calls
/// [WatchFormState.collect] on it, then writes the result.
class WatchForm extends StatefulWidget {
  final Map<String, dynamic> initialData;

  /// Shown above everything else, e.g. the admin's merchant picker.
  final Widget? header;

  /// Shows the AR fit section (admin only). The numbers it holds decide how
  /// the 3D model sits on the wrist; Firestore rules also block non-admins
  /// from writing them, so this flag is a convenience, not the security.
  final bool showArFit;

  const WatchForm({
    super.key,
    this.initialData = const {},
    this.header,
    this.showArFit = false,
  });

  @override
  State<WatchForm> createState() => WatchFormState();
}

class WatchFormState extends State<WatchForm> {
  static const _maxPhotos = 5;
  static const _styles = [
    'Sport', 'Classic', 'Luxury', 'Casual', 'Minimalist', 'Dress', //
  ];
  static const _genders = ["Men's", "Women's", 'Unisex'];
  static const _textKeys = [
    'name', 'brand', 'price', 'caseDiameterMm', 'caseThicknessMm', //
    'lugToLugMm', 'bandWidthMm', 'bandMaterial', 'caseMaterial',
    'movementType', 'waterResistance',
  ];

  final _formKey = GlobalKey<FormState>();
  final _cloudinary = CloudinaryService();

  /// Whole numbers show without a trailing ".0".
  static String _text(dynamic v) =>
      v is num && v == v.roundToDouble() ? '${v.toInt()}' : '${v ?? ''}';

  late final _fields = {
    for (final k in _textKeys)
      k: TextEditingController(text: _text(widget.initialData[k])),
  };

  late String _style = widget.initialData['styleCategory'] as String? ?? 'Sport';
  // Null means "not specified". It is never defaulted to a real value, since
  // a wrong gender guess is worse than an honest gap.
  late String? _gender = widget.initialData['targetGender'] as String?;
  late bool _listed = widget.initialData['listedInCatalog'] as bool? ?? true;

  // Watches saved before multi-color or multi-photo support only have a
  // single `colorHex` or `imageUrl`; those count as the one existing value.
  late final List<String> _colorHexes = () {
    final d = widget.initialData;
    final hexes = (d['colorHexes'] as List?)?.cast<String>() ?? [];
    final legacy = d['colorHex'] as String? ?? '';
    return hexes.isNotEmpty
        ? List<String>.of(hexes)
        : [legacy.isNotEmpty ? legacy : watchColorPalette.first.hex];
  }();
  String _customColorHex = watchColorPalette.first.hex;
  bool _showCustomColor = false;

  late final List<String> _imageUrls = () {
    final d = widget.initialData;
    final urls = (d['imageUrls'] as List?)?.cast<String>() ?? [];
    final legacy = d['imageUrl'] as String? ?? '';
    return urls.isNotEmpty
        ? List<String>.of(urls)
        : [if (legacy.isNotEmpty) legacy];
  }();
  final List<File> _newImages = [];
  bool _uploadingPhotos = false;

  late final String _modelUrl = widget.initialData['modelUrl'] as String? ?? '';
  File? _modelFile;
  bool _uploadingModel = false;
  String? _modelError;

  // AR fit (admin only): measured strap-opening numbers for THIS model file.
  // Prefilled only when the saved fit belongs to the model that is attached
  // now (ArFit.tryParse checks that), so numbers measured for an old model
  // are never carried over to a replacement.
  late final ArFit? _savedFit = ArFit.tryParse(widget.initialData);
  late final _fitCx = TextEditingController(text: _fitText(_savedFit?.holeCx));
  late final _fitHalfX =
      TextEditingController(text: _fitText(_savedFit?.holeHalfX));
  late final _fitHalfY =
      TextEditingController(text: _fitText(_savedFit?.holeHalfY));
  // Blank means the default of 1.0.
  late final _fitScale = TextEditingController(
      text: (_savedFit != null && _savedFit!.scale != 1.0)
          ? _text(_savedFit!.scale)
          : '');

  static String _fitText(double? v) => v == null ? '' : _text(v);

  int get _photoCount => _imageUrls.length + _newImages.length;
  bool get _hasModel => _modelFile != null || _modelUrl.isNotEmpty;

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    _fitCx.dispose();
    _fitHalfX.dispose();
    _fitHalfY.dispose();
    _fitScale.dispose();
    super.dispose();
  }

  /// Validates the form, uploads any new photos and 3D model, and returns
  /// the fields to save. Returns null if validation fails.
  Future<Map<String, dynamic>?> collect() async {
    if (!_formKey.currentState!.validate()) return null;

    // Only newly picked files are uploaded. Hosted URLs are kept as they are.
    final uploaded = <String>[];
    if (_newImages.isNotEmpty) {
      setState(() => _uploadingPhotos = true);
      try {
        for (final file in _newImages) {
          uploaded.add(await _cloudinary.uploadImage(file));
        }
      } finally {
        if (mounted) setState(() => _uploadingPhotos = false);
      }
    }
    final imageUrls = [..._imageUrls, ...uploaded];

    var modelUrl = _modelUrl;
    if (_modelFile != null) {
      setState(() => _uploadingModel = true);
      try {
        modelUrl = await _cloudinary.uploadModel(_modelFile!);
      } finally {
        if (mounted) setState(() => _uploadingModel = false);
      }
    }

    String t(String key) => _fields[key]!.text.trim();
    double? n(String key) => double.tryParse(t(key));

    final data = <String, dynamic>{
      'name': t('name'),
      'brand': t('brand'),
      'price': double.parse(t('price')),
      'styleCategory': _style,
      'targetGender': _gender,
      'colorHex': _colorHexes.first,
      'colorHexes': List<String>.of(_colorHexes),
      'caseDiameterMm': n('caseDiameterMm'),
      'caseThicknessMm': n('caseThicknessMm'),
      'lugToLugMm': double.parse(t('lugToLugMm')),
      'bandWidthMm': n('bandWidthMm'),
      'bandMaterial': t('bandMaterial'),
      'caseMaterial': t('caseMaterial'),
      'movementType': t('movementType'),
      'waterResistance': t('waterResistance'),
      'listedInCatalog': _listed,
      'imageUrl': imageUrls.isNotEmpty ? imageUrls.first : '',
      'imageUrls': imageUrls,
      'modelUrl': modelUrl,
      'has3DModel': modelUrl.isNotEmpty,
    };

    // Only the admin form writes arFit. For anyone else the key is left out,
    // so an edit never touches it. (If a merchant replaces the model, the saved
    // fit no longer matches the new file and the watch drops out of AR until an
    // admin enters numbers for the new file.)
    if (widget.showArFit) {
      final fit = _buildArFit(modelUrl);
      if (fit != null) {
        data['arFit'] = fit;
      } else if (widget.initialData.containsKey('arFit')) {
        // Cleared (or stale after a model change): remove it. Only edits ever
        // have initialData, and those use update(), where delete() is valid.
        data['arFit'] = FieldValue.delete();
      }
    }
    return data;
  }

  Future<void> _pickImages() async {
    final remaining = _maxPhotos - _photoCount;
    if (remaining <= 0) return;
    final images = await _cloudinary.pickMultipleImages();
    if (images.isNotEmpty) {
      setState(() => _newImages.addAll(images.take(remaining)));
    }
  }

  Future<void> _pickModel() async {
    try {
      final file = await _cloudinary.pickModelFile();
      if (file != null) {
        setState(() {
          _modelFile = file;
          _modelError = null;
          // Whatever was entered described the previous model file.
          _fitCx.clear();
          _fitHalfX.clear();
          _fitHalfY.clear();
          _fitScale.clear();
        });
      }
    } catch (e) {
      setState(() => _modelError = e.toString());
    }
  }

  /// Tapping a swatch adds it (up to the cap) or removes it. A watch always
  /// keeps at least one color, and the first is its primary.
  void _toggleColor(String hex) {
    final index =
        _colorHexes.indexWhere((c) => c.toUpperCase() == hex.toUpperCase());
    setState(() {
      if (index >= 0) {
        if (_colorHexes.length > 1) _colorHexes.removeAt(index);
      } else if (_colorHexes.length < maxWatchColors) {
        _colorHexes.add(hex);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ?widget.header,
          luxeSection(
            'PHOTOS',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 96,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _photoCount + (_photoCount < _maxPhotos ? 1 : 0),
                    separatorBuilder: (context, i) => const SizedBox(width: 10),
                    itemBuilder: (context, i) =>
                        i == _photoCount ? _addPhotoTile() : _photoTile(i),
                  ),
                ),
                if (_uploadingPhotos)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
              ],
            ),
            trailing: Text('$_photoCount / $_maxPhotos', style: kLabelStyle),
          ),
          luxeSection('3D MODEL', _modelRow()),
          if (widget.showArFit && _hasModel)
            luxeSection('AR FIT', _arFitEditor()),
          luxeSection(
            'DETAILS',
            Column(
              children: [
                _field('Watch name *', 'name',
                    hint: 'e.g. Seiko Prospex SPB143J1',
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null),
                const SizedBox(height: 16),
                _field('Brand', 'brand', hint: 'e.g. Seiko'),
                const SizedBox(height: 16),
                _field('Price (PHP) *', 'price',
                    hint: 'e.g. 15000',
                    number: true,
                    validator: requiredPositiveNumber),
              ],
            ),
          ),
          luxeSection(
            'STYLE',
            _pills(_styles, (s) => s == _style, (s) => _style = s),
          ),
          luxeSection(
            'TARGET GENDER',
            _pills(['Not specified', ..._genders], (g) {
              return g == 'Not specified' ? _gender == null : g == _gender;
            }, (g) => _gender = g == 'Not specified' ? null : g),
          ),
          luxeSection(
            'COLORS',
            _colorsEditor(),
            trailing:
                Text('${_colorHexes.length} / $maxWatchColors', style: kLabelStyle),
          ),
          luxeSection(
            'SPECIFICATIONS',
            Column(
              children: [
                _pair(_field('Case diameter (mm)', 'caseDiameterMm',
                        number: true, validator: optionalPositiveNumber),
                    _field('Case thickness (mm)', 'caseThicknessMm',
                        number: true, validator: optionalPositiveNumber)),
                _pair(_field('Lug-to-lug (mm) *', 'lugToLugMm',
                        number: true, validator: requiredPositiveNumber),
                    _field('Band width (mm)', 'bandWidthMm',
                        number: true, validator: optionalPositiveNumber)),
                _pair(_field('Band material', 'bandMaterial'),
                    _field('Case material', 'caseMaterial')),
                _pair(_field('Movement', 'movementType'),
                    _field('Water resistance', 'waterResistance'),
                    last: true),
              ],
            ),
          ),
          luxeSection(
            'LISTING',
            Row(
              children: [
                Expanded(
                  child: Text('Listed in catalog',
                      style: TextStyle(
                          color: AppTheme.textPrimary, fontSize: 14)),
                ),
                Switch(
                  value: _listed,
                  activeThumbColor: AppTheme.gold,
                  onChanged: (v) => setState(() => _listed = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _field(String label, String key,
      {String? hint,
      bool number = false,
      FormFieldValidator<String>? validator}) {
    return TextFormField(
      controller: _fields[key],
      style: const TextStyle(fontSize: 15),
      keyboardType:
          number ? const TextInputType.numberWithOptions(decimal: true) : null,
      validator: validator,
      decoration: luxeFieldDecoration(hint: hint).copyWith(
        labelText: label,
        labelStyle:
            TextStyle(color: AppTheme.textSecondary, fontSize: 13),
      ),
    );
  }

  /// Two fields side by side, with a gap below unless [last].
  Widget _pair(Widget a, Widget b, {bool last = false}) => Padding(
        padding: EdgeInsets.only(bottom: last ? 0 : 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: a),
            const SizedBox(width: 16),
            Expanded(child: b),
          ],
        ),
      );

  /// Single-select pills.
  Widget _pills(List<String> options, bool Function(String) isSelected,
      void Function(String) onSelect) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final option in options)
          luxePill(option,
              selected: isSelected(option),
              onTap: () => setState(() => onSelect(option))),
      ],
    );
  }

  Widget _link(String label, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(label,
              style: kLabelStyle.copyWith(color: AppTheme.textPrimary)),
        ),
      );

  Widget _addPhotoTile() => InkWell(
        onTap: _uploadingPhotos ? null : _pickImages,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.outline),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, size: 22, color: AppTheme.textSecondary),
              SizedBox(height: 4),
              Text('ADD',
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 10,
                      letterSpacing: 1.2)),
            ],
          ),
        ),
      );

  Widget _photoTile(int i) {
    final isHosted = i < _imageUrls.length;
    final fallback =
        Center(child: Icon(Icons.watch, color: AppTheme.textSecondary));

    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 96,
            height: 96,
            child: ColoredBox(
              color: AppTheme.surface,
              child: isHosted
                  ? NetworkPhoto(url: _imageUrls[i], errorWidget: fallback)
                  : Image.file(_newImages[i - _imageUrls.length],
                      fit: BoxFit.cover),
            ),
          ),
        ),
        if (i == 0)
          Positioned(
            left: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('COVER',
                  style: TextStyle(
                      color: Colors.white, fontSize: 9, letterSpacing: 1)),
            ),
          ),
        Positioned(
          right: 4,
          top: 4,
          child: GestureDetector(
            onTap: () => setState(() => isHosted
                ? _imageUrls.removeAt(i)
                : _newImages.removeAt(i - _imageUrls.length)),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                  color: Colors.black54, shape: BoxShape.circle),
              child: const Icon(Icons.close, size: 13, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // AR fit (admin only)
  // ---------------------------------------------------------------------

  bool get _fitAnyFilled => [_fitCx, _fitHalfX, _fitHalfY, _fitScale]
      .any((c) => c.text.trim().isNotEmpty);

  static double? _inRange(TextEditingController c, double min, double max) {
    final d = double.tryParse(c.text.trim());
    return (d != null && d.isFinite && d >= min && d <= max) ? d : null;
  }

  /// Three required numbers in range, and the size multiplier blank or in range.
  bool get _fitComplete =>
      _inRange(_fitCx, arHoleCxMin, arHoleCxMax) != null &&
      _inRange(_fitHalfX, arHalfXMin, arHalfXMax) != null &&
      _inRange(_fitHalfY, arHalfYMin, arHalfYMax) != null &&
      (_fitScale.text.trim().isEmpty ||
          _inRange(_fitScale, arScaleMin, arScaleMax) != null);

  /// The map stored on the watch, tied to [modelUrl]. Null when the fit is blank.
  Map<String, dynamic>? _buildArFit(String modelUrl) {
    if (modelUrl.isEmpty || !_fitComplete) return null;
    final scale = double.tryParse(_fitScale.text.trim());
    return {
      'modelUrl': modelUrl,
      'holeCx': double.parse(_fitCx.text.trim()),
      'holeHalfX': double.parse(_fitHalfX.text.trim()),
      'holeHalfY': double.parse(_fitHalfY.text.trim()),
      'scale': ?scale,
    };
  }

  String? _fitValidator(String? v, double min, double max,
      {required bool isRequired}) {
    final text = v?.trim() ?? '';
    if (text.isEmpty) return isRequired ? 'Required' : null;
    final d = double.tryParse(text);
    if (d == null || !d.isFinite) return 'Enter a number';
    if (d < min || d > max) return 'Between $min and $max';
    return null;
  }

  Widget _fitField(String label, TextEditingController controller,
      {required String hint,
      required double min,
      required double max,
      required bool Function() isRequired}) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(fontSize: 15),
      // signed: holeCx is negative for every measured model.
      keyboardType:
          const TextInputType.numberWithOptions(decimal: true, signed: true),
      validator: (v) => _fitValidator(v, min, max, isRequired: isRequired()),
      onChanged: (_) => setState(() {}), // refreshes the status line
      decoration: luxeFieldDecoration(hint: hint).copyWith(
        labelText: label,
        labelStyle: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
      ),
    );
  }

  Widget _arFitEditor() {
    final complete = _fitComplete;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Measured strap-opening numbers for this exact model file, in the "
          "model's own units. Leave all blank to keep the watch out of AR. "
          "Replacing the model clears them.",
          style: _muted,
        ),
        const SizedBox(height: 14),
        _fitField('Opening centre (holeCx)', _fitCx,
            hint: 'e.g. -0.057',
            min: arHoleCxMin,
            max: arHoleCxMax,
            isRequired: () => _fitAnyFilled),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _fitField('Half-thickness (holeHalfX)', _fitHalfX,
                  hint: 'e.g. 0.25',
                  min: arHalfXMin,
                  max: arHalfXMax,
                  isRequired: () => _fitAnyFilled),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _fitField('Half-width (holeHalfY)', _fitHalfY,
                  hint: 'e.g. 0.435',
                  min: arHalfYMin,
                  max: arHalfYMax,
                  isRequired: () => _fitAnyFilled),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _fitField('Size multiplier (optional)', _fitScale,
            hint: 'blank = 1.0',
            min: arScaleMin,
            max: arScaleMax,
            isRequired: () => false),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(complete ? Icons.check_circle_outline : Icons.info_outline,
                size: 16,
                color: complete ? AppTheme.textPrimary : AppTheme.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                complete
                    ? 'AR-ready once saved.'
                    : 'Not in AR yet: fit incomplete.',
                style: _muted,
              ),
            ),
            TextButton.icon(
              onPressed: _pasteFitJson,
              icon: const Icon(Icons.content_paste, size: 16),
              label: const Text('Paste JSON'),
            ),
          ],
        ),
      ],
    );
  }

  /// Fills the fields from JSON such as
  /// {"holeCx": -0.058, "holeHalfX": 0.226, "holeHalfY": 0.432, "scale": 1.0}
  /// (an object wrapped in {"arFit": {...}} also works).
  Map<String, double>? _parseFitJson(String text) {
    try {
      dynamic decoded = jsonDecode(text.trim());
      if (decoded is Map && decoded['arFit'] is Map) decoded = decoded['arFit'];
      if (decoded is! Map) return null;
      double? number(String key) {
        final v = decoded[key];
        return (v is num && v.isFinite) ? v.toDouble() : null;
      }

      final cx = number('holeCx');
      final hx = number('holeHalfX');
      final hy = number('holeHalfY');
      if (cx == null || hx == null || hy == null) return null;
      return {'holeCx': cx, 'holeHalfX': hx, 'holeHalfY': hy, 'scale': ?number('scale')};
    } catch (_) {
      return null;
    }
  }

  Future<void> _pasteFitJson() async {
    // Not disposed: the dialog is still animating out when showDialog returns,
    // and a controller with no listeners is simply garbage collected.
    final input = TextEditingController();
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Paste AR fit JSON'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: input,
                autofocus: true,
                maxLines: 6,
                decoration: const InputDecoration(
                  hintText:
                      '{"holeCx": -0.058, "holeHalfX": 0.226, "holeHalfY": 0.432}',
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!,
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 12)),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final parsed = _parseFitJson(input.text);
                if (parsed == null) {
                  setLocal(() => error =
                      'Could not read that. It needs numbers for holeCx, holeHalfX and holeHalfY.');
                  return;
                }
                setState(() {
                  _fitCx.text = _fitText(parsed['holeCx']);
                  _fitHalfX.text = _fitText(parsed['holeHalfX']);
                  _fitHalfY.text = _fitText(parsed['holeHalfY']);
                  _fitScale.text = _fitText(parsed['scale']);
                });
                Navigator.of(ctx).pop();
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modelRow() {
    final title = _uploadingModel
        ? 'Uploading model...'
        : _modelFile != null
            ? _modelFile!.path.split(Platform.pathSeparator).last
            : _modelUrl.isNotEmpty
                ? '3D model attached'
                : 'No 3D model';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: _uploadingModel ? null : _pickModel,
          child: Row(
            children: [
              if (_uploadingModel)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(_hasModel ? Icons.check : Icons.threed_rotation,
                    size: 20,
                    color: _hasModel
                        ? AppTheme.textPrimary
                        : AppTheme.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: _hasModel
                                ? AppTheme.textPrimary
                                : AppTheme.textSecondary,
                            fontSize: 14)),
                    Text(
                        widget.showArFit
                            ? 'A .glb file. Add its AR fit below to enable try-on.'
                            : 'A .glb file. AR try-on goes live once the model has been reviewed.',
                        style: _muted),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (_modelFile != null && !_uploadingModel)
                IconButton(
                  icon: Icon(Icons.close,
                      size: 18, color: AppTheme.textSecondary),
                  onPressed: () => setState(() => _modelFile = null),
                )
              else if (!_uploadingModel)
                Text(_hasModel ? 'REPLACE' : 'ATTACH',
                    style: kLabelStyle.copyWith(color: AppTheme.textPrimary)),
            ],
          ),
        ),
        if (_modelError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_modelError!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
          ),
      ],
    );
  }

  Widget _colorsEditor() {
    final atMax = _colorHexes.length >= maxWatchColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (var i = 0; i < _colorHexes.length; i++) _colorChip(i)],
        ),
        const SizedBox(height: 12),
        Text(
          atMax
              ? 'Remove a color to add another.'
              : 'Tap a swatch to add it. The first color is the primary.',
          style: _muted,
        ),
        if (!atMax) ...[
          const SizedBox(height: 12),
          WatchColorPicker(selectedHexes: _colorHexes, onChanged: _toggleColor),
          const SizedBox(height: 4),
          _link(_showCustomColor ? 'HIDE CUSTOM COLOR' : 'CUSTOM COLOR',
              () => setState(() => _showCustomColor = !_showCustomColor)),
          if (_showCustomColor) ...[
            const SizedBox(height: 8),
            WatchColorWheelPicker(
              initialHex: _customColorHex,
              onChanged: (hex) => setState(() => _customColorHex = hex),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textPrimary,
                side: BorderSide(color: AppTheme.outline),
              ),
              onPressed: () {
                final hex = _customColorHex.toUpperCase();
                // _toggleColor would remove a color that is already chosen.
                if (!_colorHexes.any((c) => c.toUpperCase() == hex)) {
                  _toggleColor(_customColorHex);
                }
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add this color'),
            ),
          ],
        ],
      ],
    );
  }

  /// A chosen color: swatch, name (or hex for a custom one), a PRIMARY mark
  /// on the first, and a remove button unless it is the only one.
  Widget _colorChip(int i) {
    final hex = _colorHexes[i];
    final name = paletteNameForHex(hex) ?? hex.toUpperCase();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: i == 0 ? AppTheme.textPrimary : AppTheme.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: hexToColor(hex),
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.outline),
            ),
          ),
          const SizedBox(width: 8),
          Text(i == 0 ? '$name · Primary' : name,
              style:
                  TextStyle(color: AppTheme.textPrimary, fontSize: 12)),
          if (_colorHexes.length > 1) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => setState(() => _colorHexes.removeAt(i)),
              child: Icon(Icons.close,
                  size: 14, color: AppTheme.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}