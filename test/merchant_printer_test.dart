import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speedfest_merchant/Common/printer/merchant_printer_platform_interface.dart';
import 'package:speedfest_merchant/Common/printer/merchant_receipt_renderer.dart';
import 'package:speedfest_merchant/Controller/merchant_printers_provider.dart';
import 'package:speedfest_merchant/Models/merchant_buyer_config.dart';
import 'package:speedfest_merchant/Models/merchant_order.dart';
import 'package:speedfest_merchant/Models/merchant_printer.dart';
import 'package:speedfest_merchant/PrinterPage/merchant_printers_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MerchantPrinter protocol persistence', () {
    test('legacy saved printers default to ESC/POS', () {
      final printer = MerchantPrinter.fromJson({
        'id': 'legacy',
        'name': 'Legacy printer',
        'connection_type': 'bluetooth',
        'address': '00:11:22:33:44:55',
        'port': 0,
        'paper_size': 'mm80',
        'is_default': true,
      });

      expect(printer.protocol, MerchantPrinterProtocol.escPos);
    });

    test('StarPRNT selection round trips through JSON', () {
      final original = MerchantPrinter.bluetooth(
        id: 'star',
        name: 'TSP100',
        address: '00:11:22:33:44:55',
        protocol: MerchantPrinterProtocol.starPrnt,
        receiptCopies: 4,
      );

      final restored = MerchantPrinter.fromJson(original.toJson());

      expect(restored.protocol, MerchantPrinterProtocol.starPrnt);
      expect(restored.protocolLabel, 'StarPRNT / Star Line');
      expect(restored.receiptCopies, 4);
    });
  });

  test('legacy printer copies default to one', () {
    final printer = MerchantPrinter.fromJson({
      'id': 'legacy',
      'name': 'Legacy printer',
      'connection_type': 'network',
      'address': '192.168.1.20',
      'port': 9100,
      'paper_size': 'mm80',
      'is_default': true,
    });

    expect(printer.receiptCopies, 1);
    expect(printer.receiptCopiesLabel, '1 receipt copy');
  });

  test('saved copy count controls the ESC/POS order payload', () async {
    SharedPreferences.setMockInitialValues({
      'merchant_saved_printers_v1': jsonEncode([
        {
          'id': 'kitchen',
          'name': 'Kitchen printer',
          'connection_type': 'network',
          'address': '192.168.1.20',
          'port': 9100,
          'paper_size': 'mm80',
          'protocol': 'escPos',
          'is_default': true,
        },
      ]),
    });
    final platform = _RecordingPrinterPlatform();
    final provider = MerchantPrintersProvider(
      platform: platform,
      renderer: _FixedReceiptRenderer(),
    );
    await provider.initialize();

    expect(provider.defaultPrinter?.receiptCopies, 1);
    await provider.setPrinterReceiptCopies('kitchen', 3);
    final preferences = await SharedPreferences.getInstance();
    final saved =
        jsonDecode(preferences.getString('merchant_saved_printers_v1')!)
            as List<dynamic>;
    expect((saved.single as Map<String, dynamic>)['receipt_copies'], 3);

    final printed = await provider.printOrder(
      order: MerchantOrder.fromJson({
        'order_id': 'copies-test',
        'fulfillment_type': 'takeout',
        'items': const [],
        'pricing': const {'total': 0},
      }),
    );

    expect(printed, isTrue);
    expect(platform.networkPayloads, [
      [1, 2, 3, 1, 2, 3, 1, 2, 3],
    ]);

    platform.networkPayloads.clear();
    final tested = await provider.testPrinter(provider.defaultPrinter!);
    expect(tested, isTrue);
    expect(platform.networkPayloads, [
      [1, 2, 3],
    ]);
  });

  test('Star printing submits one image job per receipt copy', () async {
    SharedPreferences.setMockInitialValues({
      'merchant_saved_printers_v1': jsonEncode([
        {
          'id': 'star-kitchen',
          'name': 'Star kitchen printer',
          'connection_type': 'bluetooth',
          'address': '00:11:22:33:44:55',
          'port': 0,
          'paper_size': 'mm80',
          'protocol': 'starPrnt',
          'receipt_copies': 3,
          'is_default': true,
        },
      ]),
    });
    final platform = _RecordingPrinterPlatform();
    final provider = MerchantPrintersProvider(
      platform: platform,
      renderer: _FixedReceiptRenderer(),
    );
    await provider.initialize();

    final printed = await provider.printOrder(order: _testOrder());

    expect(printed, isTrue);
    expect(platform.starPrintCalls, 3);
  });

  test('browser printing creates one job with one page per copy', () async {
    SharedPreferences.setMockInitialValues({
      'merchant_saved_printers_v1': jsonEncode([
        {
          'id': 'browser',
          'name': 'Browser print preview',
          'connection_type': 'browser',
          'address': 'browser',
          'port': 0,
          'paper_size': 'mm80',
          'receipt_copies': 3,
          'is_default': true,
        },
      ]),
    });
    final platform = _RecordingPrinterPlatform();
    final provider = MerchantPrintersProvider(
      platform: platform,
      renderer: _FixedReceiptRenderer(),
    );
    await provider.initialize();

    final printed = await provider.printOrder(order: _testOrder());

    expect(printed, isTrue);
    expect(platform.browserPrintCalls, 1);
    expect('<section'.allMatches(platform.browserHtml!).length, 3);
    expect(
      'page-break-after:always'.allMatches(platform.browserHtml!).length,
      2,
    );
  });

  testWidgets('receipt copy setting is available on a narrow phone layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'merchant_saved_printers_v1': jsonEncode([
        {
          'id': 'kitchen',
          'name': 'Kitchen printer',
          'connection_type': 'network',
          'address': '192.168.1.20',
          'port': 9100,
          'paper_size': 'mm80',
          'protocol': 'escPos',
          'receipt_copies': 3,
          'is_default': true,
        },
      ]),
    });
    final provider = MerchantPrintersProvider(
      platform: _RecordingPrinterPlatform(),
      renderer: _FixedReceiptRenderer(),
    );
    await provider.initialize();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(home: MerchantPrintersPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Kitchen printer'),
      250,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.textContaining('3 receipt copies'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Printer actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set receipt copies'));
    await tester.pumpAndSettle();

    expect(find.text('Receipt copies'), findsOneWidget);
    expect(find.text('Copies per order'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

MerchantOrder _testOrder() {
  return MerchantOrder.fromJson({
    'order_id': 'copies-test',
    'fulfillment_type': 'takeout',
    'items': const [],
    'pricing': const {'total': 0},
  });
}

class _FixedReceiptRenderer extends MerchantReceiptRenderer {
  @override
  Future<void> initialize() async {}

  @override
  Future<MerchantReceiptRenderResult> renderOrder({
    required MerchantOrder order,
    required MerchantPrinterPaperSize paperSize,
    MerchantStoreProfileConfig? storeProfile,
    bool includeBitmap = false,
  }) async => _result(includeBitmap);

  @override
  Future<MerchantReceiptRenderResult> renderTest({
    required MerchantPrinter printer,
    bool includeBitmap = false,
  }) async => _result(includeBitmap);

  MerchantReceiptRenderResult _result(bool includeBitmap) {
    return MerchantReceiptRenderResult(
      escPosBytes: const [1, 2, 3],
      text: 'receipt',
      html: '<div>receipt</div>',
      bitmapPng: includeBitmap ? Uint8List.fromList([1, 2, 3]) : null,
      paperWidthDots: 576,
      feedLines: 3,
      cutMode: 'full',
      templateId: 'test',
    );
  }
}

class _RecordingPrinterPlatform implements MerchantPrinterPlatform {
  final List<List<int>> networkPayloads = [];
  int starPrintCalls = 0;
  int browserPrintCalls = 0;
  String? browserHtml;

  @override
  bool get supportsBluetooth => true;

  @override
  bool get supportsBrowserPrint => true;

  @override
  bool get supportsNetwork => true;

  @override
  bool get supportsStarPrinting => true;

  @override
  Future<void> connectBluetoothPrinter(MerchantPrinter printer) async {}

  @override
  Future<void> connectStarPrinter(MerchantPrinter printer) async {}

  @override
  Future<List<MerchantDiscoveredPrinter>> discoverBluetoothPrinters() async =>
      const [];

  @override
  Future<List<MerchantDiscoveredPrinter>> discoverNetworkPrinters({
    int port = 9100,
  }) async => const [];

  @override
  Future<void> printBluetoothBytes(
    MerchantPrinter printer,
    List<int> bytes,
  ) async {}

  @override
  Future<void> printBrowserText({
    required String title,
    required String text,
    String? html,
  }) async {
    browserPrintCalls++;
    browserHtml = html;
  }

  @override
  Future<void> printNetworkBytes(
    MerchantPrinter printer,
    List<int> bytes,
  ) async {
    networkPayloads.add(List<int>.from(bytes));
  }

  @override
  Future<void> printStarImage(
    MerchantPrinter printer,
    Uint8List imageBytes, {
    required int paperWidthDots,
    required int feedLines,
    required String cutMode,
  }) async {
    starPrintCalls++;
  }

  @override
  Future<void> probeNetworkPrinter(MerchantPrinter printer) async {}
}
