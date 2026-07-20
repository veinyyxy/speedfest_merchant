import 'dart:ui' as ui;

import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../Common/dine_in_table_qr_document.dart';
import '../Common/merchant_permissions.dart';
import '../Controller/merchant_dining_tables_provider.dart';
import '../Controller/merchant_session_provider.dart';
import '../Models/merchant_dining_table.dart';

enum _TableVisibility { all, active, inactive }

enum _AddTableMode { single, range }

enum _TableAction { edit, toggleActive, rotateToken }

class MerchantDiningTablesPage extends StatefulWidget {
  const MerchantDiningTablesPage({super.key});

  @override
  State<MerchantDiningTablesPage> createState() =>
      _MerchantDiningTablesPageState();
}

class _MerchantDiningTablesPageState extends State<MerchantDiningTablesPage> {
  _TableVisibility _visibility = _TableVisibility.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetch());
  }

  Future<void> _fetch() async {
    final session = context.read<MerchantSessionProvider>();
    final token = session.token;
    if (token == null) return;
    await context.read<MerchantDiningTablesProvider>().fetchTables(
      apiClient: session.apiClient,
      token: token,
    );
  }

  Future<void> _openAddMenu() async {
    final mode = await showModalBottomSheet<_AddTableMode>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.table_restaurant_outlined),
              title: const Text('Add one table'),
              onTap: () => Navigator.of(sheetContext).pop(_AddTableMode.single),
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add_outlined),
              title: const Text('Add a table range'),
              onTap: () => Navigator.of(sheetContext).pop(_AddTableMode.range),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || mode == null) return;
    if (mode == _AddTableMode.single) {
      await _createSingleTable();
    } else {
      await _createTableRange();
    }
  }

  Future<void> _createSingleTable() async {
    final tableNumber = await showDialog<String>(
      context: context,
      builder: (_) => const _SingleTableDialog(),
    );
    if (!mounted || tableNumber == null) return;

    final session = context.read<MerchantSessionProvider>();
    final token = session.token;
    if (token == null) return;
    final provider = context.read<MerchantDiningTablesProvider>();
    final ok = await provider.createTable(
      apiClient: session.apiClient,
      token: token,
      tableNumber: tableNumber,
    );
    if (!mounted) return;
    _showResult(ok, success: '$tableNumber created.');
  }

  Future<void> _createTableRange() async {
    final tableNumbers = await showDialog<List<String>>(
      context: context,
      builder: (_) => const _TableRangeDialog(),
    );
    if (!mounted || tableNumbers == null) return;

    final session = context.read<MerchantSessionProvider>();
    final token = session.token;
    if (token == null) return;
    final provider = context.read<MerchantDiningTablesProvider>();
    final createdCount = await provider.createTables(
      apiClient: session.apiClient,
      token: token,
      tableNumbers: tableNumbers,
    );
    if (!mounted) return;
    _showResult(createdCount != null, success: '$createdCount tables created.');
  }

  Future<void> _editTable(MerchantDiningTable table) async {
    final input = await showDialog<_TableEditInput>(
      context: context,
      builder: (_) => _EditTableDialog(table: table),
    );
    if (!mounted || input == null) return;
    final session = context.read<MerchantSessionProvider>();
    final token = session.token;
    if (token == null) return;
    final provider = context.read<MerchantDiningTablesProvider>();
    final ok = await provider.updateTable(
      apiClient: session.apiClient,
      token: token,
      tableId: table.id,
      tableNumber: input.tableNumber,
      isActive: input.isActive,
    );
    if (!mounted) return;
    _showResult(ok, success: '${input.tableNumber} updated.');
  }

  Future<void> _toggleTable(MerchantDiningTable table) async {
    final nextActive = !table.isActive;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(nextActive ? 'Enable table?' : 'Disable table?'),
        content: Text(
          nextActive
              ? '${table.tableNumber} will accept new scans and orders.'
              : '${table.tableNumber} QR code will stop accepting new scans. Existing orders are unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(nextActive ? 'Enable' : 'Disable'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    final session = context.read<MerchantSessionProvider>();
    final token = session.token;
    if (token == null) return;
    final provider = context.read<MerchantDiningTablesProvider>();
    final ok = await provider.updateTable(
      apiClient: session.apiClient,
      token: token,
      tableId: table.id,
      isActive: nextActive,
    );
    if (!mounted) return;
    _showResult(
      ok,
      success: '${table.tableNumber} ${nextActive ? 'enabled' : 'disabled'}.',
    );
  }

  Future<void> _rotateToken(MerchantDiningTable table) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Generate a new QR code?'),
        content: Text(
          'The QR code currently printed for ${table.tableNumber} will stop working immediately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Generate new code'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    final session = context.read<MerchantSessionProvider>();
    final token = session.token;
    if (token == null) return;
    final provider = context.read<MerchantDiningTablesProvider>();
    final ok = await provider.rotateToken(
      apiClient: session.apiClient,
      token: token,
      tableId: table.id,
    );
    if (!mounted) return;
    _showResult(
      ok,
      success: 'A new QR code was generated for ${table.tableNumber}.',
    );
  }

  void _showResult(bool ok, {required String success}) {
    final provider = context.read<MerchantDiningTablesProvider>();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? success : provider.errorMessage ?? 'Unable to save table.',
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: ok ? null : Colors.red.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MerchantDiningTablesProvider>();
    final session = context.watch<MerchantSessionProvider>();
    final canManage = session.can(MerchantPermissions.tablesManage);
    final tables = provider.tables
        .where((table) {
          return switch (_visibility) {
            _TableVisibility.all => true,
            _TableVisibility.active => table.isActive,
            _TableVisibility.inactive => !table.isActive,
          };
        })
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dine-in Tables'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: provider.isLoading ? null : _fetch,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          _TableFilterBar(
            selected: _visibility,
            allCount: provider.tables.length,
            activeCount: provider.tables.where((item) => item.isActive).length,
            inactiveCount: provider.tables
                .where((item) => !item.isActive)
                .length,
            onSelected: (value) => setState(() => _visibility = value),
          ),
          if (provider.isLoading) const LinearProgressIndicator(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _fetch,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  if (provider.errorMessage != null && provider.tables.isEmpty)
                    _ErrorPanel(
                      message: provider.errorMessage!,
                      onRetry: _fetch,
                    )
                  else if (!provider.isLoading && tables.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 72),
                      child: Center(child: Text('No tables in this view.')),
                    )
                  else
                    for (final table in tables) ...[
                      _DiningTableCard(
                        table: table,
                        canManage: canManage,
                        isSaving: provider.isSaving,
                        onPreview: () => showDialog<void>(
                          context: context,
                          builder: (_) => _TableQrDialog(table: table),
                        ),
                        onAction: (action) {
                          switch (action) {
                            case _TableAction.edit:
                              _editTable(table);
                              break;
                            case _TableAction.toggleActive:
                              _toggleTable(table);
                              break;
                            case _TableAction.rotateToken:
                              _rotateToken(table);
                              break;
                          }
                        },
                      ),
                      const SizedBox(height: 10),
                    ],
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: provider.isSaving ? null : _openAddMenu,
              icon: const Icon(Icons.add),
              label: const Text('Add tables'),
            )
          : null,
    );
  }
}

class _TableFilterBar extends StatelessWidget {
  const _TableFilterBar({
    required this.selected,
    required this.allCount,
    required this.activeCount,
    required this.inactiveCount,
    required this.onSelected,
  });

  final _TableVisibility selected;
  final int allCount;
  final int activeCount;
  final int inactiveCount;
  final ValueChanged<_TableVisibility> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        scrollDirection: Axis.horizontal,
        children: [
          ChoiceChip(
            label: Text('All $allCount'),
            selected: selected == _TableVisibility.all,
            onSelected: (_) => onSelected(_TableVisibility.all),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: Text('Active $activeCount'),
            selected: selected == _TableVisibility.active,
            onSelected: (_) => onSelected(_TableVisibility.active),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: Text('Inactive $inactiveCount'),
            selected: selected == _TableVisibility.inactive,
            onSelected: (_) => onSelected(_TableVisibility.inactive),
          ),
        ],
      ),
    );
  }
}

class _DiningTableCard extends StatelessWidget {
  const _DiningTableCard({
    required this.table,
    required this.canManage,
    required this.isSaving,
    required this.onPreview,
    required this.onAction,
  });

  final MerchantDiningTable table;
  final bool canManage;
  final bool isSaving;
  final VoidCallback onPreview;
  final ValueChanged<_TableAction> onAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            InkWell(
              onTap: onPreview,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: 82,
                height: 82,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: QrImageView(
                  data: table.effectiveQrPayload,
                  version: QrVersions.auto,
                  gapless: true,
                  semanticsLabel: '${table.tableNumber} QR code',
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    table.tableNumber,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _StatusBadge(isActive: table.isActive),
                  if (table.updatedAt != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Updated ${_formatDateTime(table.updatedAt!)}',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: 'Preview QR code',
              onPressed: onPreview,
              icon: const Icon(Icons.qr_code_2_outlined),
            ),
            if (canManage)
              PopupMenuButton<_TableAction>(
                enabled: !isSaving,
                tooltip: 'Table actions',
                onSelected: onAction,
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: _TableAction.edit,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Edit'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _TableAction.toggleActive,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        table.isActive
                            ? Icons.block_outlined
                            : Icons.check_circle_outline,
                      ),
                      title: Text(table.isActive ? 'Disable' : 'Enable'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: _TableAction.rotateToken,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.autorenew),
                      title: Text('Generate new QR'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.isActive});

  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final color = isActive ? Colors.green.shade700 : Colors.grey.shade700;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isActive ? 'Active' : 'Inactive',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SingleTableDialog extends StatefulWidget {
  const _SingleTableDialog();

  @override
  State<_SingleTableDialog> createState() => _SingleTableDialogState();
}

class _SingleTableDialogState extends State<_SingleTableDialog> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add table'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          maxLength: 40,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Table number',
            hintText: 'Table 12',
            border: OutlineInputBorder(),
          ),
          validator: _validateTableNumber,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) return;
    Navigator.of(context).pop(_controller.text.trim());
  }
}

class _TableRangeDialog extends StatefulWidget {
  const _TableRangeDialog();

  @override
  State<_TableRangeDialog> createState() => _TableRangeDialogState();
}

class _TableRangeDialogState extends State<_TableRangeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _prefixController = TextEditingController(text: 'Table ');
  final _startController = TextEditingController(text: '1');
  final _endController = TextEditingController(text: '10');
  bool _padNumbers = false;

  @override
  void dispose() {
    _prefixController.dispose();
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add a table range'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _prefixController,
                maxLength: 32,
                decoration: const InputDecoration(
                  labelText: 'Prefix',
                  hintText: 'Table ',
                  border: OutlineInputBorder(),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _startController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'First',
                        border: OutlineInputBorder(),
                      ),
                      validator: _validateRangeNumber,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _endController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Last',
                        border: OutlineInputBorder(),
                      ),
                      validator: _validateRangeNumber,
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Pad numbers with zeros'),
                subtitle: const Text('Example: Table 01, Table 02'),
                value: _padNumbers,
                onChanged: (value) => setState(() => _padNumbers = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Add range')),
      ],
    );
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) return;
    final first = int.parse(_startController.text.trim());
    final last = int.parse(_endController.text.trim());
    final count = last - first + 1;
    if (last < first || count > 100) {
      _showDialogMessage('The range must contain 1-100 tables.');
      return;
    }
    final prefix = _prefixController.text;
    final numberLength = last.toString().length;
    final width = _padNumbers
        ? numberLength < 2
              ? 2
              : numberLength
        : 0;
    final values = [
      for (var number = first; number <= last; number++)
        '$prefix${width == 0 ? number : number.toString().padLeft(width, '0')}'
            .trim(),
    ];
    if (values.any((value) => _validateTableNumber(value) != null)) {
      _showDialogMessage('One or more generated table numbers are too long.');
      return;
    }
    Navigator.of(context).pop(values);
  }

  void _showDialogMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

class _EditTableDialog extends StatefulWidget {
  const _EditTableDialog({required this.table});

  final MerchantDiningTable table;

  @override
  State<_EditTableDialog> createState() => _EditTableDialogState();
}

class _EditTableDialogState extends State<_EditTableDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;
  late bool _isActive;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.table.tableNumber);
    _isActive = widget.table.isActive;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit table'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _controller,
              autofocus: true,
              maxLength: 40,
              decoration: const InputDecoration(
                labelText: 'Table number',
                border: OutlineInputBorder(),
              ),
              validator: _validateTableNumber,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active'),
              value: _isActive,
              onChanged: (value) => setState(() => _isActive = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) return;
    Navigator.of(context).pop(
      _TableEditInput(
        tableNumber: _controller.text.trim(),
        isActive: _isActive,
      ),
    );
  }
}

class _TableEditInput {
  const _TableEditInput({required this.tableNumber, required this.isActive});

  final String tableNumber;
  final bool isActive;
}

class _TableQrDialog extends StatefulWidget {
  const _TableQrDialog({required this.table});

  final MerchantDiningTable table;

  @override
  State<_TableQrDialog> createState() => _TableQrDialogState();
}

class _TableQrDialogState extends State<_TableQrDialog> {
  bool _isWorking = false;

  MerchantDiningTable get table => widget.table;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: 'Close',
                  onPressed: _isWorking
                      ? null
                      : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ),
              Text(
                table.tableNumber,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Text('Scan to order'),
              const SizedBox(height: 20),
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(14),
                child: QrImageView(
                  data: table.effectiveQrPayload,
                  version: QrVersions.auto,
                  size: 260,
                  gapless: true,
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                  semanticsLabel: '${table.tableNumber} QR code',
                ),
              ),
              const SizedBox(height: 20),
              if (_isWorking) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 12),
              ],
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _isWorking ? null : _copyCode,
                    icon: const Icon(Icons.copy_outlined),
                    label: const Text('Copy code'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isWorking ? null : _savePng,
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('Save PNG'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isWorking ? null : _savePdf,
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Save PDF'),
                  ),
                  FilledButton.icon(
                    onPressed: _isWorking ? null : _print,
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('Print'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: table.tableToken));
    if (mounted) _showMessage('Table code copied.');
  }

  Future<void> _savePng() async {
    await _runExport(() async {
      final bytes = await _buildQrPng(table.effectiveQrPayload);
      final path = await _saveQrFile(
        name: '${_fileStem(table.tableNumber)}_qr',
        bytes: bytes,
        fileExtension: 'png',
        mimeType: MimeType.png,
      );
      return path == null ? 'Save cancelled.' : 'QR image saved.';
    });
  }

  Future<void> _savePdf() async {
    await _runExport(() async {
      final bytes = await buildDineInTableQrPdf(table: table);
      final path = await _saveQrFile(
        name: '${_fileStem(table.tableNumber)}_qr',
        bytes: bytes,
        fileExtension: 'pdf',
        mimeType: MimeType.pdf,
      );
      return path == null ? 'Save cancelled.' : 'QR PDF saved.';
    });
  }

  Future<String?> _saveQrFile({
    required String name,
    required Uint8List bytes,
    required String fileExtension,
    required MimeType mimeType,
  }) {
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.linux) {
      return FileSaver.instance.saveFile(
        name: name,
        bytes: bytes,
        fileExtension: fileExtension,
        mimeType: mimeType,
      );
    }
    return FileSaver.instance.saveAs(
      name: name,
      bytes: bytes,
      fileExtension: fileExtension,
      mimeType: mimeType,
    );
  }

  Future<void> _print() async {
    await _runExport(() async {
      await Printing.layoutPdf(
        name: '${_fileStem(table.tableNumber)}_qr.pdf',
        onLayout: (format) =>
            buildDineInTableQrPdf(table: table, pageFormat: format),
      );
      return 'Print dialog opened.';
    });
  }

  Future<void> _runExport(Future<String> Function() action) async {
    setState(() => _isWorking = true);
    try {
      final message = await action();
      if (mounted) _showMessage(message);
    } catch (error) {
      if (mounted) {
        _showMessage('Unable to export QR code: $error', error: true);
      }
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  void _showMessage(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? Colors.red.shade700 : null,
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

String? _validateTableNumber(String? value) {
  final normalized = value?.trim() ?? '';
  if (normalized.isEmpty) return 'Enter a table number.';
  if (normalized.length > 40) return 'Use no more than 40 characters.';
  if (RegExp(r'[\x00-\x1F\x7F]').hasMatch(normalized)) {
    return 'Control characters are not allowed.';
  }
  return null;
}

String? _validateRangeNumber(String? value) {
  final number = int.tryParse(value?.trim() ?? '');
  if (number == null || number < 0 || number > 999999) {
    return 'Enter 0-999999.';
  }
  return null;
}

Future<Uint8List> _buildQrPng(String payload) async {
  const size = 1200.0;
  final painter = QrPainter(
    data: payload,
    version: QrVersions.auto,
    errorCorrectionLevel: QrErrorCorrectLevel.M,
    gapless: true,
  );
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, size, size),
    ui.Paint()..color = Colors.white,
  );
  painter.paint(canvas, const ui.Size.square(size));
  final image = await recorder.endRecording().toImage(
    size.toInt(),
    size.toInt(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) throw StateError('QR image could not be encoded.');
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

String _fileStem(String value) {
  final normalized = value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return normalized.isEmpty ? 'dine_in_table' : normalized;
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
