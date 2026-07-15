import 'dart:async';
import 'dart:io';

import 'package:flutter_classic_bluetooth/flutter_classic_bluetooth.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../../Models/merchant_printer.dart';
import 'merchant_printer_platform_interface.dart';

MerchantPrinterPlatform createMerchantPrinterPlatform() {
  return const _IoPrinterPlatform();
}

class _IoPrinterPlatform implements MerchantPrinterPlatform {
  const _IoPrinterPlatform();

  static const _networkConnectTimeout = Duration(milliseconds: 450);
  static const _networkPrintTimeout = Duration(seconds: 6);
  static const _bluetoothConnectTimeout = Duration(seconds: 15);
  static const _bluetoothScanTimeout = Duration(seconds: 8);
  static final _classicBluetooth = FlutterClassicBluetooth();
  static const _starPrinterChannel = MethodChannel(
    'speedfeast_merchant/star_printer',
  );
  static BtcConnection? _androidClassicConnection;

  @override
  bool get supportsBluetooth =>
      Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isMacOS ||
      Platform.isWindows;

  @override
  bool get supportsBrowserPrint => false;

  @override
  bool get supportsNetwork => true;

  @override
  bool get supportsStarPrinting => Platform.isAndroid;

  @override
  Future<List<MerchantDiscoveredPrinter>> discoverBluetoothPrinters() async {
    _ensureBluetoothPlatform();
    await _ensureBluetoothPermission();

    final enabled = await PrintBluetoothThermal.bluetoothEnabled;
    if (!enabled) {
      throw const MerchantPrinterException('Bluetooth is turned off.');
    }

    if (Platform.isAndroid) {
      return _discoverAndroidBluetoothPrinters();
    }

    final printers = await PrintBluetoothThermal.pairedBluetooths;
    return printers.map(_thermalPrinterDiscovery).toList(growable: false);
  }

  @override
  Future<List<MerchantDiscoveredPrinter>> discoverNetworkPrinters({
    int port = 9100,
  }) async {
    final hosts = await _localSubnetHosts();
    if (hosts.isEmpty) {
      throw const MerchantPrinterException(
        'No local IPv4 network was found for printer discovery.',
      );
    }

    final results = <MerchantDiscoveredPrinter>[];
    var nextIndex = 0;

    Future<void> worker() async {
      while (nextIndex < hosts.length) {
        final host = hosts[nextIndex++];
        final connected = await _canConnect(host, port, _networkConnectTimeout);
        if (connected) {
          results.add(
            MerchantDiscoveredPrinter(
              name: 'Network printer',
              connectionType: MerchantPrinterConnectionType.network,
              address: host,
              port: port,
            ),
          );
        }
      }
    }

    final workerCount = hosts.length < 32 ? hosts.length : 32;
    await Future.wait(List.generate(workerCount, (_) => worker()));
    results.sort((left, right) => left.address.compareTo(right.address));
    return results;
  }

  @override
  Future<void> connectBluetoothPrinter(MerchantPrinter printer) async {
    _ensureBluetoothPlatform();
    await _ensureBluetoothPermission();
    final address = printer.address.trim();
    if (address.isEmpty) {
      throw const MerchantPrinterException(
        'Bluetooth printer address is empty.',
      );
    }

    if (Platform.isAndroid && !await _isPairedClassicDevice(address)) {
      await _pairAndroidClassicDevice(address);
    }

    if (Platform.isAndroid) {
      await _connectAndroidClassicPrinter(address);
      return;
    }

    final connected = await PrintBluetoothThermal.connect(
      macPrinterAddress: address,
    ).timeout(_bluetoothConnectTimeout);
    if (!connected) {
      throw MerchantPrinterException(
        'Could not connect to ${printer.displayName}.',
      );
    }
  }

  @override
  Future<void> connectStarPrinter(MerchantPrinter printer) async {
    _ensureStarPrinterPlatform();
    if (printer.isBluetooth) {
      await _ensureBluetoothPermission();
      if (!await _isPairedClassicDevice(printer.address)) {
        await _pairAndroidClassicDevice(printer.address);
      }
      await _closeAndroidClassicConnection();
    }

    await _invokeStarPrinterMethod('probe', _starPrinterArguments(printer));
  }

  @override
  Future<void> probeNetworkPrinter(MerchantPrinter printer) async {
    if (!printer.isNetwork) {
      throw const MerchantPrinterException('This is not a network printer.');
    }
    final connected = await _canConnect(
      printer.address,
      printer.port,
      _networkPrintTimeout,
    );
    if (!connected) {
      throw MerchantPrinterException(
        'Could not connect to ${printer.targetLabel}.',
      );
    }
  }

  @override
  Future<void> printBluetoothBytes(
    MerchantPrinter printer,
    List<int> bytes,
  ) async {
    _ensureBluetoothPlatform();
    await _ensureBluetoothPermission();

    if (Platform.isAndroid) {
      var connection = _androidClassicConnection;
      if (connection == null ||
          !connection.isConnected ||
          connection.address.toLowerCase() != printer.address.toLowerCase()) {
        await connectBluetoothPrinter(printer);
        connection = _androidClassicConnection;
      }
      if (connection == null || !connection.isConnected) {
        throw MerchantPrinterException(
          'Could not connect to ${printer.displayName}.',
        );
      }

      try {
        await connection.output.writeBytes(bytes);
        await connection.output.allSent;
      } catch (err) {
        await _closeAndroidClassicConnection();
        throw MerchantPrinterException(
          'Could not send print data to ${printer.displayName}: $err',
        );
      }
      return;
    }

    var connected = await PrintBluetoothThermal.connectionStatus;
    if (!connected) {
      await connectBluetoothPrinter(printer);
      connected = await PrintBluetoothThermal.connectionStatus;
    }
    if (!connected) {
      throw MerchantPrinterException(
        'Could not connect to ${printer.displayName}.',
      );
    }

    final success = await PrintBluetoothThermal.writeBytes(bytes);
    if (!success) {
      throw MerchantPrinterException(
        'Print command was rejected by ${printer.displayName}.',
      );
    }
  }

  @override
  Future<void> printBrowserText({
    required String title,
    required String text,
    String? html,
  }) {
    throw const MerchantPrinterException(
      'Browser print preview is only available on web.',
    );
  }

  @override
  Future<void> printNetworkBytes(
    MerchantPrinter printer,
    List<int> bytes,
  ) async {
    if (!printer.isNetwork) {
      throw const MerchantPrinterException('This is not a network printer.');
    }

    Socket? socket;
    try {
      socket = await Socket.connect(
        printer.address,
        printer.port,
        timeout: _networkPrintTimeout,
      );
      socket.add(bytes);
      await socket.flush().timeout(_networkPrintTimeout);
      await socket.close().timeout(_networkPrintTimeout);
    } on SocketException catch (err) {
      throw MerchantPrinterException(
        'Could not reach ${printer.targetLabel}: ${err.message}',
      );
    } on TimeoutException {
      throw MerchantPrinterException(
        'Timed out while printing to ${printer.targetLabel}.',
      );
    } finally {
      socket?.destroy();
    }
  }

  @override
  Future<void> printStarImage(
    MerchantPrinter printer,
    Uint8List imageBytes, {
    required int paperWidthDots,
    required int feedLines,
    required String cutMode,
  }) async {
    _ensureStarPrinterPlatform();
    if (printer.isBluetooth) {
      await _ensureBluetoothPermission();
      if (!await _isPairedClassicDevice(printer.address)) {
        await _pairAndroidClassicDevice(printer.address);
      }
      await _closeAndroidClassicConnection();
    }
    if (!printer.isBluetooth && !printer.isNetwork) {
      throw const MerchantPrinterException(
        'Star printing requires a Bluetooth or IP printer.',
      );
    }

    if (imageBytes.isEmpty) {
      throw const MerchantPrinterException('Star receipt image is empty.');
    }

    await _invokeStarPrinterMethod('printImage', {
      ..._starPrinterArguments(printer),
      'imageBytes': imageBytes,
      'paperWidthDots': paperWidthDots,
      'feedLines': feedLines,
      'cutMode': cutMode,
    });
  }

  Map<String, Object> _starPrinterArguments(MerchantPrinter printer) {
    return {
      'interface': printer.isBluetooth ? 'bluetooth' : 'lan',
      'identifier': printer.address.trim(),
    };
  }

  Future<void> _invokeStarPrinterMethod(
    String method,
    Map<String, Object> arguments,
  ) async {
    try {
      await _starPrinterChannel.invokeMethod<void>(method, arguments);
    } on PlatformException catch (err) {
      final message = err.message?.trim();
      throw MerchantPrinterException(
        message?.isNotEmpty == true
            ? message!
            : 'Star printer operation failed (${err.code}).',
      );
    } on MissingPluginException {
      throw const MerchantPrinterException(
        'Star printer support is not installed in this app build.',
      );
    }
  }

  void _ensureBluetoothPlatform() {
    if (!supportsBluetooth) {
      throw const MerchantPrinterException(
        'Bluetooth printing is not available on this platform.',
      );
    }
  }

  void _ensureStarPrinterPlatform() {
    if (!supportsStarPrinting) {
      throw const MerchantPrinterException(
        'StarPRNT / Star Line printing is currently available on Android.',
      );
    }
  }

  Future<void> _ensureBluetoothPermission() async {
    if (Platform.isAndroid) {
      // Android 11 and earlier require location permission for classic
      // Bluetooth discovery. On newer Android versions this is a no-op because
      // ACCESS_FINE_LOCATION is capped at API 30 in the manifest.
      await Permission.locationWhenInUse.request();
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ].request();
      final denied = statuses.values.any((status) => !status.isGranted);
      if (denied) {
        throw const MerchantPrinterException(
          'Bluetooth permission is required to use a receipt printer.',
        );
      }
      return;
    }

    if (Platform.isIOS || Platform.isMacOS) {
      final status = await Permission.bluetooth.request();
      if (!status.isGranted && !status.isLimited) {
        throw const MerchantPrinterException(
          'Bluetooth permission is required to use a receipt printer.',
        );
      }
    }
  }

  Future<List<MerchantDiscoveredPrinter>>
  _discoverAndroidBluetoothPrinters() async {
    final discoveries = <String, MerchantDiscoveredPrinter>{};

    try {
      final pairedPrinters = await PrintBluetoothThermal.pairedBluetooths;
      for (final printer in pairedPrinters) {
        final discovered = _thermalPrinterDiscovery(printer);
        discoveries[discovered.address.toLowerCase()] = discovered;
      }
    } catch (err) {
      throw MerchantPrinterException(
        'Could not read paired Bluetooth devices: $err',
      );
    }

    try {
      final nearby = await _classicBluetooth.scan(
        timeout: _bluetoothScanTimeout,
      );
      for (final device in nearby) {
        final address = device.address.trim();
        if (address.isEmpty) continue;
        discoveries.putIfAbsent(
          address.toLowerCase(),
          () => MerchantDiscoveredPrinter(
            name: device.displayName,
            connectionType: MerchantPrinterConnectionType.bluetooth,
            address: address,
            port: 0,
          ),
        );
      }
    } catch (err) {
      throw MerchantPrinterException(
        'Could not scan nearby Bluetooth devices: $err',
      );
    }

    final result = discoveries.values.toList();
    result.sort(
      (left, right) => left.displayName.toLowerCase().compareTo(
        right.displayName.toLowerCase(),
      ),
    );
    return result;
  }

  MerchantDiscoveredPrinter _thermalPrinterDiscovery(BluetoothInfo printer) {
    return MerchantDiscoveredPrinter(
      name: printer.name,
      connectionType: MerchantPrinterConnectionType.bluetooth,
      address: printer.macAdress,
      port: 0,
    );
  }

  Future<bool> _isPairedClassicDevice(String address) async {
    if (!Platform.isAndroid) return false;
    try {
      final paired = await _classicBluetooth.getPairedDevices();
      final normalizedAddress = address.trim().toLowerCase();
      return paired.any(
        (device) => device.address.trim().toLowerCase() == normalizedAddress,
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> _pairAndroidClassicDevice(String address) async {
    try {
      final paired = await _classicBluetooth
          .bondDevice(address)
          .timeout(const Duration(seconds: 30));
      if (!paired) {
        throw const MerchantPrinterException(
          'Pairing was not completed. Accept the Bluetooth pairing prompt and try again.',
        );
      }
    } on MerchantPrinterException {
      rethrow;
    } catch (err) {
      throw MerchantPrinterException(
        'Could not pair with the Bluetooth printer: $err',
      );
    }
  }

  Future<void> _connectAndroidClassicPrinter(String address) async {
    final existing = _androidClassicConnection;
    if (existing != null &&
        existing.isConnected &&
        existing.address.toLowerCase() == address.toLowerCase()) {
      return;
    }
    await _closeAndroidClassicConnection();

    Object? secureError;
    try {
      _androidClassicConnection = await _classicBluetooth.connect(
        address: address,
        secure: true,
        timeout: _bluetoothConnectTimeout,
      );
      return;
    } catch (err) {
      secureError = err;
    }

    try {
      _androidClassicConnection = await _classicBluetooth.connect(
        address: address,
        secure: false,
        timeout: _bluetoothConnectTimeout,
      );
    } catch (err) {
      throw MerchantPrinterException(
        'Could not open the printer SPP connection. '
        'Secure connection failed: $secureError; '
        'insecure connection failed: $err',
      );
    }
  }

  Future<void> _closeAndroidClassicConnection() async {
    final connection = _androidClassicConnection;
    _androidClassicConnection = null;
    if (connection == null) return;
    try {
      await connection.close();
    } catch (_) {
      // The printer may already have closed the RFCOMM socket.
    } finally {
      connection.dispose();
    }
  }

  Future<List<String>> _localSubnetHosts() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    final prefixes = <String>{};
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        final host = address.address;
        final parts = host.split('.');
        if (parts.length != 4 || host.startsWith('169.254.')) continue;
        prefixes.add('${parts[0]}.${parts[1]}.${parts[2]}');
      }
    }

    return [
      for (final prefix in prefixes)
        for (var index = 1; index <= 254; index++) '$prefix.$index',
    ];
  }

  Future<bool> _canConnect(String host, int port, Duration timeout) async {
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      return true;
    } catch (_) {
      return false;
    } finally {
      socket?.destroy();
    }
  }
}
