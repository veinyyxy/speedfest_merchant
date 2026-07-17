import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

import '../../Models/merchant_buyer_config.dart';
import '../../Models/merchant_order.dart';
import '../../Models/merchant_printer.dart';
import 'receipt_template.dart';

class MerchantReceiptRenderer {
  MerchantReceiptRenderer({
    ReceiptTemplateConfig? template,
    ReceiptTemplateLoader? loader,
    AssetBundle? assetBundle,
  }) : _template = template,
       _loader = loader ?? ReceiptTemplateLoader(bundle: assetBundle),
       _assetBundle = assetBundle ?? rootBundle;

  final ReceiptTemplateLoader _loader;
  final AssetBundle _assetBundle;
  ReceiptTemplateConfig? _template;
  Future<void>? _initializing;
  String _templateAssetPath = '';
  bool _usedFallbackTemplate = false;

  String get templateName => _template?.name ?? 'Receipt template';
  String get templateAssetPath => _templateAssetPath;
  bool get usedFallbackTemplate => _usedFallbackTemplate;

  Future<void> initialize() {
    if (_template != null) return Future.value();
    return _initializing ??= _loadTemplate();
  }

  Future<void> _loadTemplate() async {
    final loaded = await _loader.load();
    _template = loaded.template;
    _templateAssetPath = loaded.assetPath;
    _usedFallbackTemplate = loaded.usedFallback;
  }

  Future<MerchantReceiptRenderResult> renderOrder({
    required MerchantOrder order,
    required MerchantPrinterPaperSize paperSize,
    MerchantStoreProfileConfig? storeProfile,
    bool includeBitmap = false,
  }) async {
    await initialize();
    final template = _requireTemplate();
    final document = _ReceiptLayoutEngine(template).build(
      paperSize: paperSize,
      context: _orderContext(order, storeProfile),
      elements: template.sections,
    );
    return _renderDocument(document, includeBitmap: includeBitmap);
  }

  Future<MerchantReceiptRenderResult> renderTest({
    required MerchantPrinter printer,
    bool includeBitmap = false,
  }) async {
    await initialize();
    final template = _requireTemplate();
    final document = _ReceiptLayoutEngine(template).build(
      paperSize: printer.paperSize,
      context: {
        'app': {'name': 'Powered by Speedfeast'},
        'printer': {
          'name': printer.displayName,
          'connectionType': printer.connectionLabel,
          'target': printer.targetLabel,
          'paperSize': printer.paperSizeLabel,
          'protocol': printer.protocolLabel,
        },
        'test': {'message': 'If you can read this, printing is ready.'},
      },
      elements: template.testSections,
    );
    return _renderDocument(document, includeBitmap: includeBitmap);
  }

  ReceiptTemplateConfig _requireTemplate() {
    final template = _template;
    if (template == null) {
      throw const ReceiptTemplateException(
        'Receipt template has not been initialized.',
      );
    }
    return template;
  }

  Future<MerchantReceiptRenderResult> _renderDocument(
    _ReceiptDocument document, {
    required bool includeBitmap,
  }) async {
    final prepared = await _loadDocumentImages(document);
    try {
      return MerchantReceiptRenderResult(
        escPosBytes: _documentToEscPosBytes(prepared),
        text: _documentToPlainText(prepared),
        html: _documentToHtml(prepared),
        bitmapPng: includeBitmap ? await _documentToPng(prepared) : null,
        paperWidthDots: prepared.paper.widthDots,
        feedLines: prepared.feedLines,
        cutMode: prepared.cutMode,
        templateId: prepared.templateId,
      );
    } finally {
      prepared.disposeImages();
    }
  }

  Future<_ReceiptDocument> _loadDocumentImages(
    _ReceiptDocument document,
  ) async {
    final lines = <_ReceiptDocumentLine>[];
    for (final line in document.lines) {
      final image = line.image;
      if (image == null) {
        lines.add(line);
        continue;
      }
      lines.add(
        line.withImage(await _loadReceiptImage(image, paper: document.paper)),
      );
    }
    return document.withLines(List.unmodifiable(lines));
  }

  Future<_ReceiptImageLine> _loadReceiptImage(
    _ReceiptImageLine image, {
    required ReceiptPaperProfile paper,
  }) async {
    final contentWidth = paper.widthDots - paper.horizontalMarginDots * 2;
    final targetWidth = math.min(image.widthDots, contentWidth);
    final data = await _assetBundle.load(image.asset);
    final sourceBytes = Uint8List.fromList(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    final codec = await ui.instantiateImageCodec(
      sourceBytes,
      targetWidth: targetWidth,
    );
    try {
      final frame = await codec.getNextFrame();
      final decodedImage = frame.image;
      final rgbaData = await decodedImage.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (rgbaData == null) {
        decodedImage.dispose();
        throw ReceiptTemplateException(
          'Unable to decode receipt image ${image.asset}.',
        );
      }
      final rgba = rgbaData.buffer.asUint8List(
        rgbaData.offsetInBytes,
        rgbaData.lengthInBytes,
      );
      return image.loaded(
        decodedImage: decodedImage,
        sourceBytes: sourceBytes,
        escPosRaster: _imageToMonochromeRaster(
          paper: paper,
          image: image,
          imageWidth: decodedImage.width,
          imageHeight: decodedImage.height,
          rgba: rgba,
        ),
      );
    } finally {
      codec.dispose();
    }
  }
}

class MerchantReceiptRenderResult {
  const MerchantReceiptRenderResult({
    required this.escPosBytes,
    required this.text,
    required this.html,
    required this.bitmapPng,
    required this.paperWidthDots,
    required this.feedLines,
    required this.cutMode,
    required this.templateId,
  });

  final List<int> escPosBytes;
  final String text;
  final String html;
  final Uint8List? bitmapPng;
  final int paperWidthDots;
  final int feedLines;
  final String cutMode;
  final String templateId;
}

class _ReceiptDocument {
  const _ReceiptDocument({
    required this.templateId,
    required this.paper,
    required this.lines,
    required this.feedLines,
    required this.cutMode,
  });

  final String templateId;
  final ReceiptPaperProfile paper;
  final List<_ReceiptDocumentLine> lines;
  final int feedLines;
  final String cutMode;

  _ReceiptDocument withLines(List<_ReceiptDocumentLine> value) {
    return _ReceiptDocument(
      templateId: templateId,
      paper: paper,
      lines: value,
      feedLines: feedLines,
      cutMode: cutMode,
    );
  }

  void disposeImages() {
    for (final line in lines) {
      line.image?.decodedImage?.dispose();
    }
  }
}

class _ReceiptDocumentLine {
  const _ReceiptDocumentLine({
    required this.text,
    required this.style,
    this.moneyLabel,
    this.moneySign,
    this.moneyNumber,
    this.image,
    this.separator,
  });

  final String text;
  final ReceiptStyleDefinition style;
  final String? moneyLabel;
  final String? moneySign;
  final String? moneyNumber;
  final _ReceiptImageLine? image;
  final _ReceiptSeparatorLine? separator;

  _ReceiptDocumentLine withImage(_ReceiptImageLine value) {
    return _ReceiptDocumentLine(
      text: text,
      style: style,
      moneyLabel: moneyLabel,
      moneySign: moneySign,
      moneyNumber: moneyNumber,
      image: value,
      separator: separator,
    );
  }
}

class _ReceiptImageLine {
  const _ReceiptImageLine({
    required this.asset,
    required this.widthDots,
    required this.position,
    required this.spaceBeforeDots,
    required this.spaceAfterDots,
    this.decodedImage,
    this.sourceBytes,
    this.escPosRaster,
  });

  final String asset;
  final int widthDots;
  final ReceiptAlignment position;
  final int spaceBeforeDots;
  final int spaceAfterDots;
  final ui.Image? decodedImage;
  final Uint8List? sourceBytes;
  final Uint8List? escPosRaster;

  int get renderedWidth => decodedImage?.width ?? 0;
  int get renderedHeight => decodedImage?.height ?? 0;
  int get totalHeight => spaceBeforeDots + renderedHeight + spaceAfterDots;

  _ReceiptImageLine loaded({
    required ui.Image decodedImage,
    required Uint8List sourceBytes,
    required Uint8List escPosRaster,
  }) {
    return _ReceiptImageLine(
      asset: asset,
      widthDots: widthDots,
      position: position,
      spaceBeforeDots: spaceBeforeDots,
      spaceAfterDots: spaceAfterDots,
      decodedImage: decodedImage,
      sourceBytes: sourceBytes,
      escPosRaster: escPosRaster,
    );
  }
}

class _ReceiptSeparatorLine {
  const _ReceiptSeparatorLine({
    required this.position,
    required this.widthPercent,
    required this.thicknessDots,
    required this.spaceBeforeDots,
    required this.spaceAfterDots,
  });

  final ReceiptAlignment position;
  final double widthPercent;
  final int thicknessDots;
  final int spaceBeforeDots;
  final int spaceAfterDots;
}

class _ReceiptLayoutEngine {
  const _ReceiptLayoutEngine(this.template);

  final ReceiptTemplateConfig template;

  _ReceiptDocument build({
    required MerchantPrinterPaperSize paperSize,
    required Map<String, dynamic> context,
    required List<ReceiptTemplateElement> elements,
  }) {
    final paperKey = switch (paperSize) {
      MerchantPrinterPaperSize.mm58 => 'mm58',
      MerchantPrinterPaperSize.mm80 => 'mm80',
    };
    final paper = template.paperProfile(paperKey);
    final state = _ReceiptBuildState();
    _appendElements(
      elements,
      scope: _TemplateScope(root: context),
      paper: paper,
      state: state,
      depth: 0,
    );
    if (state.lines.length > 1000) {
      throw const ReceiptTemplateException(
        'Receipt template generated too many lines.',
      );
    }
    return _ReceiptDocument(
      templateId: template.templateId,
      paper: paper,
      lines: List.unmodifiable(state.lines),
      feedLines: state.feedLines.clamp(0, 20),
      cutMode: state.cutMode,
    );
  }

  void _appendElements(
    List<ReceiptTemplateElement> elements, {
    required _TemplateScope scope,
    required ReceiptPaperProfile paper,
    required _ReceiptBuildState state,
    required int depth,
  }) {
    if (depth > 6) {
      throw const ReceiptTemplateException(
        'Receipt template repeat nesting is too deep.',
      );
    }
    for (final element in elements) {
      if (!_conditionMatches(element.condition, scope)) continue;
      final style = template.styles[element.style]!;
      switch (element.type) {
        case ReceiptElementType.image:
          state.lines.add(
            _ReceiptDocumentLine(
              text: '',
              style: style,
              image: _ReceiptImageLine(
                asset: element.imageAsset,
                widthDots: element.imageWidthDots,
                position: element.imagePosition,
                spaceBeforeDots: element.imageSpaceBeforeDots,
                spaceAfterDots: element.imageSpaceAfterDots,
              ),
            ),
          );
        case ReceiptElementType.text:
          var value = element.template.isNotEmpty
              ? _expandTemplate(element.template, scope)
              : _valueText(scope.read(element.field));
          if (value.trim().isEmpty) value = element.fallback;
          _appendText(
            state.lines,
            value,
            prefix: element.prefix,
            style: style,
            columns: paper.columns,
            wrapMode: element.textWrapMode,
          );
        case ReceiptElementType.separator:
          state.lines.add(
            _ReceiptDocumentLine(
              text: '',
              style: style,
              separator: _ReceiptSeparatorLine(
                position: element.separatorPosition,
                widthPercent: element.separatorWidthPercent,
                thicknessDots: element.separatorThicknessDots,
                spaceBeforeDots: element.separatorSpaceBeforeDots,
                spaceAfterDots: element.separatorSpaceAfterDots,
              ),
            ),
          );
        case ReceiptElementType.moneyRow:
          final label = _expandTemplate(element.label, scope);
          final amount = _numericValue(scope.read(element.amountField));
          _appendMoneyRow(
            state.lines,
            label: label,
            prefix: element.prefix,
            amount: amount,
            currencySymbol: template.currencySymbol,
            style: style,
            columns: paper.columns,
          );
        case ReceiptElementType.repeat:
          final source = scope.read(element.source);
          if (source is! List) continue;
          for (final item in source.take(250)) {
            final childScope = scope.withLocal(element.itemName, item);
            _appendElements(
              element.children,
              scope: childScope,
              paper: paper,
              state: state,
              depth: depth + 1,
            );
          }
        case ReceiptElementType.feed:
          state.feedLines += element.lines;
        case ReceiptElementType.cut:
          state.cutMode = element.mode;
      }
      if (state.lines.length > 1000) {
        throw const ReceiptTemplateException(
          'Receipt template generated too many lines.',
        );
      }
    }
  }
}

class _ReceiptBuildState {
  final List<_ReceiptDocumentLine> lines = [];
  int feedLines = 0;
  String cutMode = 'none';
}

class _TemplateScope {
  const _TemplateScope({required this.root, this.locals = const {}});

  final Map<String, dynamic> root;
  final Map<String, dynamic> locals;

  _TemplateScope withLocal(String name, dynamic value) {
    return _TemplateScope(root: root, locals: {...locals, name: value});
  }

  dynamic read(String path) {
    final segments = path.split('.').where((item) => item.isNotEmpty).toList();
    if (segments.isEmpty) return null;
    dynamic current = locals.containsKey(segments.first)
        ? locals[segments.first]
        : root[segments.first];
    for (final segment in segments.skip(1)) {
      if (current is Map) {
        current = current[segment];
      } else {
        return null;
      }
    }
    return current;
  }
}

bool _conditionMatches(ReceiptCondition? condition, _TemplateScope scope) {
  if (condition == null) return true;
  final current = scope.read(condition.field);
  return switch (condition.operatorName) {
    'notEmpty' => !_isEmptyValue(current),
    'empty' => _isEmptyValue(current),
    'greaterThan' => _numericValue(current) > _numericValue(condition.value),
    'equals' => _valuesEqual(current, condition.value),
    'isTrue' => current == true,
    'isFalse' => current == false,
    _ => false,
  };
}

bool _isEmptyValue(dynamic value) {
  if (value == null) return true;
  if (value is String) return value.trim().isEmpty;
  if (value is Iterable) return value.isEmpty;
  if (value is Map) return value.isEmpty;
  return false;
}

bool _valuesEqual(dynamic left, dynamic right) {
  if (left is num && right is num) return left.toDouble() == right.toDouble();
  return left?.toString() == right?.toString();
}

final _templateFieldPattern = RegExp(r'\{\{\s*([A-Za-z0-9_.]+)\s*\}\}');

String _expandTemplate(String template, _TemplateScope scope) {
  return template.replaceAllMapped(
    _templateFieldPattern,
    (match) => _valueText(scope.read(match.group(1) ?? '')),
  );
}

void _appendText(
  List<_ReceiptDocumentLine> lines,
  String value, {
  required String prefix,
  required ReceiptStyleDefinition style,
  required int columns,
  required ReceiptTextWrapMode wrapMode,
}) {
  if (value.trim().isEmpty) return;
  final paragraphs = value
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');
  if (wrapMode == ReceiptTextWrapMode.output) {
    for (final paragraph in paragraphs) {
      final normalized = paragraph.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (normalized.isEmpty) continue;
      lines.add(_ReceiptDocumentLine(text: '$prefix$normalized', style: style));
    }
    return;
  }

  final width = _effectiveColumns(columns, style);
  final continuationPrefix = List.filled(prefix.length, ' ').join();
  for (final paragraph in paragraphs) {
    final wrapped = _wrapWords(paragraph, math.max(4, width - prefix.length));
    for (var index = 0; index < wrapped.length; index++) {
      lines.add(
        _ReceiptDocumentLine(
          text: '${index == 0 ? prefix : continuationPrefix}${wrapped[index]}',
          style: style,
        ),
      );
    }
  }
}

void _appendMoneyRow(
  List<_ReceiptDocumentLine> lines, {
  required String label,
  required String prefix,
  required double amount,
  required String currencySymbol,
  required ReceiptStyleDefinition style,
  required int columns,
}) {
  final width = _effectiveColumns(columns, style);
  final cleanLabel = label.trim();
  final sign = amount < 0 ? '-' : '';
  final number = amount.abs().toStringAsFixed(2);
  final formattedAmount = '$sign$currencySymbol$number';
  final amountStart = math.max(0, width - formattedAmount.length);
  final labelWidth = math.max(4, amountStart - prefix.length - 1);
  final wrappedLabel = _wrapWords(cleanLabel, labelWidth);
  if (wrappedLabel.isEmpty) {
    lines.add(
      _ReceiptDocumentLine(text: formattedAmount.padLeft(width), style: style),
    );
    return;
  }

  final firstLabel = '$prefix${wrappedLabel.first}';
  final gap = math.max(1, amountStart - firstLabel.length);
  lines.add(
    _ReceiptDocumentLine(
      text: '$firstLabel${List.filled(gap, ' ').join()}$formattedAmount',
      style: style,
      moneyLabel: firstLabel,
      moneySign: sign,
      moneyNumber: '$currencySymbol$number',
    ),
  );
  final continuationPrefix = List.filled(prefix.length, ' ').join();
  for (final extra in wrappedLabel.skip(1)) {
    lines.add(
      _ReceiptDocumentLine(text: '$continuationPrefix$extra', style: style),
    );
  }
}

int _effectiveColumns(int columns, ReceiptStyleDefinition style) {
  return math.max(4, columns ~/ style.widthScale);
}

List<String> _wrapWords(String value, int width) {
  final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.isEmpty) return const [];
  if (width <= 4) return [normalized];

  final words = normalized.split(' ');
  final lines = <String>[];
  var current = '';
  for (final word in words) {
    if (word.length > width) {
      if (current.isNotEmpty) {
        lines.add(current);
        current = '';
      }
      var remaining = word;
      while (remaining.length > width) {
        lines.add(remaining.substring(0, width));
        remaining = remaining.substring(width);
      }
      current = remaining;
      continue;
    }

    final candidate = current.isEmpty ? word : '$current $word';
    if (candidate.length <= width) {
      current = candidate;
    } else {
      if (current.isNotEmpty) lines.add(current);
      current = word;
    }
  }
  if (current.isNotEmpty) lines.add(current);
  return lines;
}

List<int> _documentToEscPosBytes(_ReceiptDocument document) {
  final bytes = <int>[0x1B, 0x40, 0x1B, 0x74, 16];
  for (final line in document.lines) {
    final image = line.image;
    if (image != null) {
      bytes.addAll(_imageToEscPosBytes(document.paper, image));
      continue;
    }
    final separator = line.separator;
    if (separator != null) {
      bytes.addAll(_separatorToEscPosBytes(document.paper, separator));
      continue;
    }
    bytes.addAll([0x1B, 0x61, line.style.align.escPosCode]);
    bytes.addAll([0x1B, 0x21, line.style.escPosMode]);
    bytes.addAll(_encodeLatin1Lossy(line.text));
    bytes.add(0x0A);
  }
  bytes.addAll([0x1B, 0x61, 0, 0x1B, 0x21, 0]);
  bytes.addAll(List.filled(document.feedLines, 0x0A));
  if (document.cutMode == 'partial') {
    bytes.addAll([0x1D, 0x56, 0x01]);
  }
  return bytes;
}

String _documentToPlainText(_ReceiptDocument document) {
  final lines = document.lines.map((line) {
    if (line.image != null) return '';
    if (line.separator != null) return '';
    final width = _effectiveColumns(document.paper.columns, line.style);
    return switch (line.style.align) {
      ReceiptAlignment.left => line.text,
      ReceiptAlignment.center => line.text.padLeft(
        line.text.length + math.max(0, (width - line.text.length) ~/ 2),
      ),
      ReceiptAlignment.right => line.text.padLeft(width),
    };
  }).toList();
  lines.addAll(List.filled(document.feedLines, ''));
  return lines.join('\n');
}

String _documentToHtml(_ReceiptDocument document) {
  final width = document.paper.widthMm;
  return '''
<div style="font-family: 'Liberation Mono', 'Noto Sans Mono', monospace; color: #000; width: ${width}mm;">
${document.lines.map(_documentLineToHtml).join('\n')}
</div>
''';
}

String _documentLineToHtml(_ReceiptDocumentLine line) {
  final image = line.image;
  if (image != null) {
    final sourceBytes = image.sourceBytes;
    if (sourceBytes == null) return '';
    final justifyContent = switch (image.position) {
      ReceiptAlignment.left => 'flex-start',
      ReceiptAlignment.center => 'center',
      ReceiptAlignment.right => 'flex-end',
    };
    final encoded = base64Encode(sourceBytes);
    return '<div style="display:flex; justify-content:$justifyContent; '
        'padding-top:${image.spaceBeforeDots}px; '
        'padding-bottom:${image.spaceAfterDots}px;">'
        '<img alt="Receipt logo" src="data:image/png;base64,$encoded" '
        'width="${image.renderedWidth}" height="${image.renderedHeight}" />'
        '</div>';
  }
  final separator = line.separator;
  if (separator != null) {
    final justifyContent = switch (separator.position) {
      ReceiptAlignment.left => 'flex-start',
      ReceiptAlignment.center => 'center',
      ReceiptAlignment.right => 'flex-end',
    };
    return '<div style="display:flex; justify-content:$justifyContent; '
        'padding-top:${separator.spaceBeforeDots}px; '
        'padding-bottom:${separator.spaceAfterDots}px;">'
        '<span style="display:block; width:${separator.widthPercent}%; '
        'height:${separator.thicknessDots}px; background:#000;"></span>'
        '</div>';
  }
  final escaped = const HtmlEscape().convert(line.text);
  final align = switch (line.style.align) {
    ReceiptAlignment.left => 'left',
    ReceiptAlignment.center => 'center',
    ReceiptAlignment.right => 'right',
  };
  final weight = line.style.bold ? '700' : '400';
  final fontSize = line.style.bitmapFontSize * 0.75;
  if (line.moneyLabel != null && line.moneyNumber != null) {
    final label = const HtmlEscape().convert(line.moneyLabel!);
    final sign = const HtmlEscape().convert(line.moneySign ?? '');
    final number = const HtmlEscape().convert(line.moneyNumber!);
    return '<div style="display:flex; gap:8px; font-size:${fontSize}pt; '
        'font-weight:$weight; line-height:${line.style.bitmapLineHeight};">'
        '<span style="flex:1 1 auto; overflow-wrap:anywhere; '
        'white-space:pre-wrap;">$label</span>'
        '<span style="flex:0 0 auto; white-space:pre;">$sign$number</span>'
        '</div>';
  }
  return '<div style="white-space:pre-wrap; text-align:$align; '
      'font-size:${fontSize}pt; font-weight:$weight; '
      'line-height:${line.style.bitmapLineHeight};">$escaped</div>';
}

Future<Uint8List> _documentToPng(_ReceiptDocument document) async {
  final width = document.paper.widthDots;
  final horizontalMargin = document.paper.horizontalMarginDots.toDouble();
  final verticalMargin = document.paper.verticalMarginDots.toDouble();
  final contentWidth = width - horizontalMargin * 2;
  final paintLines = <_BitmapPaintLine>[];
  var contentHeight = 0.0;

  for (final line in document.lines) {
    final receiptImage = line.image;
    if (receiptImage != null) {
      final height = receiptImage.totalHeight.toDouble();
      paintLines.add(
        _BitmapPaintLine(height: height, receiptImage: receiptImage),
      );
      contentHeight += height;
      continue;
    }
    final separator = line.separator;
    if (separator != null) {
      final height =
          (separator.spaceBeforeDots +
                  separator.thicknessDots +
                  separator.spaceAfterDots)
              .toDouble();
      paintLines.add(_BitmapPaintLine(height: height, separator: separator));
      contentHeight += height;
      continue;
    }
    final textStyle = TextStyle(
      color: const ui.Color(0xFF000000),
      fontFamily: 'monospace',
      fontSize: line.style.bitmapFontSize,
      height: line.style.bitmapLineHeight,
      fontWeight: line.style.bold ? FontWeight.w700 : FontWeight.w400,
    );
    final moneyLabel = line.moneyLabel;
    final moneyNumber = line.moneyNumber;
    if (moneyLabel != null && moneyNumber != null) {
      final trailingPainter = TextPainter(
        text: TextSpan(
          text: '${line.moneySign ?? ''}$moneyNumber',
          style: textStyle,
        ),
        textAlign: ui.TextAlign.right,
        textDirection: ui.TextDirection.ltr,
      )..layout();
      final gap = math.max(4.0, line.style.bitmapFontSize * 0.35);
      final labelWidth = math.max(
        1.0,
        contentWidth - trailingPainter.width - gap,
      );
      final painter = TextPainter(
        text: TextSpan(text: moneyLabel, style: textStyle),
        textAlign: ui.TextAlign.left,
        textDirection: ui.TextDirection.ltr,
      )..layout(maxWidth: labelWidth);
      final height = math.max(
        math.max(painter.height, trailingPainter.height),
        line.style.bitmapFontSize * line.style.bitmapLineHeight,
      );
      paintLines.add(
        _BitmapPaintLine(
          painter: painter,
          trailingPainter: trailingPainter,
          height: height,
        ),
      );
      contentHeight += height;
      continue;
    }

    final textAlign = switch (line.style.align) {
      ReceiptAlignment.left => ui.TextAlign.left,
      ReceiptAlignment.center => ui.TextAlign.center,
      ReceiptAlignment.right => ui.TextAlign.right,
    };
    final painter = TextPainter(
      text: TextSpan(text: line.text, style: textStyle),
      textAlign: textAlign,
      textDirection: ui.TextDirection.ltr,
    )..layout(minWidth: contentWidth, maxWidth: contentWidth);
    final height = math.max(
      painter.height,
      line.style.bitmapFontSize * line.style.bitmapLineHeight,
    );
    paintLines.add(_BitmapPaintLine(painter: painter, height: height));
    contentHeight += height;
  }

  final imageHeight = math.max(1, (verticalMargin * 2 + contentHeight).ceil());
  if (imageHeight > 16000) {
    throw const ReceiptTemplateException(
      'Receipt image is too tall. Reduce the template content.',
    );
  }

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), imageHeight.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  var y = verticalMargin;
  for (final line in paintLines) {
    final receiptImage = line.receiptImage;
    if (receiptImage != null) {
      final decodedImage = receiptImage.decodedImage!;
      final left = _imageLeftDots(
        document.paper,
        imageWidth: decodedImage.width,
        position: receiptImage.position,
      );
      canvas.drawImage(
        decodedImage,
        ui.Offset(left.toDouble(), y + receiptImage.spaceBeforeDots),
        ui.Paint(),
      );
      y += line.height;
      continue;
    }
    final separator = line.separator;
    if (separator != null) {
      final geometry = _separatorGeometry(document.paper, separator);
      canvas.drawRect(
        ui.Rect.fromLTWH(
          geometry.leftDots.toDouble(),
          y + separator.spaceBeforeDots,
          geometry.widthDots.toDouble(),
          separator.thicknessDots.toDouble(),
        ),
        ui.Paint()..color = const ui.Color(0xFF000000),
      );
      y += line.height;
      continue;
    }
    line.painter!.paint(canvas, ui.Offset(horizontalMargin, y));
    final trailingPainter = line.trailingPainter;
    if (trailingPainter != null) {
      trailingPainter.paint(
        canvas,
        ui.Offset(width - horizontalMargin - trailingPainter.width, y),
      );
    }
    y += line.height;
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, imageHeight);
  picture.dispose();
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw const ReceiptTemplateException(
        'Unable to encode the Star receipt image.',
      );
    }
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}

class _BitmapPaintLine {
  const _BitmapPaintLine({
    required this.height,
    this.painter,
    this.trailingPainter,
    this.receiptImage,
    this.separator,
  });

  final TextPainter? painter;
  final double height;
  final TextPainter? trailingPainter;
  final _ReceiptImageLine? receiptImage;
  final _ReceiptSeparatorLine? separator;
}

Uint8List _imageToMonochromeRaster({
  required ReceiptPaperProfile paper,
  required _ReceiptImageLine image,
  required int imageWidth,
  required int imageHeight,
  required Uint8List rgba,
}) {
  final widthBytes = (paper.widthDots + 7) ~/ 8;
  final totalHeight =
      image.spaceBeforeDots + imageHeight + image.spaceAfterDots;
  final raster = Uint8List(widthBytes * totalHeight);
  final left = _imageLeftDots(
    paper,
    imageWidth: imageWidth,
    position: image.position,
  );

  for (var y = 0; y < imageHeight; y++) {
    final targetRow = (image.spaceBeforeDots + y) * widthBytes;
    for (var x = 0; x < imageWidth; x++) {
      final sourceOffset = (y * imageWidth + x) * 4;
      final alpha = rgba[sourceOffset + 3];
      final inverseAlpha = 255 - alpha;
      final red = (rgba[sourceOffset] * alpha + 255 * inverseAlpha) ~/ 255;
      final green =
          (rgba[sourceOffset + 1] * alpha + 255 * inverseAlpha) ~/ 255;
      final blue = (rgba[sourceOffset + 2] * alpha + 255 * inverseAlpha) ~/ 255;
      final luminance = (red * 299 + green * 587 + blue * 114) ~/ 1000;
      if (luminance >= 210) continue;
      final targetX = left + x;
      raster[targetRow + (targetX >> 3)] |= 0x80 >> (targetX & 7);
    }
  }
  return raster;
}

List<int> _imageToEscPosBytes(
  ReceiptPaperProfile paper,
  _ReceiptImageLine image,
) {
  final raster = image.escPosRaster;
  if (raster == null || image.renderedHeight <= 0) {
    throw ReceiptTemplateException(
      'Receipt image ${image.asset} has not been loaded.',
    );
  }
  final widthBytes = (paper.widthDots + 7) ~/ 8;
  final heightDots = image.totalHeight;
  return [
    0x1B,
    0x61,
    0x00,
    0x1D,
    0x76,
    0x30,
    0x00,
    widthBytes & 0xFF,
    (widthBytes >> 8) & 0xFF,
    heightDots & 0xFF,
    (heightDots >> 8) & 0xFF,
    ...raster,
  ];
}

int _imageLeftDots(
  ReceiptPaperProfile paper, {
  required int imageWidth,
  required ReceiptAlignment position,
}) {
  final contentWidth = paper.widthDots - paper.horizontalMarginDots * 2;
  final remaining = math.max(0, contentWidth - imageWidth);
  final offset = switch (position) {
    ReceiptAlignment.left => 0,
    ReceiptAlignment.center => remaining ~/ 2,
    ReceiptAlignment.right => remaining,
  };
  return paper.horizontalMarginDots + offset;
}

class _SeparatorGeometry {
  const _SeparatorGeometry({required this.leftDots, required this.widthDots});

  final int leftDots;
  final int widthDots;
}

_SeparatorGeometry _separatorGeometry(
  ReceiptPaperProfile paper,
  _ReceiptSeparatorLine separator,
) {
  final contentWidth = paper.widthDots - paper.horizontalMarginDots * 2;
  final widthDots = (contentWidth * separator.widthPercent / 100).round().clamp(
    1,
    contentWidth,
  );
  final remaining = contentWidth - widthDots;
  final offset = switch (separator.position) {
    ReceiptAlignment.left => 0,
    ReceiptAlignment.center => remaining ~/ 2,
    ReceiptAlignment.right => remaining,
  };
  return _SeparatorGeometry(
    leftDots: paper.horizontalMarginDots + offset,
    widthDots: widthDots,
  );
}

List<int> _separatorToEscPosBytes(
  ReceiptPaperProfile paper,
  _ReceiptSeparatorLine separator,
) {
  final geometry = _separatorGeometry(paper, separator);
  final widthBytes = (paper.widthDots + 7) ~/ 8;
  final heightDots =
      separator.spaceBeforeDots +
      separator.thicknessDots +
      separator.spaceAfterDots;
  final raster = Uint8List(widthBytes * heightDots);
  final firstBlackRow = separator.spaceBeforeDots;
  final lastBlackRow = firstBlackRow + separator.thicknessDots;
  final lastBlackColumn = geometry.leftDots + geometry.widthDots;
  for (var y = firstBlackRow; y < lastBlackRow; y++) {
    final rowOffset = y * widthBytes;
    for (var x = geometry.leftDots; x < lastBlackColumn; x++) {
      raster[rowOffset + (x >> 3)] |= 0x80 >> (x & 7);
    }
  }
  return [
    0x1B,
    0x61,
    0x00,
    0x1D,
    0x76,
    0x30,
    0x00,
    widthBytes & 0xFF,
    (widthBytes >> 8) & 0xFF,
    heightDots & 0xFF,
    (heightDots >> 8) & 0xFF,
    ...raster,
  ];
}

Map<String, dynamic> _orderContext(
  MerchantOrder order,
  MerchantStoreProfileConfig? storeProfile,
) {
  final dueAt = _receiptDueAtLabel(order);
  return {
    'app': {'name': 'Powered by Speedfeast'},
    'store': {
      'name': _fallback(storeProfile?.name, fallback: 'Restaurant'),
      'phone': storeProfile?.phone ?? '',
      'address': storeProfile?.addressDisplay ?? '',
    },
    'customer': {'displayName': _receiptCustomerLine(order)},
    'order': {
      'shortId': _shortOrderId(order.id),
      'fulfillmentLabel': _receiptFulfillmentLabel(order),
      'paymentLabel': _receiptPaymentLabel(order),
      'dueAtLabel': dueAt,
      'note': order.orderNote,
      'itemCountLabel':
          '${order.itemCount} Item${order.itemCount == 1 ? '' : 's'}',
      'hasItems': order.items.isNotEmpty,
      'items': [
        for (final item in order.items)
          {
            'quantity': item.quantity,
            'name': item.name,
            'price': item.price,
            'isReward': item.isRewardItem,
            'instructions': item.specialInstructions,
            'optionGroups': [
              for (final group in item.optionGroups.entries)
                {
                  'name': group.key.trim().isEmpty ? 'Options' : group.key,
                  'options': [
                    for (final option in group.value)
                      {
                        'quantity': option.quantity,
                        'name': option.name,
                        'price': option.totalPrice,
                      },
                  ],
                },
            ],
          },
      ],
    },
    'pricing': {
      'subtotal': _receiptSubtotal(order),
      'deliveryFee': order.pricing.deliveryFee,
      'serviceFee': order.pricing.deliveryServiceFee,
      'tax': order.pricing.taxes,
      'tip': order.pricing.tipAmount,
      'refunded': -order.refundedAmount,
      'hasRefund': order.refundedAmount > 0,
      'total': _receiptTotal(order),
    },
  };
}

List<int> _encodeLatin1Lossy(String text) {
  return [
    for (final codeUnit in text.codeUnits) codeUnit <= 0xFF ? codeUnit : 0x3F,
  ];
}

String _valueText(dynamic value) {
  if (value == null) return '';
  if (value is double && value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  return value.toString();
}

double _numericValue(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

String _receiptFulfillmentLabel(MerchantOrder order) {
  if (order.isDelivery) return 'Delivery';
  if (order.isTakeout) return 'Takeout';
  if (order.isDineIn) return 'Dine-in';
  return order.fulfillmentLabel;
}

String _receiptCustomerLine(MerchantOrder order) {
  if (order.isDineIn) {
    final table = order.tableNumber.trim();
    return table.isEmpty ? '' : 'T $table';
  }
  final name = order.customerName.trim();
  if (name.isNotEmpty) return _maskCustomerLastName(name);
  return order.customerPhone.trim();
}

String _maskCustomerLastName(String value) {
  final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  final nameParts = normalized.split(' ');
  if (nameParts.length < 2) return normalized;

  final lastName = nameParts.removeLast();
  final lastNameWithoutDot = lastName.endsWith('.')
      ? lastName.substring(0, lastName.length - 1)
      : lastName;
  if (lastNameWithoutDot.isEmpty) return normalized;

  final initial = String.fromCharCode(
    lastNameWithoutDot.runes.first,
  ).toUpperCase();
  return '${nameParts.join(' ')} $initial.';
}

String _receiptPaymentLabel(MerchantOrder order) {
  if (!order.isInStorePayment) {
    final label = order.paymentStatusLabel.trim();
    return label.isEmpty ? 'Not started' : label;
  }
  if (order.isAwaitingInStoreCollection) {
    if (order.isDineIn) return order.inStorePaymentLabel;
    return '${order.inStorePaymentLabel} · Awaiting';
  }
  if (order.normalizedPaymentStatus == 'paid') {
    final method = order.paymentMethodLabel.trim();
    return method.isEmpty ? 'Paid' : '$method paid';
  }
  final label = order.paymentStatusLabel.trim();
  return label.isEmpty ? order.inStorePaymentLabel : label;
}

String _receiptDueAtLabel(MerchantOrder order) {
  if (order.dueAt != null) return _formatReceiptDateTime(order.dueAt!);
  return order.dueAtLabel.trim();
}

String _formatReceiptDateTime(DateTime value) {
  final local = value.toLocal();
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  final rawHour = local.hour % 12;
  final hour = rawHour == 0 ? 12 : rawHour;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour >= 12 ? 'PM' : 'AM';
  return '${months[local.month - 1]} ${local.day}, $hour:$minute $period';
}

double _receiptSubtotal(MerchantOrder order) {
  if (order.pricing.subtotal > 0) return order.pricing.subtotal;
  return order.items.fold<double>(0, (sum, item) => sum + item.price);
}

double _receiptTotal(MerchantOrder order) {
  if (order.pricing.total > 0) return order.pricing.total;
  return order.totalAmount;
}

String _shortOrderId(String value) {
  final trimmed = value.trim();
  if (trimmed.length <= 8) return trimmed;
  return trimmed.substring(0, 8);
}

String _fallback(String? value, {String fallback = ''}) {
  final text = value?.trim() ?? '';
  return text.isEmpty ? fallback : text;
}
