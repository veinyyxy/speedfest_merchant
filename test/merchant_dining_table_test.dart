import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:speedfest_merchant/Common/dine_in_table_qr_document.dart';
import 'package:speedfest_merchant/Common/merchant_permissions.dart';
import 'package:speedfest_merchant/Models/merchant_dining_table.dart';

void main() {
  const tableToken = 'table-token-123';

  test('dining table parses API values and builds a portable QR payload', () {
    final table = MerchantDiningTable.fromJson({
      'table_id': 'table-id',
      'store_id': 'store-id',
      'table_number': '12',
      'table_token': tableToken,
      'is_active': true,
      'created_at': '2026-07-19T10:00:00.000Z',
    });

    expect(table.tableNumber, '12');
    expect(table.isActive, isTrue);
    expect(
      table.effectiveQrPayload,
      'speedfeast://dine-in/table?table_token=table-token-123',
    );
  });

  test(
    'dining table QR PDF remains valid when qr_payload is omitted',
    () async {
      final table = MerchantDiningTable.fromJson({
        'table_id': 'table-id',
        'store_id': 'store-id',
        'table_number': 'Patio 4',
        'table_token': tableToken,
        'is_active': true,
      });

      final bytes = await buildDineInTableQrPdf(table: table);

      expect(utf8.decode(bytes.take(4).toList()), '%PDF');
      expect(bytes.length, greaterThan(1000));
    },
  );

  test('table management permissions are available to the UI', () {
    expect(MerchantPermissions.tablesView, 'tables.view');
    expect(MerchantPermissions.tablesManage, 'tables.manage');
    expect(
      MerchantPermissions.settingsArea,
      contains(MerchantPermissions.tablesView),
    );
  });
}
