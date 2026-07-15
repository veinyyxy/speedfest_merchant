import 'package:flutter_test/flutter_test.dart';
import 'package:speedfest_merchant/Models/merchant_printer.dart';

void main() {
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
      );

      final restored = MerchantPrinter.fromJson(original.toJson());

      expect(restored.protocol, MerchantPrinterProtocol.starPrnt);
      expect(restored.protocolLabel, 'StarPRNT / Star Line');
    });
  });
}
