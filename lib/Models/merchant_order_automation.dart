class MerchantOrderAutomationSettings {
  const MerchantOrderAutomationSettings({
    required this.autoAcceptEnabled,
    required this.preparationMinutes,
    required this.autoPrintEnabled,
    required this.autoReadyEnabled,
  });

  final bool autoAcceptEnabled;
  final int preparationMinutes;
  final bool autoPrintEnabled;
  final bool autoReadyEnabled;

  factory MerchantOrderAutomationSettings.defaults() {
    return const MerchantOrderAutomationSettings(
      autoAcceptEnabled: false,
      preparationMinutes: 30,
      autoPrintEnabled: true,
      autoReadyEnabled: false,
    );
  }

  factory MerchantOrderAutomationSettings.fromJson(Map<String, dynamic> json) {
    return MerchantOrderAutomationSettings(
      autoAcceptEnabled: _readBool(
        json['auto_accept_enabled'] ?? json['autoAcceptEnabled'],
      ),
      preparationMinutes: _readInt(
        json['preparation_minutes'] ?? json['preparationMinutes'],
        fallback: 30,
      ),
      autoPrintEnabled: _readBool(
        json['auto_print_enabled'] ?? json['autoPrintEnabled'],
        fallback: true,
      ),
      autoReadyEnabled: _readBool(
        json['auto_ready_enabled'] ?? json['autoReadyEnabled'],
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'auto_accept_enabled': autoAcceptEnabled,
      'preparation_minutes': preparationMinutes,
      'auto_print_enabled': autoPrintEnabled,
      'auto_ready_enabled': autoReadyEnabled,
    };
  }
}

class MerchantPrintJob {
  const MerchantPrintJob({
    required this.id,
    required this.orderId,
    required this.claimToken,
    required this.jobType,
  });

  final String id;
  final String orderId;
  final String claimToken;
  final String jobType;

  bool get isValid =>
      id.isNotEmpty && orderId.isNotEmpty && claimToken.isNotEmpty;

  factory MerchantPrintJob.fromJson(Map<String, dynamic> json) {
    return MerchantPrintJob(
      id: _readText(json['print_job_id'] ?? json['printJobId']),
      orderId: _readText(json['order_id'] ?? json['orderId']),
      claimToken: _readText(json['claim_token'] ?? json['claimToken']),
      jobType: _readText(json['job_type'] ?? json['jobType']),
    );
  }
}

String _readText(dynamic value) => value?.toString().trim() ?? '';

int _readInt(dynamic value, {required int fallback}) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

bool _readBool(dynamic value, {bool fallback = false}) {
  if (value is bool) return value;
  final normalized = value?.toString().trim().toLowerCase();
  if (normalized == 'true' || normalized == '1') return true;
  if (normalized == 'false' || normalized == '0') return false;
  return fallback;
}
