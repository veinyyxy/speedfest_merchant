import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../Controller/merchant_printers_provider.dart';
import '../Models/merchant_printer.dart';

class MerchantPrintersPage extends StatefulWidget {
  const MerchantPrintersPage({super.key});

  @override
  State<MerchantPrintersPage> createState() => _MerchantPrintersPageState();
}

class _MerchantPrintersPageState extends State<MerchantPrintersPage> {
  final _networkFormKey = GlobalKey<FormState>();
  final _printerNameController = TextEditingController();
  final _printerAddressController = TextEditingController();
  final _printerPortController = TextEditingController(text: '9100');
  MerchantPrinterPaperSize _paperSize = MerchantPrinterPaperSize.mm80;
  MerchantPrinterProtocol _protocol = MerchantPrinterProtocol.escPos;

  @override
  void dispose() {
    _printerNameController.dispose();
    _printerAddressController.dispose();
    _printerPortController.dispose();
    super.dispose();
  }

  Future<void> _addNetworkPrinter() async {
    final valid = _networkFormKey.currentState?.validate() ?? false;
    if (!valid) return;

    final provider = context.read<MerchantPrintersProvider>();
    final ok = await provider.addNetworkPrinter(
      name: _printerNameController.text,
      address: _printerAddressController.text,
      port: int.tryParse(_printerPortController.text.trim()) ?? 9100,
      paperSize: _paperSize,
      protocol: _protocol,
    );
    if (!mounted) return;

    _showMessage(
      ok
          ? 'Printer connected and saved.'
          : provider.errorMessage ?? 'Printer could not be connected.',
      success: ok,
    );
    if (ok) {
      _printerNameController.clear();
      _printerAddressController.clear();
      _printerPortController.text = '9100';
    }
  }

  Future<void> _addDiscoveredPrinter(MerchantDiscoveredPrinter printer) async {
    final provider = context.read<MerchantPrintersProvider>();
    final ok = await provider.addDiscoveredPrinter(
      printer,
      paperSize: _paperSize,
      protocol: _protocol,
    );
    if (!mounted) return;

    _showMessage(
      ok
          ? '${printer.displayName} connected and saved.'
          : provider.errorMessage ?? 'Printer could not be connected.',
      success: ok,
    );
  }

  Future<void> _connectPrinter(MerchantPrinter printer) async {
    final provider = context.read<MerchantPrintersProvider>();
    final ok = await provider.connectPrinter(printer);
    if (!mounted) return;
    _showMessage(
      ok
          ? '${printer.displayName} connected.'
          : provider.errorMessage ?? 'Printer could not be connected.',
      success: ok,
    );
  }

  Future<void> _testPrinter(MerchantPrinter printer) async {
    final provider = context.read<MerchantPrintersProvider>();
    final ok = await provider.testPrinter(printer);
    if (!mounted) return;
    _showMessage(
      ok
          ? 'Test receipt sent to ${printer.displayName}.'
          : provider.errorMessage ?? 'Test receipt could not be printed.',
      success: ok,
    );
  }

  Future<void> _addBrowserPrinter() async {
    final provider = context.read<MerchantPrintersProvider>();
    final ok = await provider.addBrowserPrinter();
    if (!mounted) return;
    _showMessage(
      ok
          ? 'Browser print preview added.'
          : provider.errorMessage ??
                'Browser print preview could not be added.',
      success: ok,
    );
  }

  Future<void> _setPrinterProtocol(
    MerchantPrinter printer,
    MerchantPrinterProtocol protocol,
  ) async {
    final provider = context.read<MerchantPrintersProvider>();
    await provider.setPrinterProtocol(printer.id, protocol);
    if (!mounted) return;
    _showMessage(
      '${printer.displayName} now uses ${_printerProtocolLabel(protocol)}. '
      'Connect or run a test print to verify it.',
    );
  }

  Future<void> _showReceiptTemplatePreview() async {
    final provider = context.read<MerchantPrintersProvider>();
    try {
      final image = await provider.renderReceiptTemplatePreview(_paperSize);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 760),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(provider.receiptTemplateName),
                  subtitle: Text('${_paperSizeLabel(_paperSize)} preview'),
                  trailing: IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: Container(
                    color: Colors.grey.shade300,
                    padding: const EdgeInsets.all(20),
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4,
                      child: Image.memory(image, fit: BoxFit.contain),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (err) {
      if (!mounted) return;
      _showMessage('Unable to preview receipt template: $err', success: false);
    }
  }

  void _showMessage(String message, {bool success = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: success ? null : Colors.red.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MerchantPrintersProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Printers')),
      body: RefreshIndicator(
        onRefresh: provider.initialize,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (provider.errorMessage != null) ...[
              _InlineError(message: provider.errorMessage!),
              const SizedBox(height: 12),
            ],
            _PaperSizeSelector(
              value: _paperSize,
              onChanged: (value) => setState(() => _paperSize = value),
            ),
            const SizedBox(height: 12),
            _ProtocolSelector(
              value: _protocol,
              supportsStarPrinting: provider.supportsStarPrinting,
              onChanged: (value) => setState(() => _protocol = value),
            ),
            const SizedBox(height: 12),
            _ReceiptTemplateCard(
              name: provider.receiptTemplateName,
              assetPath: provider.receiptTemplateAssetPath,
              usedFallback: provider.usedFallbackReceiptTemplate,
              onPreview: _showReceiptTemplatePreview,
            ),
            const SizedBox(height: 12),
            _SavedPrintersCard(
              provider: provider,
              onConnect: _connectPrinter,
              onTest: _testPrinter,
              onProtocolChanged: _setPrinterProtocol,
            ),
            const SizedBox(height: 12),
            _NetworkPrinterCard(
              formKey: _networkFormKey,
              nameController: _printerNameController,
              addressController: _printerAddressController,
              portController: _printerPortController,
              isBusy: provider.isBusy,
              supportsNetwork: provider.supportsNetwork,
              discoveries: provider.networkDiscoveries,
              isScanning: provider.isScanningNetwork,
              onAdd: _addNetworkPrinter,
              onScan: () => provider.discoverNetworkPrinters(
                port: int.tryParse(_printerPortController.text.trim()) ?? 9100,
              ),
              onAddDiscovered: _addDiscoveredPrinter,
            ),
            const SizedBox(height: 12),
            _BluetoothPrinterCard(
              supportsBluetooth: provider.supportsBluetooth,
              discoveries: provider.bluetoothDiscoveries,
              isScanning: provider.isScanningBluetooth,
              isBusy: provider.isBusy,
              onScan: provider.discoverBluetoothPrinters,
              onAddDiscovered: _addDiscoveredPrinter,
            ),
            if (provider.supportsBrowserPrint) ...[
              const SizedBox(height: 12),
              _BrowserPrinterCard(
                isBusy: provider.isBusy,
                onAdd: _addBrowserPrinter,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReceiptTemplateCard extends StatelessWidget {
  const _ReceiptTemplateCard({
    required this.name,
    required this.assetPath,
    required this.usedFallback,
    required this.onPreview,
  });

  final String name;
  final String assetPath;
  final bool usedFallback;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.description_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onPreview,
                  icon: const Icon(Icons.preview_outlined),
                  label: const Text('Preview'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(
              assetPath.isEmpty
                  ? 'Loading local receipt template...'
                  : assetPath,
              style: TextStyle(
                color: usedFallback
                    ? Colors.orange.shade800
                    : Colors.grey.shade700,
                fontSize: 12,
              ),
            ),
            if (usedFallback) ...[
              const SizedBox(height: 6),
              Text(
                'The primary JSON was invalid, so the local fallback template is active.',
                style: TextStyle(color: Colors.orange.shade800),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProtocolSelector extends StatelessWidget {
  const _ProtocolSelector({
    required this.value,
    required this.supportsStarPrinting,
    required this.onChanged,
  });

  final MerchantPrinterProtocol value;
  final bool supportsStarPrinting;
  final ValueChanged<MerchantPrinterProtocol> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Protocol for newly added printers',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<MerchantPrinterProtocol>(
              value: value,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Printer protocol',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(
                  value: MerchantPrinterProtocol.escPos,
                  child: Text(
                    'ESC/POS (generic receipt printers)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DropdownMenuItem(
                  value: MerchantPrinterProtocol.starPrnt,
                  enabled: supportsStarPrinting,
                  child: const Text(
                    'StarPRNT / Star Line (Star SDK)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              onChanged: (selected) {
                if (selected != null) onChanged(selected);
              },
            ),
            const SizedBox(height: 8),
            Text(
              supportsStarPrinting
                  ? 'Choose StarPRNT / Star Line for Star TSP graphics-only printers. The receipt is rasterized and sent through the Star SDK.'
                  : 'StarPRNT / Star Line printing is currently available in the Android app.',
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaperSizeSelector extends StatelessWidget {
  const _PaperSizeSelector({required this.value, required this.onChanged});

  final MerchantPrinterPaperSize value;
  final ValueChanged<MerchantPrinterPaperSize> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Default paper size for newly added printers',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 12),
            SegmentedButton<MerchantPrinterPaperSize>(
              segments: const [
                ButtonSegment(
                  value: MerchantPrinterPaperSize.mm58,
                  label: Text('58 mm'),
                ),
                ButtonSegment(
                  value: MerchantPrinterPaperSize.mm80,
                  label: Text('80 mm'),
                ),
              ],
              selected: {value},
              onSelectionChanged: (selected) => onChanged(selected.first),
            ),
          ],
        ),
      ),
    );
  }
}

class _SavedPrintersCard extends StatelessWidget {
  const _SavedPrintersCard({
    required this.provider,
    required this.onConnect,
    required this.onTest,
    required this.onProtocolChanged,
  });

  final MerchantPrintersProvider provider;
  final ValueChanged<MerchantPrinter> onConnect;
  final ValueChanged<MerchantPrinter> onTest;
  final void Function(MerchantPrinter printer, MerchantPrinterProtocol protocol)
  onProtocolChanged;

  @override
  Widget build(BuildContext context) {
    final printers = provider.printers;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Saved Printers',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (provider.isLoading)
              const LinearProgressIndicator()
            else if (printers.isEmpty)
              Text(
                'No printers saved yet. Add an IP printer or connect a Bluetooth printer.',
                style: TextStyle(color: Colors.grey.shade700),
              )
            else
              ...printers.map(
                (printer) => _PrinterTile(
                  printer: printer,
                  isConnected: printer.id == provider.connectedPrinterId,
                  isBusy: provider.isBusy || provider.isPrinting,
                  supportsStarPrinting: provider.supportsStarPrinting,
                  onConnect: () => onConnect(printer),
                  onTest: () => onTest(printer),
                  onSetDefault: () => provider.setDefaultPrinter(printer.id),
                  onUseEscPos: () => onProtocolChanged(
                    printer,
                    MerchantPrinterProtocol.escPos,
                  ),
                  onUseStarPrnt: () => onProtocolChanged(
                    printer,
                    MerchantPrinterProtocol.starPrnt,
                  ),
                  onRemove: () => provider.removePrinter(printer.id),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PrinterTile extends StatelessWidget {
  const _PrinterTile({
    required this.printer,
    required this.isConnected,
    required this.isBusy,
    required this.supportsStarPrinting,
    required this.onConnect,
    required this.onTest,
    required this.onSetDefault,
    required this.onUseEscPos,
    required this.onUseStarPrnt,
    required this.onRemove,
  });

  final MerchantPrinter printer;
  final bool isConnected;
  final bool isBusy;
  final bool supportsStarPrinting;
  final VoidCallback onConnect;
  final VoidCallback onTest;
  final VoidCallback onSetDefault;
  final VoidCallback onUseEscPos;
  final VoidCallback onUseStarPrnt;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: printer.isDefault
            ? Theme.of(context).colorScheme.primary.withAlpha(28)
            : Colors.grey.shade100,
        child: Icon(
          printer.isNetwork
              ? Icons.router_outlined
              : printer.isBluetooth
              ? Icons.bluetooth
              : Icons.print_outlined,
          color: printer.isDefault
              ? Theme.of(context).colorScheme.primary
              : Colors.grey.shade700,
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              printer.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (printer.isDefault)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withAlpha(28),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Default',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          if (isConnected) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.green.withAlpha(28),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Connected',
                style: TextStyle(
                  color: Colors.green.shade700,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(
          [
            printer.connectionLabel,
            printer.targetLabel,
            printer.paperSizeLabel,
            printer.protocolLabel,
            if (printer.lastConnectedAt != null)
              'Last connected ${_formatDateTime(printer.lastConnectedAt!)}',
          ].join(' · '),
        ),
      ),
      trailing: PopupMenuButton<_PrinterAction>(
        enabled: !isBusy,
        tooltip: 'Printer actions',
        onSelected: (action) {
          switch (action) {
            case _PrinterAction.connect:
              onConnect();
            case _PrinterAction.test:
              onTest();
            case _PrinterAction.setDefault:
              onSetDefault();
            case _PrinterAction.useEscPos:
              onUseEscPos();
            case _PrinterAction.useStarPrnt:
              onUseStarPrnt();
            case _PrinterAction.remove:
              onRemove();
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: _PrinterAction.connect,
            child: Text('Connect'),
          ),
          const PopupMenuItem(
            value: _PrinterAction.test,
            child: Text('Test print'),
          ),
          if (!printer.isDefault)
            const PopupMenuItem(
              value: _PrinterAction.setDefault,
              child: Text('Set default'),
            ),
          if (printer.connectionType != MerchantPrinterConnectionType.browser &&
              printer.protocol != MerchantPrinterProtocol.escPos)
            const PopupMenuItem(
              value: _PrinterAction.useEscPos,
              child: Text('Use ESC/POS'),
            ),
          if (printer.connectionType != MerchantPrinterConnectionType.browser &&
              supportsStarPrinting &&
              printer.protocol != MerchantPrinterProtocol.starPrnt)
            const PopupMenuItem(
              value: _PrinterAction.useStarPrnt,
              child: Text('Use StarPRNT / Star Line'),
            ),
          const PopupMenuItem(
            value: _PrinterAction.remove,
            child: Text('Remove'),
          ),
        ],
      ),
    );
  }
}

enum _PrinterAction {
  connect,
  test,
  setDefault,
  useEscPos,
  useStarPrnt,
  remove,
}

class _NetworkPrinterCard extends StatelessWidget {
  const _NetworkPrinterCard({
    required this.formKey,
    required this.nameController,
    required this.addressController,
    required this.portController,
    required this.isBusy,
    required this.supportsNetwork,
    required this.discoveries,
    required this.isScanning,
    required this.onAdd,
    required this.onScan,
    required this.onAddDiscovered,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final TextEditingController addressController;
  final TextEditingController portController;
  final bool isBusy;
  final bool supportsNetwork;
  final List<MerchantDiscoveredPrinter> discoveries;
  final bool isScanning;
  final VoidCallback onAdd;
  final VoidCallback onScan;
  final ValueChanged<MerchantDiscoveredPrinter> onAddDiscovered;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'IP Printer',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                supportsNetwork
                    ? 'Most ESC/POS network printers use port 9100.'
                    : 'Direct IP printing is not available on this platform.',
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: nameController,
                enabled: supportsNetwork && !isBusy,
                decoration: const InputDecoration(
                  labelText: 'Printer name',
                  hintText: 'Kitchen printer',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              _ResponsivePair(
                first: TextFormField(
                  controller: addressController,
                  enabled: supportsNetwork && !isBusy,
                  decoration: const InputDecoration(
                    labelText: 'IP address',
                    hintText: '192.168.100.50',
                    border: OutlineInputBorder(),
                  ),
                  validator: _requiredValidator,
                ),
                second: TextFormField(
                  controller: portController,
                  enabled: supportsNetwork && !isBusy,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Port',
                    border: OutlineInputBorder(),
                  ),
                  validator: _portValidator,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: supportsNetwork && !isBusy ? onAdd : null,
                    icon: const Icon(Icons.add_link_outlined),
                    label: const Text('Connect and save'),
                  ),
                  OutlinedButton.icon(
                    onPressed: supportsNetwork && !isBusy ? onScan : null,
                    icon: isScanning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.radar_outlined),
                    label: Text(isScanning ? 'Scanning' : 'Scan network'),
                  ),
                ],
              ),
              if (discoveries.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Divider(),
                for (final printer in discoveries)
                  _DiscoveryTile(
                    printer: printer,
                    isBusy: isBusy,
                    onAdd: () => onAddDiscovered(printer),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BluetoothPrinterCard extends StatelessWidget {
  const _BluetoothPrinterCard({
    required this.supportsBluetooth,
    required this.discoveries,
    required this.isScanning,
    required this.isBusy,
    required this.onScan,
    required this.onAddDiscovered,
  });

  final bool supportsBluetooth;
  final List<MerchantDiscoveredPrinter> discoveries;
  final bool isScanning;
  final bool isBusy;
  final VoidCallback onScan;
  final ValueChanged<MerchantDiscoveredPrinter> onAddDiscovered;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bluetooth Printer',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              supportsBluetooth
                  ? 'Keep the printer on and discoverable, then scan for nearby or paired devices.'
                  : 'Bluetooth receipt printing is not available on this platform.',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: supportsBluetooth && !isBusy ? onScan : null,
              icon: isScanning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.bluetooth_searching),
              label: Text(isScanning ? 'Scanning' : 'Find Bluetooth printers'),
            ),
            if (discoveries.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(),
              for (final printer in discoveries)
                _DiscoveryTile(
                  printer: printer,
                  isBusy: isBusy,
                  onAdd: () => onAddDiscovered(printer),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BrowserPrinterCard extends StatelessWidget {
  const _BrowserPrinterCard({required this.isBusy, required this.onAdd});

  final bool isBusy;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Browser Print Preview',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Use the browser print dialog when direct receipt-printer access is not available.',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: isBusy ? null : onAdd,
              icon: const Icon(Icons.open_in_browser_outlined),
              label: const Text('Add browser preview'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiscoveryTile extends StatelessWidget {
  const _DiscoveryTile({
    required this.printer,
    required this.isBusy,
    required this.onAdd,
  });

  final MerchantDiscoveredPrinter printer;
  final bool isBusy;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        printer.connectionType == MerchantPrinterConnectionType.bluetooth
            ? Icons.bluetooth
            : Icons.router_outlined,
      ),
      title: Text(printer.displayName),
      subtitle: Text(printer.targetLabel),
      trailing: FilledButton(
        onPressed: isBusy ? null : onAdd,
        child: const Text('Connect'),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade700),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: Colors.red.shade800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResponsivePair extends StatelessWidget {
  const _ResponsivePair({required this.first, required this.second});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(children: [first, const SizedBox(height: 12), second]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: 12),
            SizedBox(width: 140, child: second),
          ],
        );
      },
    );
  }
}

String? _requiredValidator(String? value) {
  return (value?.trim().isEmpty ?? true) ? 'Required' : null;
}

String? _portValidator(String? value) {
  final parsed = int.tryParse(value?.trim() ?? '');
  if (parsed == null) return 'Enter a port';
  if (parsed <= 0 || parsed > 65535) return 'Invalid port';
  return null;
}

String _formatDateTime(DateTime date) {
  final local = date.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}-$month-$day $hour:$minute';
}

String _printerProtocolLabel(MerchantPrinterProtocol protocol) {
  return switch (protocol) {
    MerchantPrinterProtocol.escPos => 'ESC/POS',
    MerchantPrinterProtocol.starPrnt => 'StarPRNT / Star Line',
  };
}

String _paperSizeLabel(MerchantPrinterPaperSize paperSize) {
  return switch (paperSize) {
    MerchantPrinterPaperSize.mm58 => '58 mm',
    MerchantPrinterPaperSize.mm80 => '80 mm',
  };
}
