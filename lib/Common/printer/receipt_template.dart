import 'dart:convert';

import 'package:flutter/services.dart';

class ReceiptTemplateLoader {
  ReceiptTemplateLoader({
    AssetBundle? bundle,
    this.primaryAsset = 'assets/printer_templates/order_receipt_v1.json',
    this.fallbackAsset =
        'assets/printer_templates/order_receipt_fallback_v1.json',
  }) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  final String primaryAsset;
  final String fallbackAsset;

  Future<ReceiptTemplateLoadResult> load() async {
    Object? primaryError;
    try {
      return ReceiptTemplateLoadResult(
        template: await _loadAsset(primaryAsset),
        assetPath: primaryAsset,
        usedFallback: false,
      );
    } catch (err) {
      primaryError = err;
    }

    try {
      return ReceiptTemplateLoadResult(
        template: await _loadAsset(fallbackAsset),
        assetPath: fallbackAsset,
        usedFallback: true,
        primaryError: primaryError,
      );
    } catch (fallbackError) {
      throw ReceiptTemplateException(
        'Unable to load a valid receipt template. '
        'Primary: $primaryError; fallback: $fallbackError',
      );
    }
  }

  Future<ReceiptTemplateConfig> _loadAsset(String assetPath) async {
    final raw = await _bundle.loadString(assetPath);
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw ReceiptTemplateException('$assetPath must contain a JSON object.');
    }
    return ReceiptTemplateConfig.fromJson(
      decoded.map<String, dynamic>(
        (key, value) => MapEntry(key.toString(), value),
      ),
    );
  }
}

class ReceiptTemplateLoadResult {
  const ReceiptTemplateLoadResult({
    required this.template,
    required this.assetPath,
    required this.usedFallback,
    this.primaryError,
  });

  final ReceiptTemplateConfig template;
  final String assetPath;
  final bool usedFallback;
  final Object? primaryError;
}

class ReceiptTemplateConfig {
  const ReceiptTemplateConfig({
    required this.schemaVersion,
    required this.templateId,
    required this.name,
    required this.currencySymbol,
    required this.paperProfiles,
    required this.styles,
    required this.sections,
    required this.testSections,
  });

  final int schemaVersion;
  final String templateId;
  final String name;
  final String currencySymbol;
  final Map<String, ReceiptPaperProfile> paperProfiles;
  final Map<String, ReceiptStyleDefinition> styles;
  final List<ReceiptTemplateElement> sections;
  final List<ReceiptTemplateElement> testSections;

  ReceiptPaperProfile paperProfile(String key) {
    final profile = paperProfiles[key];
    if (profile == null) {
      throw ReceiptTemplateException(
        'Receipt template $templateId does not define paper profile $key.',
      );
    }
    return profile;
  }

  factory ReceiptTemplateConfig.fromJson(Map<String, dynamic> json) {
    final schemaVersion = _readInt(json, 'schemaVersion');
    if (schemaVersion != 1) {
      throw ReceiptTemplateException(
        'Unsupported receipt template schemaVersion $schemaVersion.',
      );
    }

    final templateId = _requiredString(json, 'templateId');
    final name = _requiredString(json, 'name');
    final currencySymbol = _readString(json['currencySymbol'], fallback: r'$');
    if (currencySymbol.length > 8) {
      throw const ReceiptTemplateException(
        'currencySymbol cannot be longer than 8 characters.',
      );
    }

    final paperJson = _requiredMap(json, 'paperProfiles');
    final paperProfiles = <String, ReceiptPaperProfile>{};
    for (final entry in paperJson.entries) {
      paperProfiles[entry.key] = ReceiptPaperProfile.fromJson(
        entry.key,
        _valueAsMap(entry.value, 'paperProfiles.${entry.key}'),
      );
    }
    for (final requiredPaper in const ['mm58', 'mm80']) {
      if (!paperProfiles.containsKey(requiredPaper)) {
        throw ReceiptTemplateException(
          'paperProfiles.$requiredPaper is required.',
        );
      }
    }

    final stylesJson = _requiredMap(json, 'styles');
    final styles = <String, ReceiptStyleDefinition>{};
    for (final entry in stylesJson.entries) {
      styles[entry.key] = ReceiptStyleDefinition.fromJson(
        entry.key,
        _valueAsMap(entry.value, 'styles.${entry.key}'),
      );
    }
    if (!styles.containsKey('normal')) {
      throw const ReceiptTemplateException('styles.normal is required.');
    }

    final sections = _parseElements(
      json['sections'],
      styles: styles,
      path: 'sections',
    );
    final testSections = _parseElements(
      json['testSections'],
      styles: styles,
      path: 'testSections',
    );
    if (sections.isEmpty || testSections.isEmpty) {
      throw const ReceiptTemplateException(
        'sections and testSections must not be empty.',
      );
    }

    return ReceiptTemplateConfig(
      schemaVersion: schemaVersion,
      templateId: templateId,
      name: name,
      currencySymbol: currencySymbol,
      paperProfiles: Map.unmodifiable(paperProfiles),
      styles: Map.unmodifiable(styles),
      sections: List.unmodifiable(sections),
      testSections: List.unmodifiable(testSections),
    );
  }
}

class ReceiptPaperProfile {
  const ReceiptPaperProfile({
    required this.key,
    required this.columns,
    required this.widthDots,
    required this.widthMm,
    required this.horizontalMarginDots,
    required this.verticalMarginDots,
  });

  final String key;
  final int columns;
  final int widthDots;
  final double widthMm;
  final int horizontalMarginDots;
  final int verticalMarginDots;

  factory ReceiptPaperProfile.fromJson(String key, Map<String, dynamic> json) {
    final columns = _readInt(json, 'columns');
    final widthDots = _readInt(json, 'widthDots');
    final widthMm = _readDouble(json, 'widthMm');
    final horizontalMarginDots = _readInt(json, 'horizontalMarginDots');
    final verticalMarginDots = _readInt(
      json,
      'verticalMarginDots',
      fallback: 12,
    );
    if (columns < 16 || columns > 80) {
      throw ReceiptTemplateException(
        'paperProfiles.$key.columns must be between 16 and 80.',
      );
    }
    if (widthDots < 256 || widthDots > 832) {
      throw ReceiptTemplateException(
        'paperProfiles.$key.widthDots must be between 256 and 832.',
      );
    }
    if (widthMm < 40 || widthMm > 100) {
      throw ReceiptTemplateException(
        'paperProfiles.$key.widthMm must be between 40 and 100.',
      );
    }
    if (horizontalMarginDots < 0 || horizontalMarginDots * 2 >= widthDots) {
      throw ReceiptTemplateException(
        'paperProfiles.$key.horizontalMarginDots is invalid.',
      );
    }
    if (verticalMarginDots < 0 || verticalMarginDots > 200) {
      throw ReceiptTemplateException(
        'paperProfiles.$key.verticalMarginDots is invalid.',
      );
    }
    return ReceiptPaperProfile(
      key: key,
      columns: columns,
      widthDots: widthDots,
      widthMm: widthMm,
      horizontalMarginDots: horizontalMarginDots,
      verticalMarginDots: verticalMarginDots,
    );
  }
}

class ReceiptStyleDefinition {
  const ReceiptStyleDefinition({
    required this.name,
    required this.align,
    required this.bold,
    required this.smallFont,
    required this.widthScale,
    required this.heightScale,
    required this.bitmapFontSize,
    required this.bitmapLineHeight,
  });

  final String name;
  final ReceiptAlignment align;
  final bool bold;
  final bool smallFont;
  final int widthScale;
  final int heightScale;
  final double bitmapFontSize;
  final double bitmapLineHeight;

  int get escPosMode {
    var mode = 0;
    if (smallFont) mode |= 0x01;
    if (bold) mode |= 0x08;
    if (heightScale == 2) mode |= 0x10;
    if (widthScale == 2) mode |= 0x20;
    return mode;
  }

  factory ReceiptStyleDefinition.fromJson(
    String name,
    Map<String, dynamic> json,
  ) {
    final align = ReceiptAlignment.fromName(
      _readString(json['align'], fallback: 'left'),
    );
    final bold = _readBool(json['bold']);
    final escPos = _optionalMap(json['escPos']);
    final bitmap = _optionalMap(json['bitmap']);
    final widthScale = _readInt(escPos, 'widthScale', fallback: 1);
    final heightScale = _readInt(escPos, 'heightScale', fallback: 1);
    final smallFont = _readBool(escPos['smallFont']);
    final bitmapFontSize = _readDouble(bitmap, 'fontSize', fallback: 20);
    final bitmapLineHeight = _readDouble(bitmap, 'lineHeight', fallback: 1.12);
    if (widthScale < 1 ||
        widthScale > 2 ||
        heightScale < 1 ||
        heightScale > 2) {
      throw ReceiptTemplateException(
        'styles.$name ESC/POS scale must be 1 or 2.',
      );
    }
    if (bitmapFontSize < 10 || bitmapFontSize > 72) {
      throw ReceiptTemplateException(
        'styles.$name bitmap.fontSize must be between 10 and 72.',
      );
    }
    if (bitmapLineHeight < 0.8 || bitmapLineHeight > 3) {
      throw ReceiptTemplateException(
        'styles.$name bitmap.lineHeight must be between 0.8 and 3.',
      );
    }
    return ReceiptStyleDefinition(
      name: name,
      align: align,
      bold: bold,
      smallFont: smallFont,
      widthScale: widthScale,
      heightScale: heightScale,
      bitmapFontSize: bitmapFontSize,
      bitmapLineHeight: bitmapLineHeight,
    );
  }
}

enum ReceiptAlignment {
  left(0),
  center(1),
  right(2);

  const ReceiptAlignment(this.escPosCode);

  final int escPosCode;

  factory ReceiptAlignment.fromName(String name) {
    return switch (name.trim().toLowerCase()) {
      'left' => ReceiptAlignment.left,
      'center' => ReceiptAlignment.center,
      'right' => ReceiptAlignment.right,
      _ => throw ReceiptTemplateException('Unsupported alignment: $name.'),
    };
  }
}

class ReceiptTemplateElement {
  const ReceiptTemplateElement({
    required this.type,
    required this.style,
    required this.field,
    required this.template,
    required this.fallback,
    required this.prefix,
    required this.textWrapMode,
    required this.imageAsset,
    required this.imageWidthDots,
    required this.imagePosition,
    required this.imageSpaceBeforeDots,
    required this.imageSpaceAfterDots,
    required this.separatorPosition,
    required this.separatorWidthPercent,
    required this.separatorThicknessDots,
    required this.separatorSpaceBeforeDots,
    required this.separatorSpaceAfterDots,
    required this.label,
    required this.amountField,
    required this.source,
    required this.itemName,
    required this.children,
    required this.condition,
    required this.lines,
    required this.mode,
  });

  final ReceiptElementType type;
  final String style;
  final String field;
  final String template;
  final String fallback;
  final String prefix;
  final ReceiptTextWrapMode textWrapMode;
  final String imageAsset;
  final int imageWidthDots;
  final ReceiptAlignment imagePosition;
  final int imageSpaceBeforeDots;
  final int imageSpaceAfterDots;
  final ReceiptAlignment separatorPosition;
  final double separatorWidthPercent;
  final int separatorThicknessDots;
  final int separatorSpaceBeforeDots;
  final int separatorSpaceAfterDots;
  final String label;
  final String amountField;
  final String source;
  final String itemName;
  final List<ReceiptTemplateElement> children;
  final ReceiptCondition? condition;
  final int lines;
  final String mode;
}

enum ReceiptElementType { image, text, separator, moneyRow, repeat, feed, cut }

enum ReceiptTextWrapMode {
  columns,
  output;

  factory ReceiptTextWrapMode.fromName(String name) {
    return switch (name.trim().toLowerCase()) {
      'columns' => ReceiptTextWrapMode.columns,
      'output' => ReceiptTextWrapMode.output,
      _ => throw ReceiptTemplateException('Unsupported text wrap mode: $name.'),
    };
  }
}

class ReceiptCondition {
  const ReceiptCondition({
    required this.field,
    required this.operatorName,
    this.value,
  });

  final String field;
  final String operatorName;
  final dynamic value;

  factory ReceiptCondition.fromJson(Map<String, dynamic> json, String path) {
    final field = _requiredString(json, 'field');
    final operatorName = _requiredString(json, 'operator');
    const supported = {
      'notEmpty',
      'empty',
      'greaterThan',
      'equals',
      'isTrue',
      'isFalse',
    };
    if (!supported.contains(operatorName)) {
      throw ReceiptTemplateException(
        '$path.operator must be one of ${supported.join(', ')}.',
      );
    }
    if (operatorName == 'greaterThan' && json['value'] is! num) {
      throw ReceiptTemplateException('$path.value must be numeric.');
    }
    return ReceiptCondition(
      field: field,
      operatorName: operatorName,
      value: json['value'],
    );
  }
}

class ReceiptTemplateException implements Exception {
  const ReceiptTemplateException(this.message);

  final String message;

  @override
  String toString() => message;
}

List<ReceiptTemplateElement> _parseElements(
  dynamic raw, {
  required Map<String, ReceiptStyleDefinition> styles,
  required String path,
  int depth = 0,
}) {
  if (raw is! List) {
    throw ReceiptTemplateException('$path must be a JSON array.');
  }
  if (depth > 5) {
    throw ReceiptTemplateException('$path is nested too deeply.');
  }
  if (raw.length > 200) {
    throw ReceiptTemplateException('$path contains too many elements.');
  }

  final result = <ReceiptTemplateElement>[];
  for (var index = 0; index < raw.length; index++) {
    final itemPath = '$path[$index]';
    final json = _valueAsMap(raw[index], itemPath);
    final typeName = _requiredString(json, 'type');
    final type = switch (typeName) {
      'image' => ReceiptElementType.image,
      'text' => ReceiptElementType.text,
      'separator' => ReceiptElementType.separator,
      'moneyRow' => ReceiptElementType.moneyRow,
      'repeat' => ReceiptElementType.repeat,
      'feed' => ReceiptElementType.feed,
      'cut' => ReceiptElementType.cut,
      _ => throw ReceiptTemplateException(
        '$itemPath.type "$typeName" is not supported.',
      ),
    };
    final style = _readString(json['style'], fallback: 'normal');
    if (!styles.containsKey(style)) {
      throw ReceiptTemplateException('$itemPath uses unknown style "$style".');
    }

    final conditionJson = json['when'];
    final condition = conditionJson == null
        ? null
        : ReceiptCondition.fromJson(
            _valueAsMap(conditionJson, '$itemPath.when'),
            '$itemPath.when',
          );
    var children = const <ReceiptTemplateElement>[];
    if (type == ReceiptElementType.repeat) {
      _requiredString(json, 'source');
      _requiredString(json, 'itemName');
      children = _parseElements(
        json['children'],
        styles: styles,
        path: '$itemPath.children',
        depth: depth + 1,
      );
      if (children.isEmpty) {
        throw ReceiptTemplateException('$itemPath.children must not be empty.');
      }
    }
    if (type == ReceiptElementType.text &&
        _readString(json['field']).isEmpty &&
        _readString(json['template']).isEmpty) {
      throw ReceiptTemplateException(
        '$itemPath requires either field or template.',
      );
    }
    final textWrapMode = type == ReceiptElementType.text
        ? ReceiptTextWrapMode.fromName(
            _readString(json['wrap'], fallback: 'columns'),
          )
        : ReceiptTextWrapMode.columns;
    if (type == ReceiptElementType.moneyRow) {
      _requiredString(json, 'label');
      _requiredString(json, 'amountField');
    }

    var imageAsset = '';
    var imageWidthDots = 160;
    var imagePosition = ReceiptAlignment.center;
    var imageSpaceBeforeDots = 0;
    var imageSpaceAfterDots = 6;
    if (type == ReceiptElementType.image) {
      imageAsset = _requiredString(json, 'asset');
      imageWidthDots = _readInt(json, 'widthDots', fallback: 160);
      imagePosition = ReceiptAlignment.fromName(
        _readString(json['position'], fallback: 'center'),
      );
      imageSpaceBeforeDots = _readInt(json, 'spaceBeforeDots');
      imageSpaceAfterDots = _readInt(json, 'spaceAfterDots', fallback: 6);
      if (!imageAsset.startsWith('assets/') ||
          imageAsset.contains('..') ||
          !imageAsset.toLowerCase().endsWith('.png')) {
        throw ReceiptTemplateException(
          '$itemPath.asset must be a bundled PNG under assets/.',
        );
      }
      if (imageWidthDots < 16 || imageWidthDots > 832) {
        throw ReceiptTemplateException(
          '$itemPath.widthDots must be between 16 and 832.',
        );
      }
      if (imageSpaceBeforeDots < 0 ||
          imageSpaceBeforeDots > 200 ||
          imageSpaceAfterDots < 0 ||
          imageSpaceAfterDots > 200) {
        throw ReceiptTemplateException(
          '$itemPath image spacing must be between 0 and 200 dots.',
        );
      }
    }

    var separatorPosition = ReceiptAlignment.center;
    var separatorWidthPercent = 100.0;
    var separatorThicknessDots = 2;
    var separatorSpaceBeforeDots = 6;
    var separatorSpaceAfterDots = 6;
    if (type == ReceiptElementType.separator) {
      separatorPosition = ReceiptAlignment.fromName(
        _readString(json['position'], fallback: 'center'),
      );
      separatorWidthPercent = _readDouble(json, 'widthPercent', fallback: 100);
      separatorThicknessDots = _readInt(json, 'thicknessDots', fallback: 2);
      separatorSpaceBeforeDots = _readInt(json, 'spaceBeforeDots', fallback: 6);
      separatorSpaceAfterDots = _readInt(json, 'spaceAfterDots', fallback: 6);
      if (separatorWidthPercent < 1 || separatorWidthPercent > 100) {
        throw ReceiptTemplateException(
          '$itemPath.widthPercent must be between 1 and 100.',
        );
      }
      if (separatorThicknessDots < 1 || separatorThicknessDots > 32) {
        throw ReceiptTemplateException(
          '$itemPath.thicknessDots must be between 1 and 32.',
        );
      }
      if (separatorSpaceBeforeDots < 0 ||
          separatorSpaceBeforeDots > 200 ||
          separatorSpaceAfterDots < 0 ||
          separatorSpaceAfterDots > 200) {
        throw ReceiptTemplateException(
          '$itemPath separator spacing must be between 0 and 200 dots.',
        );
      }
    }
    final lines = _readInt(json, 'lines', fallback: 0);
    if (type == ReceiptElementType.feed && (lines < 0 || lines > 10)) {
      throw ReceiptTemplateException(
        '$itemPath.lines must be between 0 and 10.',
      );
    }
    final mode = _readString(json['mode'], fallback: 'none');
    if (type == ReceiptElementType.cut &&
        !const {'none', 'partial'}.contains(mode)) {
      throw ReceiptTemplateException(
        '$itemPath.mode currently supports only none or partial.',
      );
    }

    result.add(
      ReceiptTemplateElement(
        type: type,
        style: style,
        field: _readString(json['field']),
        template: _readString(json['template']),
        fallback: _readString(json['fallback']),
        prefix: _readLiteral(json['prefix']),
        textWrapMode: textWrapMode,
        imageAsset: imageAsset,
        imageWidthDots: imageWidthDots,
        imagePosition: imagePosition,
        imageSpaceBeforeDots: imageSpaceBeforeDots,
        imageSpaceAfterDots: imageSpaceAfterDots,
        separatorPosition: separatorPosition,
        separatorWidthPercent: separatorWidthPercent,
        separatorThicknessDots: separatorThicknessDots,
        separatorSpaceBeforeDots: separatorSpaceBeforeDots,
        separatorSpaceAfterDots: separatorSpaceAfterDots,
        label: _readString(json['label']),
        amountField: _readString(json['amountField']),
        source: _readString(json['source']),
        itemName: _readString(json['itemName']),
        children: List.unmodifiable(children),
        condition: condition,
        lines: lines,
        mode: mode,
      ),
    );
  }
  return result;
}

Map<String, dynamic> _requiredMap(Map<String, dynamic> json, String key) {
  return _valueAsMap(json[key], key);
}

Map<String, dynamic> _optionalMap(dynamic value) {
  if (value == null) return const {};
  return _valueAsMap(value, 'value');
}

Map<String, dynamic> _valueAsMap(dynamic value, String path) {
  if (value is! Map) {
    throw ReceiptTemplateException('$path must be a JSON object.');
  }
  return value.map<String, dynamic>(
    (key, item) => MapEntry(key.toString(), item),
  );
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = _readString(json[key]);
  if (value.isEmpty) {
    throw ReceiptTemplateException('$key is required.');
  }
  return value;
}

String _readString(dynamic value, {String fallback = ''}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

String _readLiteral(dynamic value) => value?.toString() ?? '';

int _readInt(Map<String, dynamic> json, String key, {int fallback = 0}) {
  final value = json[key];
  if (value == null) return fallback;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? fallback;
}

double _readDouble(
  Map<String, dynamic> json,
  String key, {
  double fallback = 0,
}) {
  final value = json[key];
  if (value == null) return fallback;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? fallback;
}

bool _readBool(dynamic value) {
  if (value is bool) return value;
  final normalized = value?.toString().trim().toLowerCase() ?? '';
  return normalized == 'true' || normalized == '1' || normalized == 'yes';
}
