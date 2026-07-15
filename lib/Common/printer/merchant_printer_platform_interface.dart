import '../../Models/merchant_printer.dart';

abstract class MerchantPrinterPlatform {
  bool get supportsBluetooth;
  bool get supportsNetwork;
  bool get supportsBrowserPrint;
  bool get supportsStarPrinting;

  Future<List<MerchantDiscoveredPrinter>> discoverBluetoothPrinters();

  Future<List<MerchantDiscoveredPrinter>> discoverNetworkPrinters({
    int port = 9100,
  });

  Future<void> connectBluetoothPrinter(MerchantPrinter printer);

  Future<void> probeNetworkPrinter(MerchantPrinter printer);

  Future<void> connectStarPrinter(MerchantPrinter printer);

  Future<void> printBluetoothBytes(MerchantPrinter printer, List<int> bytes);

  Future<void> printNetworkBytes(MerchantPrinter printer, List<int> bytes);

  Future<void> printStarText(MerchantPrinter printer, String text);

  Future<void> printBrowserText({
    required String title,
    required String text,
    String? html,
  });
}

class MerchantPrinterException implements Exception {
  const MerchantPrinterException(this.message);

  final String message;

  @override
  String toString() => message;
}
