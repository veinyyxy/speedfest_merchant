import 'dart:convert';

import '../../Models/merchant_buyer_config.dart';
import '../../Models/merchant_order.dart';
import '../../Models/merchant_printer.dart';

class MerchantReceiptRenderer {
  const MerchantReceiptRenderer();

  List<int> renderOrderTicket({
    required MerchantOrder order,
    required MerchantPrinterPaperSize paperSize,
    MerchantStoreProfileConfig? storeProfile,
  }) {
    return _styledLinesToEscPosBytes(
      _buildOrderLines(
        order: order,
        paperSize: paperSize,
        storeProfile: storeProfile,
      ),
    );
  }

  List<int> renderTestTicket(MerchantPrinter printer) {
    final width = printer.lineWidth;
    final lines = <String>[
      _center('SpeedFeast', width),
      _center('Printer test', width),
      _separator(width),
      'Printer: ${printer.displayName}',
      'Type: ${printer.connectionLabel}',
      'Target: ${printer.targetLabel}',
      'Paper: ${printer.paperSizeLabel}',
      _separator(width),
      'If you can read this, printing is ready.',
      '',
      '',
    ];
    return _plainTextToEscPosBytes(lines.join('\n'));
  }

  String renderOrderText({
    required MerchantOrder order,
    required MerchantPrinterPaperSize paperSize,
    MerchantStoreProfileConfig? storeProfile,
  }) {
    return _buildOrderLines(
      order: order,
      paperSize: paperSize,
      storeProfile: storeProfile,
    ).map((line) => line.text).join('\n');
  }

  String renderOrderHtml({
    required MerchantOrder order,
    required MerchantPrinterPaperSize paperSize,
    MerchantStoreProfileConfig? storeProfile,
  }) {
    final lines = _buildOrderLines(
      order: order,
      paperSize: paperSize,
      storeProfile: storeProfile,
    );
    return '''
<div style="font-family: 'Liberation Sans', 'Noto Sans SC', Arial, sans-serif; color: #000; width: 72mm;">
${lines.map(_receiptLineToHtml).join('\n')}
</div>
''';
  }

  List<_ReceiptLine> _buildOrderLines({
    required MerchantOrder order,
    required MerchantPrinterPaperSize paperSize,
    MerchantStoreProfileConfig? storeProfile,
  }) {
    final width = switch (paperSize) {
      MerchantPrinterPaperSize.mm58 => 32,
      MerchantPrinterPaperSize.mm80 => 48,
    };
    final lines = <_ReceiptLine>[];

    lines
      ..add(const _ReceiptLine('SpeedFeast', _ReceiptTextStyle.p1))
      ..add(
        _ReceiptLine(
          _fallback(storeProfile?.name, fallback: 'Restaurant'),
          _ReceiptTextStyle.p2,
        ),
      )
      ..add(
        _ReceiptLine(_receiptFulfillmentLabel(order), _ReceiptTextStyle.p2),
      );

    final customerLine = _receiptCustomerLine(order);
    if (customerLine.isNotEmpty) {
      _addWrappedStyled(lines, customerLine, width, _ReceiptTextStyle.p4);
    }

    lines
      ..add(
        _ReceiptLine('ID: #${_shortOrderId(order.id)}', _ReceiptTextStyle.p6),
      )
      ..add(
        _ReceiptLine(
          'Payment: ${_receiptPaymentLabel(order)}',
          _ReceiptTextStyle.p7,
        ),
      );

    final dueAt = _receiptDueAtLabel(order);
    if (dueAt.isNotEmpty) {
      lines.add(_ReceiptLine('Due at $dueAt', _ReceiptTextStyle.p8));
    }

    lines
      ..add(
        _ReceiptLine(
          '${order.itemCount} Item${order.itemCount == 1 ? '' : 's'}',
          _ReceiptTextStyle.p7,
        ),
      )
      ..add(_ReceiptLine(_separator(width), _ReceiptTextStyle.p7));

    if (order.items.isEmpty) {
      lines.add(
        const _ReceiptLine('No item details available.', _ReceiptTextStyle.p9),
      );
    } else {
      for (final item in order.items) {
        _addReceiptMoneyLine(
          lines,
          '${item.quantity}x ${item.name}',
          item.price,
          width,
        );
        if (item.isRewardItem) {
          _addIndented(lines, 'Reward item', width);
        }
        if (item.optionsLabel.isNotEmpty) {
          for (final optionText in item.optionsLabel.split(' · ')) {
            _addIndented(lines, optionText, width);
          }
        }
        if (item.specialInstructions.isNotEmpty) {
          _addIndented(lines, 'Note: ${item.specialInstructions}', width);
        }
      }
    }

    lines.add(_ReceiptLine(_separator(width), _ReceiptTextStyle.p7));
    _addReceiptMoneyLine(lines, 'subtotal', _receiptSubtotal(order), width);
    _addReceiptMoneyLine(
      lines,
      'Delivery fee',
      order.pricing.deliveryFee,
      width,
      hideZero: true,
    );
    _addReceiptMoneyLine(
      lines,
      'Service fee',
      order.pricing.deliveryServiceFee,
      width,
      hideZero: true,
    );
    _addReceiptMoneyLine(
      lines,
      'Tax',
      order.pricing.taxes,
      width,
      hideZero: true,
    );
    _addReceiptMoneyLine(
      lines,
      'Tip',
      order.pricing.tipAmount,
      width,
      hideZero: true,
    );
    if (order.refundedAmount > 0) {
      _addReceiptMoneyLine(lines, 'Refunded', -order.refundedAmount, width);
    }
    lines.add(_ReceiptLine(_separator(width), _ReceiptTextStyle.p9));
    _addReceiptMoneyLine(lines, 'Total', _receiptTotal(order), width);

    lines
      ..add(const _ReceiptLine('', _ReceiptTextStyle.p9))
      ..add(const _ReceiptLine('', _ReceiptTextStyle.p9));

    return lines;
  }

  List<int> _plainTextToEscPosBytes(String text) {
    final bytes = <int>[
      0x1B, 0x40, // Initialize.
      0x1B, 0x74, 16, // Common CP1252 code table.
    ];
    bytes.addAll(_encodeLatin1Lossy(text));
    bytes.addAll([0x0A, 0x0A, 0x0A]);
    return bytes;
  }

  List<int> _styledLinesToEscPosBytes(List<_ReceiptLine> lines) {
    final bytes = <int>[
      0x1B, 0x40, // Initialize.
      0x1B, 0x74, 16, // Common CP1252 code table.
    ];
    for (final line in lines) {
      final spec = _styleSpec(line.style);
      bytes.addAll([0x1B, 0x61, spec.align.code]);
      bytes.addAll([0x1B, 0x21, spec.escPosMode]);
      bytes.addAll(_encodeLatin1Lossy(line.text));
      bytes.add(0x0A);
    }
    bytes.addAll([0x1B, 0x61, 0, 0x1B, 0x21, 0, 0x0A, 0x0A, 0x0A]);
    return bytes;
  }
}

class _ReceiptLine {
  const _ReceiptLine(
    this.text,
    this.style, {
    this.htmlMoneyLabel,
    this.htmlMoneySign,
    this.htmlMoneyNumber,
  });

  final String text;
  final _ReceiptTextStyle style;
  final String? htmlMoneyLabel;
  final String? htmlMoneySign;
  final String? htmlMoneyNumber;
}

class _ReceiptTextSpec {
  const _ReceiptTextSpec({
    required this.align,
    required this.fontSizePt,
    required this.bold,
    required this.smallFont,
    required this.doubleHeight,
    required this.doubleWidth,
  });

  final _ReceiptAlign align;
  final double fontSizePt;
  final bool bold;
  final bool smallFont;
  final bool doubleHeight;
  final bool doubleWidth;

  int get escPosMode {
    var mode = 0;
    if (smallFont) mode |= 0x01;
    if (bold) mode |= 0x08;
    if (doubleHeight) mode |= 0x10;
    if (doubleWidth) mode |= 0x20;
    return mode;
  }
}

enum _ReceiptTextStyle { p1, p2, p4, p6, p7, p8, p9 }

enum _ReceiptAlign {
  left(0),
  center(1),
  right(2);

  const _ReceiptAlign(this.code);

  final int code;
}

_ReceiptTextSpec _styleSpec(_ReceiptTextStyle style) {
  return switch (style) {
    _ReceiptTextStyle.p1 => const _ReceiptTextSpec(
      align: _ReceiptAlign.left,
      fontSizePt: 18,
      bold: true,
      smallFont: false,
      doubleHeight: true,
      doubleWidth: true,
    ),
    _ReceiptTextStyle.p2 => const _ReceiptTextSpec(
      align: _ReceiptAlign.left,
      fontSizePt: 13.7,
      bold: false,
      smallFont: false,
      doubleHeight: false,
      doubleWidth: false,
    ),
    _ReceiptTextStyle.p4 => const _ReceiptTextSpec(
      align: _ReceiptAlign.left,
      fontSizePt: 13.7,
      bold: true,
      smallFont: false,
      doubleHeight: false,
      doubleWidth: false,
    ),
    _ReceiptTextStyle.p6 => const _ReceiptTextSpec(
      align: _ReceiptAlign.center,
      fontSizePt: 18,
      bold: true,
      smallFont: false,
      doubleHeight: true,
      doubleWidth: true,
    ),
    _ReceiptTextStyle.p7 => const _ReceiptTextSpec(
      align: _ReceiptAlign.left,
      fontSizePt: 13.7,
      bold: false,
      smallFont: false,
      doubleHeight: false,
      doubleWidth: false,
    ),
    _ReceiptTextStyle.p8 => const _ReceiptTextSpec(
      align: _ReceiptAlign.left,
      fontSizePt: 13.7,
      bold: true,
      smallFont: false,
      doubleHeight: false,
      doubleWidth: false,
    ),
    _ReceiptTextStyle.p9 => const _ReceiptTextSpec(
      align: _ReceiptAlign.left,
      fontSizePt: 12,
      bold: false,
      smallFont: true,
      doubleHeight: false,
      doubleWidth: false,
    ),
  };
}

String _receiptLineToHtml(_ReceiptLine line) {
  final spec = _styleSpec(line.style);
  final escaped = const HtmlEscape().convert(line.text);
  final align = switch (spec.align) {
    _ReceiptAlign.left => 'left',
    _ReceiptAlign.center => 'center',
    _ReceiptAlign.right => 'right',
  };
  final weight = spec.bold ? '700' : '400';
  final minHeight = spec.fontSizePt * 1.18;
  if (line.htmlMoneyLabel != null && line.htmlMoneyNumber != null) {
    final label = const HtmlEscape().convert(line.htmlMoneyLabel!);
    final sign = const HtmlEscape().convert(line.htmlMoneySign ?? '');
    final number = const HtmlEscape().convert(line.htmlMoneyNumber!);
    return '<div style="display: flex; align-items: flex-start; gap: 8px; '
        'font-size: ${spec.fontSizePt}pt; font-weight: $weight; '
        'line-height: 1.12; min-height: ${minHeight}pt;">'
        '<span style="flex: 1 1 auto; min-width: 0; overflow-wrap: anywhere;">'
        '$label</span>'
        '<span style="flex: 0 0 5.5em; display: inline-grid; '
        'grid-template-columns: 0.55em auto; '
        'font-variant-numeric: tabular-nums; '
        'font-feature-settings: &quot;tnum&quot; 1; white-space: pre;">'
        '<span>$sign</span><span>\$$number</span></span>'
        '</div>';
  }
  return '<div style="white-space: pre-wrap; text-align: $align; '
      'font-size: ${spec.fontSizePt}pt; font-weight: $weight; '
      'line-height: 1.12; min-height: ${minHeight}pt;">$escaped</div>';
}

List<int> _encodeLatin1Lossy(String text) {
  return [
    for (final codeUnit in text.codeUnits) codeUnit <= 0xFF ? codeUnit : 0x3F,
  ];
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
  if (name.isNotEmpty) return name;

  final phone = order.customerPhone.trim();
  if (phone.isNotEmpty) return phone;

  return '';
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

  final dueLabel = order.dueAtLabel.trim();
  if (dueLabel.isNotEmpty) return dueLabel;

  final createdAt = order.createdAt;
  if (createdAt != null) return _formatReceiptDateTime(createdAt);

  return order.createdAtLabel.trim();
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

void _addReceiptMoneyLine(
  List<_ReceiptLine> lines,
  String label,
  double value,
  int width, {
  bool hideZero = false,
}) {
  if (hideZero && value == 0) return;

  final amount = _alignedMoney(value);
  final cleanLabel = label.trim();
  final amountStart = _moneyStartColumn(value, width);
  final labelWidth = amountStart - 1;

  if (labelWidth <= 6) {
    lines.add(_ReceiptLine(amount.padLeft(width), _ReceiptTextStyle.p9));
    return;
  }

  final wrappedLabel = _wrap(cleanLabel, labelWidth);
  if (wrappedLabel.isEmpty) {
    lines.add(_ReceiptLine(amount.padLeft(width), _ReceiptTextStyle.p9));
    return;
  }

  final firstLabel = wrappedLabel.first;
  lines.add(
    _ReceiptLine(
      '$firstLabel${_spaces(amountStart - firstLabel.length)}$amount',
      _ReceiptTextStyle.p9,
      htmlMoneyLabel: firstLabel,
      htmlMoneySign: value < 0 ? '-' : '',
      htmlMoneyNumber: value.abs().toStringAsFixed(2),
    ),
  );

  for (final extraLine in wrappedLabel.skip(1)) {
    lines.add(_ReceiptLine(extraLine, _ReceiptTextStyle.p9));
  }
}

String _alignedMoney(double value) {
  final sign = value < 0 ? '-' : '';
  final number = value.abs().toStringAsFixed(2);
  return '$sign\$$number';
}

int _moneyStartColumn(double value, int width) {
  final signWidth = value < 0 ? 1 : 0;
  return _moneyDollarColumn(value, width) - signWidth;
}

int _moneyDollarColumn(double value, int width) {
  final number = value.abs().toStringAsFixed(2);
  final numberWidth = _moneyNumberWidth(number, width);
  return width - numberWidth - 1;
}

int _moneyNumberWidth(String number, int width) {
  final preferredWidth = width >= 42 ? 8 : 7;
  return number.length > preferredWidth ? number.length : preferredWidth;
}

void _addIndented(List<_ReceiptLine> lines, String value, int width) {
  final text = value.trim();
  if (text.isEmpty) return;
  for (final line in _wrap(text, width - 4)) {
    lines.add(_ReceiptLine('  - $line', _ReceiptTextStyle.p9));
  }
}

void _addWrappedStyled(
  List<_ReceiptLine> lines,
  String value,
  int width,
  _ReceiptTextStyle style,
) {
  for (final line in _wrap(value, width)) {
    lines.add(_ReceiptLine(line, style));
  }
}

List<String> _wrap(String value, int width) {
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

String _center(String value, int width) {
  final text = value.trim();
  if (text.length >= width) return text;
  final left = ((width - text.length) / 2).floor();
  return '${_spaces(left)}$text';
}

String _separator(int width) => ''.padLeft(width, '-');

String _spaces(int count) => ''.padLeft(count);

String _fallback(String? value, {String fallback = ''}) {
  final text = value?.trim() ?? '';
  return text.isEmpty ? fallback : text;
}
