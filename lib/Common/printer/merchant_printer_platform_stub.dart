import '../../Models/merchant_printer.dart';
import 'merchant_printer_platform_interface.dart';

MerchantPrinterPlatform createMerchantPrinterPlatform() {
  return const _UnsupportedPrinterPlatform();
}

class _UnsupportedPrinterPlatform implements MerchantPrinterPlatform {
  const _UnsupportedPrinterPlatform();

  @override
  bool get supportsBluetooth => false;

  @override
  bool get supportsBrowserPrint => false;

  @override
  bool get supportsNetwork => false;

  @override
  bool get supportsStarPrinting => false;

  @override
  Future<void> connectBluetoothPrinter(MerchantPrinter printer) {
    throw const MerchantPrinterException(
      'Bluetooth printing is not available on this platform.',
    );
  }

  @override
  Future<void> connectStarPrinter(MerchantPrinter printer) {
    throw const MerchantPrinterException(
      'Star printer support is not available on this platform.',
    );
  }

  @override
  Future<List<MerchantDiscoveredPrinter>> discoverBluetoothPrinters() {
    throw const MerchantPrinterException(
      'Bluetooth discovery is not available on this platform.',
    );
  }

  @override
  Future<List<MerchantDiscoveredPrinter>> discoverNetworkPrinters({
    int port = 9100,
  }) {
    throw const MerchantPrinterException(
      'Network printer discovery is not available on this platform.',
    );
  }

  @override
  Future<void> printBluetoothBytes(MerchantPrinter printer, List<int> bytes) {
    throw const MerchantPrinterException(
      'Bluetooth printing is not available on this platform.',
    );
  }

  @override
  Future<void> printBrowserText({
    required String title,
    required String text,
    String? html,
  }) {
    throw const MerchantPrinterException(
      'Browser printing is not available on this platform.',
    );
  }

  @override
  Future<void> printNetworkBytes(MerchantPrinter printer, List<int> bytes) {
    throw const MerchantPrinterException(
      'Network printing is not available on this platform.',
    );
  }

  @override
  Future<void> printStarText(MerchantPrinter printer, String text) {
    throw const MerchantPrinterException(
      'Star printer support is not available on this platform.',
    );
  }

  @override
  Future<void> probeNetworkPrinter(MerchantPrinter printer) {
    throw const MerchantPrinterException(
      'Network printer connection is not available on this platform.',
    );
  }
}
