class MerchantPrinter {
  static const minReceiptCopies = 1;
  static const maxReceiptCopies = 10;

  const MerchantPrinter({
    required this.id,
    required this.name,
    required this.connectionType,
    required this.address,
    required this.port,
    required this.paperSize,
    this.protocol = MerchantPrinterProtocol.escPos,
    this.receiptCopies = minReceiptCopies,
    required this.isDefault,
    required this.lastConnectedAt,
  }) : assert(
         receiptCopies >= minReceiptCopies && receiptCopies <= maxReceiptCopies,
       );

  final String id;
  final String name;
  final MerchantPrinterConnectionType connectionType;
  final String address;
  final int port;
  final MerchantPrinterPaperSize paperSize;
  final MerchantPrinterProtocol protocol;
  final int receiptCopies;
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

  String get protocolLabel {
    return switch (protocol) {
      MerchantPrinterProtocol.escPos => 'ESC/POS',
      MerchantPrinterProtocol.starPrnt => 'StarPRNT / Star Line',
    };
  }

  String get receiptCopiesLabel =>
      receiptCopies == 1 ? '1 receipt copy' : '$receiptCopies receipt copies';

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
    MerchantPrinterProtocol? protocol,
    int? receiptCopies,
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
      protocol: protocol ?? this.protocol,
      receiptCopies: receiptCopies ?? this.receiptCopies,
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
      'protocol': protocol.name,
      'receipt_copies': receiptCopies,
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
      protocol: _readProtocol(json['protocol']),
      receiptCopies: _readReceiptCopies(json['receipt_copies']),
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
    MerchantPrinterProtocol protocol = MerchantPrinterProtocol.escPos,
    int receiptCopies = minReceiptCopies,
    bool isDefault = false,
  }) {
    return MerchantPrinter(
      id: id,
      name: name,
      connectionType: MerchantPrinterConnectionType.network,
      address: address,
      port: port,
      paperSize: paperSize,
      protocol: protocol,
      receiptCopies: receiptCopies,
      isDefault: isDefault,
      lastConnectedAt: null,
    );
  }

  factory MerchantPrinter.bluetooth({
    required String id,
    required String name,
    required String address,
    MerchantPrinterPaperSize paperSize = MerchantPrinterPaperSize.mm80,
    MerchantPrinterProtocol protocol = MerchantPrinterProtocol.escPos,
    int receiptCopies = minReceiptCopies,
    bool isDefault = false,
  }) {
    return MerchantPrinter(
      id: id,
      name: name,
      connectionType: MerchantPrinterConnectionType.bluetooth,
      address: address,
      port: 0,
      paperSize: paperSize,
      protocol: protocol,
      receiptCopies: receiptCopies,
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
    required MerchantPrinterProtocol protocol,
    int receiptCopies = MerchantPrinter.minReceiptCopies,
    required bool isDefault,
  }) {
    return MerchantPrinter(
      id: id,
      name: displayName,
      connectionType: connectionType,
      address: address,
      port: port,
      paperSize: paperSize,
      protocol: protocol,
      receiptCopies: receiptCopies,
      isDefault: isDefault,
      lastConnectedAt: null,
    );
  }
}

enum MerchantPrinterConnectionType { bluetooth, network, browser }

enum MerchantPrinterPaperSize { mm58, mm80 }

enum MerchantPrinterProtocol { escPos, starPrnt }

String _readString(dynamic value, {String fallback = ''}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

int _readInt(dynamic value, {int fallback = 0}) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

int _readReceiptCopies(dynamic value) {
  return _readInt(value, fallback: MerchantPrinter.minReceiptCopies)
      .clamp(MerchantPrinter.minReceiptCopies, MerchantPrinter.maxReceiptCopies)
      .toInt();
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

MerchantPrinterProtocol _readProtocol(dynamic value) {
  final text = value?.toString().trim().toLowerCase() ?? '';
  for (final protocol in MerchantPrinterProtocol.values) {
    if (protocol.name.toLowerCase() == text) return protocol;
  }
  // Printers saved before protocol selection was introduced used ESC/POS.
  return MerchantPrinterProtocol.escPos;
}
