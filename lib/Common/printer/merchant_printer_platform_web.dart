// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html' as dom;

import '../../Models/merchant_printer.dart';
import 'merchant_printer_platform_interface.dart';

MerchantPrinterPlatform createMerchantPrinterPlatform() {
  return const _WebPrinterPlatform();
}

class _WebPrinterPlatform implements MerchantPrinterPlatform {
  const _WebPrinterPlatform();

  @override
  bool get supportsBluetooth => false;

  @override
  bool get supportsBrowserPrint => true;

  @override
  bool get supportsNetwork => false;

  @override
  Future<void> connectBluetoothPrinter(MerchantPrinter printer) {
    throw const MerchantPrinterException(
      'Bluetooth receipt printing is not available on web.',
    );
  }

  @override
  Future<List<MerchantDiscoveredPrinter>> discoverBluetoothPrinters() {
    throw const MerchantPrinterException(
      'Bluetooth discovery is not available on web.',
    );
  }

  @override
  Future<List<MerchantDiscoveredPrinter>> discoverNetworkPrinters({
    int port = 9100,
  }) {
    throw const MerchantPrinterException(
      'Network printer discovery is not available on web.',
    );
  }

  @override
  Future<void> printBluetoothBytes(MerchantPrinter printer, List<int> bytes) {
    throw const MerchantPrinterException(
      'Bluetooth receipt printing is not available on web.',
    );
  }

  @override
  Future<void> printBrowserText({
    required String title,
    required String text,
    String? html,
  }) async {
    final escapedTitle = const HtmlEscape().convert(title);
    final escapedText = const HtmlEscape().convert(text);
    final bodyHtml = html?.trim().isNotEmpty == true
        ? html!.trim()
        : '<pre>$escapedText</pre>';
    final content =
        '''
<!doctype html>
<html>
<head>
  <title>$escapedTitle</title>
  <style>
    body { margin: 24px; }
    pre { white-space: pre-wrap; font-size: 12px; line-height: 1.35; }
    @media print { body { margin: 0; } }
  </style>
</head>
<body>
  $bodyHtml
  <script>
    window.onload = function() { window.print(); };
  </script>
</body>
</html>
''';
    final body = dom.document.body;
    if (body == null) {
      throw const MerchantPrinterException(
        'Browser print preview is not ready yet.',
      );
    }

    final frame = dom.IFrameElement()
      ..style.position = 'fixed'
      ..style.right = '0'
      ..style.bottom = '0'
      ..style.width = '1px'
      ..style.height = '1px'
      ..style.border = '0'
      ..style.opacity = '0'
      ..srcdoc = content;
    body.append(frame);

    try {
      await frame.onLoad.first.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      throw const MerchantPrinterException(
        'Browser print preview could not be prepared.',
      );
    } finally {
      Timer(const Duration(seconds: 20), frame.remove);
    }
  }

  @override
  Future<void> printNetworkBytes(MerchantPrinter printer, List<int> bytes) {
    throw const MerchantPrinterException(
      'Direct IP receipt printing is not available on web.',
    );
  }

  @override
  Future<void> probeNetworkPrinter(MerchantPrinter printer) {
    throw const MerchantPrinterException(
      'Direct IP receipt printing is not available on web.',
    );
  }
}
