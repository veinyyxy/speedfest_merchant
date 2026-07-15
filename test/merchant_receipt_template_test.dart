import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speedfest_merchant/Common/printer/merchant_receipt_renderer.dart';
import 'package:speedfest_merchant/Common/printer/receipt_template.dart';
import 'package:speedfest_merchant/Models/merchant_order.dart';
import 'package:speedfest_merchant/Models/merchant_printer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled primary and fallback receipt templates are valid', () async {
    for (final path in const [
      'assets/printer_templates/order_receipt_v1.json',
      'assets/printer_templates/order_receipt_fallback_v1.json',
    ]) {
      final raw = await rootBundle.loadString(path);
      final template = ReceiptTemplateConfig.fromJson(
        (jsonDecode(raw) as Map).cast<String, dynamic>(),
      );

      expect(template.schemaVersion, 1);
      expect(template.sections, isNotEmpty);
      expect(template.testSections, isNotEmpty);
      expect(template.paperProfiles.keys, containsAll(['mm58', 'mm80']));
    }
  });

  test('one local template renders ESC/POS, text and HTML', () async {
    final renderer = MerchantReceiptRenderer();
    final order = MerchantOrder.fromJson({
      'order_id': '1234567890abcdef',
      'status': 'accepted',
      'fulfillment_type': 'delivery',
      'payment_status': 'paid',
      'payment_channel': 'online',
      'customer': {'name': 'Alex'},
      'items': [
        {
          'name': 'Burger',
          'quantity': 1,
          'subtotal': 12.5,
          'selected_options': [
            {'group_name': 'Side', 'name': 'Fries'},
          ],
        },
      ],
      'pricing': {'subtotal': 12.5, 'taxes': 1.63, 'total': 14.13},
    });

    final receipt = await renderer.renderOrder(
      order: order,
      paperSize: MerchantPrinterPaperSize.mm80,
      includeBitmap: false,
    );

    expect(receipt.text, contains('SpeedFeast'));
    expect(receipt.text, contains('1x Burger'));
    expect(receipt.text, contains(r'$12.50'));
    expect(receipt.text, isNot(contains('Delivery fee')));
    expect(receipt.text, isNot(matches(RegExp(r'-{3,}'))));
    expect(receipt.html, isNot(contains('Default order receipt')));
    expect(receipt.html, contains('background:#000'));
    expect(receipt.escPosBytes.take(2), [0x1B, 0x40]);
    expect(
      _containsByteSequence(receipt.escPosBytes, const [0x1D, 0x76, 0x30, 0]),
      isTrue,
    );
    expect(receipt.paperWidthDots, 576);
    expect(receipt.bitmapPng, isNull);
  });

  testWidgets('Star receipt renderer produces a PNG image', (tester) async {
    final renderer = MerchantReceiptRenderer();
    final printer = MerchantPrinter.bluetooth(
      id: 'star-test',
      name: 'TSP100',
      address: '00:11:22:33:44:55',
      protocol: MerchantPrinterProtocol.starPrnt,
    );

    final receipt = await tester.runAsync(
      () => renderer.renderTest(printer: printer, includeBitmap: true),
    );

    expect(receipt, isNotNull);
    expect(receipt!.bitmapPng, isNotNull);
    expect(receipt.bitmapPng!.take(4), [0x89, 0x50, 0x4E, 0x47]);
  });

  test('template validation rejects an unknown style', () async {
    final raw = await rootBundle.loadString(
      'assets/printer_templates/order_receipt_v1.json',
    );
    final json = (jsonDecode(raw) as Map).cast<String, dynamic>();
    final sections = json['sections'] as List;
    (sections.first as Map)['style'] = 'missing-style';

    expect(
      () => ReceiptTemplateConfig.fromJson(json),
      throwsA(isA<ReceiptTemplateException>()),
    );
  });

  test(
    'loader uses the bundled fallback when primary JSON is invalid',
    () async {
      final fallback = await rootBundle.loadString(
        'assets/printer_templates/order_receipt_fallback_v1.json',
      );
      final loader = ReceiptTemplateLoader(
        bundle: _MapAssetBundle({
          'primary.json': '{}',
          'fallback.json': fallback,
        }),
        primaryAsset: 'primary.json',
        fallbackAsset: 'fallback.json',
      );

      final loaded = await loader.load();

      expect(loaded.usedFallback, isTrue);
      expect(loaded.assetPath, 'fallback.json');
      expect(loaded.template.templateId, 'order_receipt_fallback_v1');
      expect(loaded.primaryError, isNotNull);
    },
  );
}

bool _containsByteSequence(List<int> bytes, List<int> pattern) {
  if (pattern.isEmpty) return true;
  for (var start = 0; start <= bytes.length - pattern.length; start++) {
    var matches = true;
    for (var index = 0; index < pattern.length; index++) {
      if (bytes[start + index] != pattern[index]) {
        matches = false;
        break;
      }
    }
    if (matches) return true;
  }
  return false;
}

class _MapAssetBundle extends CachingAssetBundle {
  _MapAssetBundle(this.assets);

  final Map<String, String> assets;

  @override
  Future<ByteData> load(String key) async {
    final value = assets[key];
    if (value == null) throw StateError('Missing test asset: $key');
    final bytes = Uint8List.fromList(utf8.encode(value));
    return ByteData.sublistView(bytes);
  }
}
