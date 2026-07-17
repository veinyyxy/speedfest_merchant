import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speedfest_merchant/Controller/merchant_auto_print_service.dart';
import 'package:speedfest_merchant/Models/merchant_order_automation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('order automation settings use the server field names', () {
    final settings = MerchantOrderAutomationSettings.fromJson(const {
      'auto_accept_enabled': true,
      'preparation_minutes': 25,
      'auto_print_enabled': true,
      'auto_ready_enabled': false,
    });

    expect(settings.autoAcceptEnabled, isTrue);
    expect(settings.preparationMinutes, 25);
    expect(settings.autoPrintEnabled, isTrue);
    expect(settings.autoReadyEnabled, isFalse);
    expect(settings.toJson()['preparation_minutes'], 25);
  });

  test('print jobs require an order and active claim token', () {
    final job = MerchantPrintJob.fromJson(const {
      'print_job_id': 'job-1',
      'order_id': 'order-1',
      'claim_token': 'claim-1',
      'job_type': 'order_receipt',
    });

    expect(job.isValid, isTrue);
    expect(job.orderId, 'order-1');
  });

  test('completed print jobs are remembered locally', () async {
    SharedPreferences.setMockInitialValues({});
    final service = MerchantAutoPrintService.instance;

    expect(await service.wasPrinted('job-1'), isFalse);
    await service.markPrinted('job-1');
    expect(await service.wasPrinted('job-1'), isTrue);
  });
}
