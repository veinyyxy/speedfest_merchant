class MerchantPrinter {
  const MerchantPrinter({
    required this.id,
    required this.name,
    required this.connectionType,
    required this.address,
    required this.port,
    required this.paperSize,
    required this.isDefault,
    required this.lastConnectedAt,
  });

  final String id;
  final String name;
  final MerchantPrinterConnectionType connectionType;
  final String address;
  final int port;
  final MerchantPrinterPaperSize paperSize;
  final bool isDefault;
  final DateTime? lastConnectedAt;

  bool get isBluetooth =>
      connectionType == MerchantPrinterConnectionType.bluetooth;
  bool get isNetwork => connectionType == MerchantPrinterConnectionType.network;

  String get displayName => name.trim().isEmpty ? 'Receipt printer' : name;
  String get targetLabel {
    if (isNetwork) return '$address:$port';
    if (isBluetooth) return address;
    return 'Browser print';
  }

  String get connectionLabel {
    return switch (connectionType) {
      MerchantPrinterConnectionType.bluetooth => 'Bluetooth',
      MerchantPrinterConnectionType.network => 'IP address',
      MerchantPrinterConnectionType.browser => 'Browser',
    };
  }

  String get paperSizeLabel {
    return switch (paperSize) {
      MerchantPrinterPaperSize.mm58 => '58 mm',
      MerchantPrinterPaperSize.mm80 => '80 mm',
    };
  }

  int get lineWidth {
    return switch (paperSize) {
      MerchantPrinterPaperSize.mm58 => 32,
      MerchantPrinterPaperSize.mm80 => 48,
    };
  }

  MerchantPrinter copyWith({
    String? id,
    String? name,
    MerchantPrinterConnectionType? connectionType,
    String? address,
    int? port,
    MerchantPrinterPaperSize? paperSize,
    bool? isDefault,
    DateTime? lastConnectedAt,
    bool clearLastConnectedAt = false,
  }) {
    return MerchantPrinter(
      id: id ?? this.id,
      name: name ?? this.name,
      connectionType: connectionType ?? this.connectionType,
      address: address ?? this.address,
      port: port ?? this.port,
      paperSize: paperSize ?? this.paperSize,
      isDefault: isDefault ?? this.isDefault,
      lastConnectedAt: clearLastConnectedAt
          ? null
          : lastConnectedAt ?? this.lastConnectedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'connection_type': connectionType.name,
      'address': address,
      'port': port,
      'paper_size': paperSize.name,
      'is_default': isDefault,
      'last_connected_at': lastConnectedAt?.toIso8601String(),
    };
  }

  factory MerchantPrinter.fromJson(Map<String, dynamic> json) {
    return MerchantPrinter(
      id: _readString(json['id']),
      name: _readString(json['name'], fallback: 'Receipt printer'),
      connectionType: _readConnectionType(json['connection_type']),
      address: _readString(json['address']),
      port: _readInt(json['port'], fallback: 9100),
      paperSize: _readPaperSize(json['paper_size']),
      isDefault: _readBool(json['is_default']),
      lastConnectedAt: DateTime.tryParse(
        _readString(json['last_connected_at']),
      ),
    );
  }

  factory MerchantPrinter.network({
    required String id,
    required String name,
    required String address,
    int port = 9100,
    MerchantPrinterPaperSize paperSize = MerchantPrinterPaperSize.mm80,
    bool isDefault = false,
  }) {
    return MerchantPrinter(
      id: id,
      name: name,
      connectionType: MerchantPrinterConnectionType.network,
      address: address,
      port: port,
      paperSize: paperSize,
      isDefault: isDefault,
      lastConnectedAt: null,
    );
  }

  factory MerchantPrinter.bluetooth({
    required String id,
    required String name,
    required String address,
    MerchantPrinterPaperSize paperSize = MerchantPrinterPaperSize.mm80,
    bool isDefault = false,
  }) {
    return MerchantPrinter(
      id: id,
      name: name,
      connectionType: MerchantPrinterConnectionType.bluetooth,
      address: address,
      port: 0,
      paperSize: paperSize,
      isDefault: isDefault,
      lastConnectedAt: null,
    );
  }
}

class MerchantDiscoveredPrinter {
  const MerchantDiscoveredPrinter({
    required this.name,
    required this.connectionType,
    required this.address,
    required this.port,
  });

  final String name;
  final MerchantPrinterConnectionType connectionType;
  final String address;
  final int port;

  String get displayName => name.trim().isEmpty ? address : name;
  String get targetLabel => port > 0 ? '$address:$port' : address;

  MerchantPrinter toPrinter({
    required String id,
    required MerchantPrinterPaperSize paperSize,
    required bool isDefault,
  }) {
    return MerchantPrinter(
      id: id,
      name: displayName,
      connectionType: connectionType,
      address: address,
      port: port,
      paperSize: paperSize,
      isDefault: isDefault,
      lastConnectedAt: null,
    );
  }
}

enum MerchantPrinterConnectionType { bluetooth, network, browser }

enum MerchantPrinterPaperSize { mm58, mm80 }

String _readString(dynamic value, {String fallback = ''}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

int _readInt(dynamic value, {int fallback = 0}) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

bool _readBool(dynamic value) {
  if (value is bool) return value;
  final text = value?.toString().trim().toLowerCase() ?? '';
  return text == 'true' || text == '1' || text == 'yes';
}

MerchantPrinterConnectionType _readConnectionType(dynamic value) {
  final text = value?.toString().trim().toLowerCase() ?? '';
  for (final type in MerchantPrinterConnectionType.values) {
    if (type.name == text) return type;
  }
  return MerchantPrinterConnectionType.network;
}

MerchantPrinterPaperSize _readPaperSize(dynamic value) {
  final text = value?.toString().trim().toLowerCase() ?? '';
  for (final size in MerchantPrinterPaperSize.values) {
    if (size.name == text) return size;
  }
  return MerchantPrinterPaperSize.mm80;
}
