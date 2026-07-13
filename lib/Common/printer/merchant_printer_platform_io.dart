import 'dart:async';
import 'dart:io';

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
  Future<List<MerchantDiscoveredPrinter>> discoverBluetoothPrinters() async {
    _ensureBluetoothPlatform();
    await _ensureBluetoothPermission();

    final enabled = await PrintBluetoothThermal.bluetoothEnabled;
    if (!enabled) {
      throw const MerchantPrinterException('Bluetooth is turned off.');
    }

    final printers = await PrintBluetoothThermal.pairedBluetooths;
    return printers
        .map(
          (printer) => MerchantDiscoveredPrinter(
            name: printer.name,
            connectionType: MerchantPrinterConnectionType.bluetooth,
            address: printer.macAdress,
            port: 0,
          ),
        )
        .toList(growable: false);
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

  void _ensureBluetoothPlatform() {
    if (!supportsBluetooth) {
      throw const MerchantPrinterException(
        'Bluetooth printing is not available on this platform.',
      );
    }
  }

  Future<void> _ensureBluetoothPermission() async {
    if (Platform.isAndroid) {
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
