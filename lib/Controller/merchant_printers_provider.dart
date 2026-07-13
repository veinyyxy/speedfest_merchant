import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Common/printer/merchant_printer_platform.dart';
import '../Common/printer/merchant_printer_platform_interface.dart';
import '../Common/printer/merchant_receipt_renderer.dart';
import '../Models/merchant_buyer_config.dart';
import '../Models/merchant_order.dart';
import '../Models/merchant_printer.dart';

class MerchantPrintersProvider with ChangeNotifier {
  MerchantPrintersProvider({
    MerchantPrinterPlatform? platform,
    MerchantReceiptRenderer? renderer,
  }) : _platform = platform ?? createMerchantPrinterPlatform(),
       _renderer = renderer ?? const MerchantReceiptRenderer();

  static const _storageKey = 'merchant_saved_printers_v1';

  final MerchantPrinterPlatform _platform;
  final MerchantReceiptRenderer _renderer;

  bool _isLoading = false;
  bool _isScanningBluetooth = false;
  bool _isScanningNetwork = false;
  bool _isConnecting = false;
  bool _isPrinting = false;
  String? _errorMessage;
  List<MerchantPrinter> _printers = const [];
  List<MerchantDiscoveredPrinter> _bluetoothDiscoveries = const [];
  List<MerchantDiscoveredPrinter> _networkDiscoveries = const [];
  String _connectedPrinterId = '';

  bool get isLoading => _isLoading;
  bool get isScanningBluetooth => _isScanningBluetooth;
  bool get isScanningNetwork => _isScanningNetwork;
  bool get isConnecting => _isConnecting;
  bool get isPrinting => _isPrinting;
  bool get isBusy =>
      isLoading || isScanningBluetooth || isScanningNetwork || isConnecting;
  String? get errorMessage => _errorMessage;
  List<MerchantPrinter> get printers => _printers;
  List<MerchantDiscoveredPrinter> get bluetoothDiscoveries =>
      _bluetoothDiscoveries;
  List<MerchantDiscoveredPrinter> get networkDiscoveries => _networkDiscoveries;
  String get connectedPrinterId => _connectedPrinterId;
  bool get supportsBluetooth => _platform.supportsBluetooth;
  bool get supportsNetwork => _platform.supportsNetwork;
  bool get supportsBrowserPrint => _platform.supportsBrowserPrint;
  MerchantPrinter? get defaultPrinter {
    for (final printer in _printers) {
      if (printer.isDefault) return printer;
    }
    return _printers.isEmpty ? null : _printers.first;
  }

  Future<void> initialize() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      _printers = _decodePrinters(raw);
      _normalizeDefaultPrinter();
    } catch (err) {
      _errorMessage = 'Unable to load printers: $err';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> discoverBluetoothPrinters() async {
    _isScanningBluetooth = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _bluetoothDiscoveries = await _platform.discoverBluetoothPrinters();
    } catch (err) {
      _errorMessage = _messageFromError(err);
    } finally {
      _isScanningBluetooth = false;
      notifyListeners();
    }
  }

  Future<void> discoverNetworkPrinters({int port = 9100}) async {
    _isScanningNetwork = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _networkDiscoveries = await _platform.discoverNetworkPrinters(port: port);
    } catch (err) {
      _errorMessage = _messageFromError(err);
    } finally {
      _isScanningNetwork = false;
      notifyListeners();
    }
  }

  Future<bool> addNetworkPrinter({
    required String name,
    required String address,
    required int port,
    required MerchantPrinterPaperSize paperSize,
  }) async {
    final cleanAddress = address.trim();
    if (cleanAddress.isEmpty) {
      _setError('Enter a printer IP address.');
      return false;
    }
    if (port <= 0 || port > 65535) {
      _setError('Enter a valid printer port.');
      return false;
    }

    final printer = MerchantPrinter.network(
      id: _newPrinterId(),
      name: name.trim().isEmpty ? cleanAddress : name.trim(),
      address: cleanAddress,
      port: port,
      paperSize: paperSize,
      isDefault: _printers.isEmpty,
    );

    return _connectAndSave(printer);
  }

  Future<bool> addDiscoveredPrinter(
    MerchantDiscoveredPrinter discovered, {
    required MerchantPrinterPaperSize paperSize,
  }) {
    final printer = discovered.toPrinter(
      id: _newPrinterId(),
      paperSize: paperSize,
      isDefault: _printers.isEmpty,
    );
    return _connectAndSave(printer);
  }

  Future<bool> addBrowserPrinter() async {
    final printer = MerchantPrinter(
      id: _newPrinterId(),
      name: 'Browser print preview',
      connectionType: MerchantPrinterConnectionType.browser,
      address: 'browser',
      port: 0,
      paperSize: MerchantPrinterPaperSize.mm80,
      isDefault: _printers.isEmpty,
      lastConnectedAt: DateTime.now(),
    );
    final savedPrinter = _upsertPrinter(printer);
    _connectedPrinterId = savedPrinter.id;
    await _savePrinters();
    return true;
  }

  Future<bool> connectPrinter(MerchantPrinter printer) {
    return _connectAndSave(printer);
  }

  Future<bool> testPrinter(MerchantPrinter printer) async {
    _isPrinting = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final bytes = _renderer.renderTestTicket(printer);
      await _printBytesOrText(
        printer: printer,
        bytes: bytes,
        text: 'SpeedFeast printer test\n\nPrinter: ${printer.displayName}',
        title: 'SpeedFeast printer test',
      );
      _markConnected(printer.id);
      await _savePrinters();
      return true;
    } catch (err) {
      _errorMessage = _messageFromError(err);
      return false;
    } finally {
      _isPrinting = false;
      notifyListeners();
    }
  }

  Future<bool> printOrder({
    required MerchantOrder order,
    MerchantStoreProfileConfig? storeProfile,
    MerchantPrinter? printer,
  }) async {
    final target = printer ?? defaultPrinter;
    if (target == null) {
      _setError('Add a receipt printer before printing orders.');
      return false;
    }

    _isPrinting = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final bytes = _renderer.renderOrderTicket(
        order: order,
        paperSize: target.paperSize,
        storeProfile: storeProfile,
      );
      final text = _renderer.renderOrderText(
        order: order,
        paperSize: target.paperSize,
        storeProfile: storeProfile,
      );
      final html = _renderer.renderOrderHtml(
        order: order,
        paperSize: target.paperSize,
        storeProfile: storeProfile,
      );
      await _printBytesOrText(
        printer: target,
        bytes: bytes,
        text: text,
        html: html,
        title: order.displayId,
      );
      _markConnected(target.id);
      await _savePrinters();
      return true;
    } catch (err) {
      _errorMessage = _messageFromError(err);
      return false;
    } finally {
      _isPrinting = false;
      notifyListeners();
    }
  }

  Future<void> setDefaultPrinter(String printerId) async {
    _printers = _printers
        .map((printer) => printer.copyWith(isDefault: printer.id == printerId))
        .toList(growable: false);
    await _savePrinters();
    notifyListeners();
  }

  Future<void> removePrinter(String printerId) async {
    _printers = _printers
        .where((printer) => printer.id != printerId)
        .toList(growable: false);
    _normalizeDefaultPrinter();
    await _savePrinters();
    notifyListeners();
  }

  Future<bool> _connectAndSave(MerchantPrinter printer) async {
    _isConnecting = true;
    _errorMessage = null;
    notifyListeners();

    try {
      switch (printer.connectionType) {
        case MerchantPrinterConnectionType.bluetooth:
          await _platform.connectBluetoothPrinter(printer);
        case MerchantPrinterConnectionType.network:
          await _platform.probeNetworkPrinter(printer);
        case MerchantPrinterConnectionType.browser:
          if (!supportsBrowserPrint) {
            throw const MerchantPrinterException(
              'Browser print preview is not available on this platform.',
            );
          }
      }

      final savedPrinter = _upsertPrinter(
        printer.copyWith(lastConnectedAt: DateTime.now()),
      );
      _connectedPrinterId = savedPrinter.id;
      await _savePrinters();
      return true;
    } catch (err) {
      _errorMessage = _messageFromError(err);
      return false;
    } finally {
      _isConnecting = false;
      notifyListeners();
    }
  }

  Future<void> _printBytesOrText({
    required MerchantPrinter printer,
    required List<int> bytes,
    required String text,
    required String title,
    String? html,
  }) async {
    switch (printer.connectionType) {
      case MerchantPrinterConnectionType.bluetooth:
        await _platform.printBluetoothBytes(printer, bytes);
      case MerchantPrinterConnectionType.network:
        await _platform.printNetworkBytes(printer, bytes);
      case MerchantPrinterConnectionType.browser:
        await _platform.printBrowserText(title: title, text: text, html: html);
    }
  }

  MerchantPrinter _upsertPrinter(MerchantPrinter printer) {
    final next = [..._printers];
    final index = next.indexWhere(
      (item) =>
          item.connectionType == printer.connectionType &&
          item.address.toLowerCase() == printer.address.toLowerCase() &&
          item.port == printer.port,
    );

    final normalizedPrinter = printer.copyWith(
      isDefault: printer.isDefault || next.isEmpty,
    );
    if (index == -1) {
      next.add(normalizedPrinter);
      _printers = next;
      _normalizeDefaultPrinter();
      return normalizedPrinter;
    } else {
      final existing = next[index];
      next[index] = normalizedPrinter.copyWith(
        id: existing.id,
        isDefault: existing.isDefault || normalizedPrinter.isDefault,
      );
      _printers = next;
      _normalizeDefaultPrinter();
      return next[index];
    }
  }

  void _markConnected(String printerId) {
    final now = DateTime.now();
    _connectedPrinterId = printerId;
    _printers = _printers
        .map(
          (printer) => printer.id == printerId
              ? printer.copyWith(lastConnectedAt: now)
              : printer,
        )
        .toList(growable: false);
  }

  void _normalizeDefaultPrinter() {
    if (_printers.isEmpty) return;

    final defaultIndex = _printers.indexWhere((printer) => printer.isDefault);
    _printers = [
      for (var index = 0; index < _printers.length; index++)
        _printers[index].copyWith(
          isDefault: defaultIndex == -1 ? index == 0 : index == defaultIndex,
        ),
    ]..sort(_comparePrinters);
  }

  Future<void> _savePrinters() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      _printers.map((printer) => printer.toJson()).toList(growable: false),
    );
    await prefs.setString(_storageKey, encoded);
  }

  List<MerchantPrinter> _decodePrinters(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map(
          (item) => MerchantPrinter.fromJson(
            item.map<String, dynamic>(
              (key, value) => MapEntry(key.toString(), value),
            ),
          ),
        )
        .where((printer) => printer.id.isNotEmpty)
        .toList(growable: false);
  }

  void _setError(String message) {
    _errorMessage = message;
    notifyListeners();
  }

  String _newPrinterId() {
    return 'printer_${DateTime.now().microsecondsSinceEpoch}';
  }

  String _messageFromError(Object err) {
    if (err is MerchantPrinterException) return err.message;
    return err.toString();
  }
}

int _comparePrinters(MerchantPrinter left, MerchantPrinter right) {
  if (left.isDefault != right.isDefault) return left.isDefault ? -1 : 1;
  return left.displayName.toLowerCase().compareTo(
    right.displayName.toLowerCase(),
  );
}
