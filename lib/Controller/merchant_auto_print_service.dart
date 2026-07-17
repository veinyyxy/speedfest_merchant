import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../Common/merchant_service_config.dart';
import '../Models/merchant_order_automation.dart';
import 'signed_api_client.dart';

class MerchantAutoPrintService {
  MerchantAutoPrintService._();

  static final instance = MerchantAutoPrintService._();

  static const _deviceIdKey = 'merchant_auto_print_device_id_v1';
  static const _printedJobIdsKey = 'merchant_auto_print_completed_jobs_v1';
  static const _maxRememberedJobs = 100;

  Future<MerchantPrintJob?> claimNext({
    required SignedApiClient apiClient,
    required String token,
  }) async {
    final rawResponse = await apiClient.post(
      MerchantServiceConfig.merchantPrintJobClaimPath,
      {'device_id': await _deviceId()},
      token: token,
    );
    final response = Map<String, dynamic>.from(rawResponse as Map);
    final rawJob = response['job'];
    if (rawJob is! Map) return null;
    final job = MerchantPrintJob.fromJson(Map<String, dynamic>.from(rawJob));
    return job.isValid ? job : null;
  }

  Future<void> reportResult({
    required SignedApiClient apiClient,
    required String token,
    required MerchantPrintJob job,
    required bool success,
    String? error,
  }) async {
    await apiClient
        .post(MerchantServiceConfig.merchantPrintJobResultPath(job.id), {
          'claim_token': job.claimToken,
          'success': success,
          if (!success && error != null && error.trim().isNotEmpty)
            'error': error.trim(),
        }, token: token);
  }

  Future<bool> wasPrinted(String printJobId) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_printedJobIdsKey) ?? const <String>[])
        .contains(printJobId);
  }

  Future<void> markPrinted(String printJobId) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = <String>[
      printJobId,
      ...(prefs.getStringList(_printedJobIdsKey) ?? const <String>[]).where(
        (id) => id != printJobId,
      ),
    ];
    if (ids.length > _maxRememberedJobs) {
      ids.removeRange(_maxRememberedJobs, ids.length);
    }
    await prefs.setStringList(_printedJobIdsKey, ids);
  }

  Future<String> _deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_deviceIdKey)?.trim() ?? '';
    if (saved.isNotEmpty) return saved;

    final random = Random.secure();
    final bytes = List<int>.generate(18, (_) => random.nextInt(256));
    final suffix = base64UrlEncode(bytes).replaceAll('=', '');
    final deviceId =
        'merchant-${DateTime.now().microsecondsSinceEpoch}-$suffix';
    await prefs.setString(_deviceIdKey, deviceId);
    return deviceId;
  }
}
