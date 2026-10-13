import 'dart:io';

import 'package:flutter/material.dart';
import '../constants/watch_colors.dart';
import '../services/cloudinary_service.dart';
import '../theme/app_theme.dart';
import '../utils/form_validators.dart';
import 'luxe.dart';
import 'network_photo.dart';
import 'watch_color_picker.dart';
import 'watch_color_wheel_picker.dart';

const _muted = TextStyle(color: AppTheme.textSecondary, fontSize: 12);

/// Every field of a watch listing, shared by the add and edit screens.
///
/// Pass the watch's saved fields as [initialData] to edit it, or nothing to
/// start a new one. The screen owns the save button and calls
/// [WatchFormState.collect] on it, then writes the result.
class WatchForm extends StatefulWidget {
  final Map<String, dynamic> initialData;

  /// Shown above everything else, e.g. the admin's merchant picker.
  final Widget? header;

  const WatchForm({super.key, this.initialData = const {}, this.header});

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

  int get _photoCount => _imageUrls.length + _newImages.length;
  bool get _hasModel => _modelFile != null || _modelUrl.isNotEmpty;

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
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

    return {
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
                const Expanded(
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
            const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
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
            border: Border.all(color: Colors.white24),
          ),
          child: const Column(
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
    const fallback =
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
                    const Text('A .glb or .gltf file enables AR try-on.',
                        style: _muted),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (_modelFile != null && !_uploadingModel)
                IconButton(
                  icon: const Icon(Icons.close,
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
                side: const BorderSide(color: Colors.white24),
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
        border: Border.all(color: i == 0 ? AppTheme.textPrimary : Colors.white24),
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
              border: Border.all(color: Colors.white24),
            ),
          ),
          const SizedBox(width: 8),
          Text(i == 0 ? '$name · Primary' : name,
              style:
                  const TextStyle(color: AppTheme.textPrimary, fontSize: 12)),
          if (_colorHexes.length > 1) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => setState(() => _colorHexes.removeAt(i)),
              child: const Icon(Icons.close,
                  size: 14, color: AppTheme.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}