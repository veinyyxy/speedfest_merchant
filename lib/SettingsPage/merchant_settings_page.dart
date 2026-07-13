import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../Common/merchant_service_config.dart';
import '../Controller/merchant_session_provider.dart';
import '../Controller/merchant_settings_provider.dart';
import '../Models/merchant_buyer_config.dart';
import '../PrinterPage/merchant_printers_page.dart';

class MerchantSettingsPage extends StatefulWidget {
  const MerchantSettingsPage({super.key});

  @override
  State<MerchantSettingsPage> createState() => _MerchantSettingsPageState();
}

class _MerchantSettingsPageState extends State<MerchantSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _imagePicker = ImagePicker();
  final _storeNameController = TextEditingController();
  final _storePhoneController = TextEditingController();
  final _addressLine1Controller = TextEditingController();
  final _addressCityController = TextEditingController();
  final _addressRegionController = TextEditingController();
  final _addressCountryController = TextEditingController();
  final _addressPostalCodeController = TextEditingController();
  final _addressDisplayController = TextEditingController();
  final _logoAltController = TextEditingController();
  final _logoUrlController = TextEditingController();
  final _deliveryFeeController = TextEditingController();
  final _deliveryServiceFeeController = TextEditingController();
  final _taxNameController = TextEditingController();
  final _taxRateController = TextEditingController();
  final _pickupMinController = TextEditingController();
  final _pickupMaxController = TextEditingController();
  final _timezoneController = TextEditingController(text: 'America/Winnipeg');
  final _weeklyIntervals = <String, List<_IntervalForm>>{};
  final _specialDateForms = <_SpecialDateForm>[];
  final _holidayDateForms = <_HolidayDateForm>[];

  String _currency = 'CAD';
  String _logoAssetId = '';
  bool _publicHolidaysClosedByDefault = false;
  bool _dineInInStoreEnabled = true;
  bool _dineInCashEnabled = true;
  bool _dineInPosCardEnabled = true;
  String _dineInCollectionTiming = 'after_service';
  bool _takeoutInStoreEnabled = true;
  bool _takeoutCashEnabled = true;
  bool _takeoutPosCardEnabled = true;
  String _takeoutCollectionTiming = 'at_pickup';
  bool _didLoad = false;

  @override
  void initState() {
    super.initState();
    for (final day in merchantWeekdayKeys) {
      _weeklyIntervals[day] = [_defaultIntervalForm(day)];
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchSettings());
  }

  @override
  void dispose() {
    _storeNameController.dispose();
    _storePhoneController.dispose();
    _addressLine1Controller.dispose();
    _addressCityController.dispose();
    _addressRegionController.dispose();
    _addressCountryController.dispose();
    _addressPostalCodeController.dispose();
    _addressDisplayController.dispose();
    _logoAltController.dispose();
    _logoUrlController.dispose();
    _deliveryFeeController.dispose();
    _deliveryServiceFeeController.dispose();
    _taxNameController.dispose();
    _taxRateController.dispose();
    _pickupMinController.dispose();
    _pickupMaxController.dispose();
    _timezoneController.dispose();
    _disposeWeeklyIntervals();
    _disposeSpecialDates();
    _disposeHolidayDates();
    super.dispose();
  }

  Future<void> _fetchSettings() async {
    final session = context.read<MerchantSessionProvider>();
    final token = session.token;
    if (token == null) return;
    final provider = context.read<MerchantSettingsProvider>();

    await provider.fetchBuyerConfig(apiClient: session.apiClient, token: token);
    if (!mounted) return;

    final config = provider.buyerConfig;
    if (config != null) {
      _applyConfig(config);
    }
  }

  void _applyConfig(MerchantBuyerConfig config) {
    final nextWeekly = <String, List<_IntervalForm>>{};
    for (final day in merchantWeekdayKeys) {
      nextWeekly[day] = _formsFromIntervals(
        config.businessHours.weekly[day] ?? const <MerchantBusinessInterval>[],
      );
    }

    final publicHolidays = _readDynamicMap(config.businessHours.publicHolidays);

    setState(() {
      _didLoad = true;
      _storeNameController.text = config.storeProfile.name;
      _storePhoneController.text = config.storeProfile.phone;
      _addressLine1Controller.text = config.storeProfile.addressLine1;
      _addressCityController.text = config.storeProfile.city;
      _addressRegionController.text = config.storeProfile.region;
      _addressCountryController.text = config.storeProfile.country;
      _addressPostalCodeController.text = config.storeProfile.postalCode;
      _addressDisplayController.text = config.storeProfile.addressDisplay;
      _logoAltController.text = config.storeProfile.logoAlt;
      _logoUrlController.text = config.storeProfile.logoUrl;
      _logoAssetId = config.storeProfile.logoAssetId;
      _currency = config.pricing.currency;
      _deliveryFeeController.text = config.pricing.deliveryFee.toStringAsFixed(
        2,
      );
      _deliveryServiceFeeController.text = config.pricing.deliveryServiceFee
          .toStringAsFixed(2);
      _taxNameController.text = config.pricing.taxName;
      _taxRateController.text = (config.pricing.taxRate * 100).toStringAsFixed(
        2,
      );
      _pickupMinController.text = config.pickupEta.minMinutes.toString();
      _pickupMaxController.text = config.pickupEta.maxMinutes.toString();
      _timezoneController.text = config.businessHours.timezone;
      _publicHolidaysClosedByDefault = _readBool(
        publicHolidays['closed_by_default'],
      );
      _dineInInStoreEnabled = config.inStorePayment.dineIn.enabled;
      _dineInCashEnabled = config.inStorePayment.dineIn.cashEnabled;
      _dineInPosCardEnabled = config.inStorePayment.dineIn.posCardEnabled;
      _dineInCollectionTiming = config.inStorePayment.dineIn.collectionTiming;
      _takeoutInStoreEnabled = config.inStorePayment.takeout.enabled;
      _takeoutCashEnabled = config.inStorePayment.takeout.cashEnabled;
      _takeoutPosCardEnabled = config.inStorePayment.takeout.posCardEnabled;
      _takeoutCollectionTiming = config.inStorePayment.takeout.collectionTiming;

      _replaceWeeklyIntervals(nextWeekly);
      _replaceSpecialDates(
        _specialDateFormsFromRaw(config.businessHours.specialDates),
      );
      _replaceHolidayDates(_holidayDateFormsFromRaw(publicHolidays['dates']));
    });
  }

  Future<void> _saveSettings() async {
    final formValid = _formKey.currentState?.validate() ?? false;
    if (!formValid) return;

    final session = context.read<MerchantSessionProvider>();
    final token = session.token;
    if (token == null) return;
    final provider = context.read<MerchantSettingsProvider>();

    final taxPercent = _readDouble(_taxRateController.text);
    final minMinutes = _readInt(_pickupMinController.text);
    final maxMinutes = _readInt(_pickupMaxController.text);
    if (maxMinutes < minMinutes) {
      _showMessage('Pickup max minutes must be greater than min minutes.');
      return;
    }
    if ((_dineInInStoreEnabled &&
            !_dineInCashEnabled &&
            !_dineInPosCardEnabled) ||
        (_takeoutInStoreEnabled &&
            !_takeoutCashEnabled &&
            !_takeoutPosCardEnabled)) {
      _showMessage(
        'Enable cash or POS card for each enabled in-store payment option.',
      );
      return;
    }

    final timeError = _validateBusinessHoursOrder();
    if (timeError != null) {
      _showMessage(timeError);
      return;
    }

    final config = MerchantBuyerConfig(
      storeProfile: MerchantStoreProfileConfig(
        name: _storeNameController.text.trim(),
        phone: _storePhoneController.text.trim(),
        addressLine1: _addressLine1Controller.text.trim(),
        city: _addressCityController.text.trim(),
        region: _addressRegionController.text.trim(),
        country: _addressCountryController.text.trim(),
        postalCode: _addressPostalCodeController.text.trim(),
        addressDisplay: _addressDisplayController.text.trim().isEmpty
            ? _storeAddressDisplayFallback()
            : _addressDisplayController.text.trim(),
        logoAssetId: _logoAssetId,
        logoUrl: _logoUrlController.text.trim(),
        logoAlt: _logoAltController.text.trim().isEmpty
            ? '${_storeNameController.text.trim()} logo'
            : _logoAltController.text.trim(),
      ),
      pricing: MerchantPricingConfig(
        currency: _currency,
        deliveryFee: _readDouble(_deliveryFeeController.text),
        deliveryServiceFee: _readDouble(_deliveryServiceFeeController.text),
        taxName: _taxNameController.text.trim(),
        taxRate: taxPercent / 100,
      ),
      businessHours: MerchantBusinessHoursConfig(
        timezone: _timezoneController.text.trim(),
        weekly: {
          for (final day in merchantWeekdayKeys)
            day: (_weeklyIntervals[day] ?? const <_IntervalForm>[])
                .map(
                  (interval) => MerchantBusinessInterval(
                    open: interval.openController.text.trim(),
                    close: interval.closeController.text.trim(),
                  ),
                )
                .toList(growable: false),
        },
        specialDates: _specialDateForms
            .map((form) => form.toJson())
            .toList(growable: false),
        publicHolidays: {
          'closed_by_default': _publicHolidaysClosedByDefault,
          'dates': _holidayDateForms
              .map((form) => form.toJson())
              .toList(growable: false),
        },
      ),
      pickupEta: MerchantPickupEtaConfig(
        minMinutes: minMinutes,
        maxMinutes: maxMinutes,
      ),
      inStorePayment: MerchantInStorePaymentConfig(
        dineIn: MerchantInStorePaymentOption(
          enabled: _dineInInStoreEnabled,
          collectionTiming: _dineInCollectionTiming,
          cashEnabled: _dineInCashEnabled,
          posCardEnabled: _dineInPosCardEnabled,
        ),
        takeout: MerchantInStorePaymentOption(
          enabled: _takeoutInStoreEnabled,
          collectionTiming: _takeoutCollectionTiming,
          cashEnabled: _takeoutCashEnabled,
          posCardEnabled: _takeoutPosCardEnabled,
        ),
      ),
    );

    final ok = await provider.saveBuyerConfig(
      apiClient: session.apiClient,
      token: token,
      config: config,
    );
    if (!mounted) return;

    if (ok && provider.buyerConfig != null) {
      _applyConfig(provider.buyerConfig!);
      _showMessage('Settings saved.');
      return;
    }
    _showMessage(provider.errorMessage ?? 'Settings could not be saved.');
  }

  Future<void> _pickAndUploadLogo() async {
    final source = await _showImageSourcePicker();
    if (!mounted || source == null) return;
    await _pickAndUploadLogoFromSource(source);
  }

  Future<void> _openPrinters() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const MerchantPrintersPage()),
    );
  }

  Future<ImageSource?> _showImageSourcePicker() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndUploadLogoFromSource(ImageSource source) async {
    final session = context.read<MerchantSessionProvider>();
    final token = session.token;
    if (token == null) return;
    final provider = context.read<MerchantSettingsProvider>();

    try {
      final pickedImage = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 82,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (pickedImage == null) return;

      final bytes = await pickedImage.readAsBytes();
      if (bytes.isEmpty) {
        _showMessage('Selected image is empty.');
        return;
      }

      final result = await provider.uploadStoreLogo(
        apiClient: session.apiClient,
        token: token,
        bytes: bytes,
        filename: _pickedLogoFilename(pickedImage),
      );
      if (!mounted) return;

      if (result == null) {
        _showMessage(provider.errorMessage ?? 'Logo could not be uploaded.');
        return;
      }

      setState(() {
        _logoAssetId = result.assetId;
        _logoUrlController.text = result.imageUrl;
        if (_logoAltController.text.trim().isEmpty) {
          final name = _storeNameController.text.trim();
          _logoAltController.text = name.isEmpty ? 'Store logo' : '$name logo';
        }
      });
      _showMessage('Logo uploaded.');
    } catch (e) {
      if (!mounted) return;
      _showMessage('Logo could not be uploaded: $e');
    }
  }

  void _replaceWeeklyIntervals(Map<String, List<_IntervalForm>> next) {
    _disposeWeeklyIntervals();
    _weeklyIntervals.addAll(next);
  }

  void _replaceSpecialDates(List<_SpecialDateForm> next) {
    _disposeSpecialDates();
    _specialDateForms.addAll(next);
  }

  void _replaceHolidayDates(List<_HolidayDateForm> next) {
    _disposeHolidayDates();
    _holidayDateForms.addAll(next);
  }

  void _disposeWeeklyIntervals() {
    for (final intervals in _weeklyIntervals.values) {
      _disposeIntervalForms(intervals);
    }
    _weeklyIntervals.clear();
  }

  void _disposeSpecialDates() {
    for (final form in _specialDateForms) {
      form.dispose();
    }
    _specialDateForms.clear();
  }

  void _disposeHolidayDates() {
    for (final form in _holidayDateForms) {
      form.dispose();
    }
    _holidayDateForms.clear();
  }

  void _disposeIntervalForms(List<_IntervalForm> intervals) {
    for (final interval in intervals) {
      interval.dispose();
    }
  }

  List<_IntervalForm> _formsFromIntervals(
    List<MerchantBusinessInterval> intervals,
  ) {
    return intervals
        .map(
          (interval) =>
              _IntervalForm(open: interval.open, close: interval.close),
        )
        .toList(growable: true);
  }

  List<_IntervalForm> _formsFromRawIntervals(dynamic value, [String? day]) {
    if (value is! List) return <_IntervalForm>[];
    final forms = <_IntervalForm>[];
    for (final item in value) {
      final map = _readDynamicMap(item);
      final open = _readString(map['open']);
      final close = _readString(map['close']);
      if (open.isEmpty && close.isEmpty) continue;
      forms.add(
        _IntervalForm(
          open: open.isEmpty ? _defaultOpenForDay(day) : open,
          close: close.isEmpty ? _defaultCloseForDay(day) : close,
        ),
      );
    }
    return forms;
  }

  List<_SpecialDateForm> _specialDateFormsFromRaw(List<dynamic> value) {
    final forms = <_SpecialDateForm>[];
    for (final item in value) {
      final map = _readDynamicMap(item);
      final closed = _readBool(map['closed']);
      final rawIntervals = map['hours'] ?? map['intervals'];
      final intervals = _formsFromRawIntervals(rawIntervals);
      if (!closed && intervals.isEmpty) {
        intervals.add(_defaultIntervalForm());
      }
      forms.add(
        _SpecialDateForm(
          date: _readString(map['date']),
          name: _readString(map['name']),
          closed: closed,
          intervals: intervals,
        ),
      );
    }
    return forms;
  }

  List<_HolidayDateForm> _holidayDateFormsFromRaw(dynamic value) {
    if (value is! List) return <_HolidayDateForm>[];
    final forms = <_HolidayDateForm>[];
    for (final item in value) {
      final map = _readDynamicMap(item);
      forms.add(
        _HolidayDateForm(
          date: _readString(map['date']),
          name: _readString(map['name']),
        ),
      );
    }
    return forms;
  }

  void _setDayOpen(String day, bool value) {
    setState(() {
      final intervals = _weeklyIntervals.putIfAbsent(day, () => []);
      if (value) {
        if (intervals.isEmpty) intervals.add(_defaultIntervalForm(day));
        return;
      }
      _disposeIntervalForms(intervals);
      intervals.clear();
    });
  }

  void _addWeeklyInterval(String day) {
    setState(() {
      _weeklyIntervals
          .putIfAbsent(day, () => [])
          .add(_defaultIntervalForm(day));
    });
  }

  void _removeWeeklyInterval(String day, int index) {
    setState(() {
      final intervals = _weeklyIntervals[day];
      if (intervals == null || index < 0 || index >= intervals.length) return;
      intervals.removeAt(index).dispose();
    });
  }

  void _addSpecialDate() {
    setState(() {
      _specialDateForms.add(
        _SpecialDateForm(date: '', name: '', closed: true, intervals: []),
      );
    });
  }

  void _removeSpecialDate(int index) {
    setState(() {
      if (index < 0 || index >= _specialDateForms.length) return;
      _specialDateForms.removeAt(index).dispose();
    });
  }

  void _setSpecialDateClosed(int index, bool value) {
    setState(() {
      if (index < 0 || index >= _specialDateForms.length) return;
      final form = _specialDateForms[index];
      form.closed = value;
      if (!value && form.intervals.isEmpty) {
        form.intervals.add(_defaultIntervalForm());
      }
    });
  }

  void _addSpecialDateInterval(int index) {
    setState(() {
      if (index < 0 || index >= _specialDateForms.length) return;
      _specialDateForms[index].intervals.add(_defaultIntervalForm());
    });
  }

  void _removeSpecialDateInterval(int specialIndex, int intervalIndex) {
    setState(() {
      if (specialIndex < 0 || specialIndex >= _specialDateForms.length) return;
      final intervals = _specialDateForms[specialIndex].intervals;
      if (intervalIndex < 0 || intervalIndex >= intervals.length) return;
      intervals.removeAt(intervalIndex).dispose();
    });
  }

  void _addHolidayDate() {
    setState(() {
      _holidayDateForms.add(_HolidayDateForm(date: '', name: ''));
    });
  }

  void _removeHolidayDate(int index) {
    setState(() {
      if (index < 0 || index >= _holidayDateForms.length) return;
      _holidayDateForms.removeAt(index).dispose();
    });
  }

  String? _validateBusinessHoursOrder() {
    for (final day in merchantWeekdayKeys) {
      final error = _validateIntervalForms(
        _weeklyIntervals[day] ?? const <_IntervalForm>[],
        _humanizeDay(day),
      );
      if (error != null) return error;
    }

    for (var index = 0; index < _specialDateForms.length; index++) {
      final form = _specialDateForms[index];
      if (form.closed) continue;
      final label = form.dateController.text.trim().isEmpty
          ? 'Special date ${index + 1}'
          : form.dateController.text.trim();
      final error = _validateIntervalForms(
        form.intervals,
        label,
        requireOne: true,
      );
      if (error != null) return error;
    }
    return null;
  }

  String? _validateIntervalForms(
    List<_IntervalForm> intervals,
    String label, {
    bool requireOne = false,
  }) {
    if (requireOne && intervals.isEmpty) {
      return '$label needs at least one interval or mark it closed.';
    }

    final parsed = <_ParsedInterval>[];
    for (var index = 0; index < intervals.length; index++) {
      final form = intervals[index];
      final open = _parseTimeToMinutes(form.openController.text);
      final close = _parseTimeToMinutes(form.closeController.text);
      if (open == null || close == null) continue;
      if (close <= open) {
        return '$label interval ${index + 1} close time must be after open time.';
      }
      parsed.add(_ParsedInterval(open: open, close: close));
    }

    parsed.sort((a, b) => a.open.compareTo(b.open));
    for (var index = 1; index < parsed.length; index++) {
      if (parsed[index].open < parsed[index - 1].close) {
        return '$label intervals cannot overlap.';
      }
    }
    return null;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MerchantSettingsProvider>();
    final isBusy =
        provider.isLoading || provider.isSaving || provider.isUploadingLogo;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: isBusy ? null : _fetchSettings,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: RefreshIndicator(
          onRefresh: _fetchSettings,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              if (provider.isLoading && !_didLoad) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 12),
              ],
              if (provider.errorMessage != null && !_didLoad) ...[
                _SettingsError(
                  message: provider.errorMessage!,
                  onRetry: _fetchSettings,
                ),
                const SizedBox(height: 12),
              ],
              _SettingsCard(
                title: 'Printers',
                children: [
                  Text(
                    'Manage receipt printers for this device. Saved printers stay local to the merchant app.',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _openPrinters,
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('Manage printers'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _SettingsCard(
                title: 'Store Profile',
                children: [
                  _LogoEditor(
                    controller: _logoUrlController,
                    enabled: !isBusy,
                    isUploading: provider.isUploadingLogo,
                    onUpload: _pickAndUploadLogo,
                    onUrlChanged: () {
                      setState(() => _logoAssetId = '');
                    },
                    onRemove: () {
                      setState(() {
                        _logoAssetId = '';
                        _logoUrlController.clear();
                      });
                    },
                  ),
                  if (_logoAssetId.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Asset ID: $_logoAssetId',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _logoAltController,
                    enabled: !isBusy,
                    decoration: const InputDecoration(
                      labelText: 'Logo Alt Text',
                      border: OutlineInputBorder(),
                    ),
                    validator: _requiredValidator,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _storeNameController,
                    enabled: !isBusy,
                    decoration: const InputDecoration(
                      labelText: 'Store Name',
                      border: OutlineInputBorder(),
                    ),
                    validator: _requiredValidator,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _storePhoneController,
                    enabled: !isBusy,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone',
                      border: OutlineInputBorder(),
                    ),
                    validator: _requiredValidator,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _addressLine1Controller,
                    enabled: !isBusy,
                    decoration: const InputDecoration(
                      labelText: 'Address Line 1',
                      border: OutlineInputBorder(),
                    ),
                    validator: _requiredValidator,
                  ),
                  const SizedBox(height: 12),
                  _ResponsivePair(
                    first: TextFormField(
                      controller: _addressCityController,
                      enabled: !isBusy,
                      decoration: const InputDecoration(
                        labelText: 'City',
                        border: OutlineInputBorder(),
                      ),
                      validator: _requiredValidator,
                    ),
                    second: TextFormField(
                      controller: _addressRegionController,
                      enabled: !isBusy,
                      decoration: const InputDecoration(
                        labelText: 'Region',
                        border: OutlineInputBorder(),
                      ),
                      validator: _requiredValidator,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ResponsivePair(
                    first: TextFormField(
                      controller: _addressCountryController,
                      enabled: !isBusy,
                      decoration: const InputDecoration(
                        labelText: 'Country',
                        border: OutlineInputBorder(),
                      ),
                      validator: _requiredValidator,
                    ),
                    second: TextFormField(
                      controller: _addressPostalCodeController,
                      enabled: !isBusy,
                      decoration: const InputDecoration(
                        labelText: 'Postal Code',
                        border: OutlineInputBorder(),
                      ),
                      validator: _requiredValidator,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _addressDisplayController,
                    enabled: !isBusy,
                    decoration: InputDecoration(
                      labelText: 'Display Address',
                      helperText: _storeAddressDisplayFallback(),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _ScopeNote(),
              const SizedBox(height: 12),
              _SettingsCard(
                title: 'Pricing',
                children: [
                  DropdownButtonFormField<String>(
                    value: _currency,
                    decoration: const InputDecoration(
                      labelText: 'Currency',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'CAD', child: Text('CAD')),
                    ],
                    onChanged: isBusy
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() => _currency = value);
                          },
                  ),
                  const SizedBox(height: 12),
                  _MoneyField(
                    controller: _deliveryFeeController,
                    label: 'Delivery Fee',
                    enabled: !isBusy,
                  ),
                  const SizedBox(height: 12),
                  _MoneyField(
                    controller: _deliveryServiceFeeController,
                    label: 'Delivery Service Fee',
                    enabled: !isBusy,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _taxNameController,
                    enabled: !isBusy,
                    decoration: const InputDecoration(
                      labelText: 'Tax Name',
                      border: OutlineInputBorder(),
                    ),
                    validator: _requiredValidator,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _taxRateController,
                    enabled: !isBusy,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Tax Rate',
                      suffixText: '%',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) =>
                        _numberRangeValidator(value, min: 0, max: 100),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _SettingsCard(
                title: 'Pickup',
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _IntegerField(
                          controller: _pickupMinController,
                          label: 'Min minutes',
                          enabled: !isBusy,
                          onChanged: () => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _IntegerField(
                          controller: _pickupMaxController,
                          label: 'Max minutes',
                          enabled: !isBusy,
                          onChanged: () => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Display: ${_pickupDisplay()}',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _SettingsCard(
                title: 'In-store Payment',
                children: [
                  Text(
                    'Customers can still pay online. These options control orders that are settled at the restaurant.',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 10),
                  _InStorePaymentOptionEditor(
                    title: 'Dine-in',
                    buyerLabel: 'Pay at counter',
                    enabled: _dineInInStoreEnabled,
                    cashEnabled: _dineInCashEnabled,
                    posCardEnabled: _dineInPosCardEnabled,
                    collectionTiming: _dineInCollectionTiming,
                    isBusy: isBusy,
                    onEnabledChanged: (value) =>
                        setState(() => _dineInInStoreEnabled = value),
                    onCashChanged: (value) =>
                        setState(() => _dineInCashEnabled = value),
                    onPosCardChanged: (value) =>
                        setState(() => _dineInPosCardEnabled = value),
                    onTimingChanged: (value) =>
                        setState(() => _dineInCollectionTiming = value),
                  ),
                  const Divider(height: 28),
                  _InStorePaymentOptionEditor(
                    title: 'Takeout',
                    buyerLabel: 'Pay at store',
                    enabled: _takeoutInStoreEnabled,
                    cashEnabled: _takeoutCashEnabled,
                    posCardEnabled: _takeoutPosCardEnabled,
                    collectionTiming: _takeoutCollectionTiming,
                    isBusy: isBusy,
                    onEnabledChanged: (value) =>
                        setState(() => _takeoutInStoreEnabled = value),
                    onCashChanged: (value) =>
                        setState(() => _takeoutCashEnabled = value),
                    onPosCardChanged: (value) =>
                        setState(() => _takeoutPosCardEnabled = value),
                    onTimingChanged: (value) =>
                        setState(() => _takeoutCollectionTiming = value),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _SettingsCard(
                title: 'Business Hours',
                children: [
                  TextFormField(
                    controller: _timezoneController,
                    enabled: !isBusy,
                    decoration: const InputDecoration(
                      labelText: 'Timezone',
                      border: OutlineInputBorder(),
                    ),
                    validator: _requiredValidator,
                  ),
                  const SizedBox(height: 12),
                  for (final day in merchantWeekdayKeys) ...[
                    _BusinessDayEditor(
                      day: day,
                      enabled: !isBusy,
                      intervals:
                          _weeklyIntervals[day] ?? const <_IntervalForm>[],
                      onOpenChanged: (value) => _setDayOpen(day, value),
                      onAddInterval: () => _addWeeklyInterval(day),
                      onRemoveInterval: (index) =>
                          _removeWeeklyInterval(day, index),
                    ),
                    if (day != merchantWeekdayKeys.last)
                      const Divider(height: 24),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              _SettingsCard(
                title: 'Special Dates',
                children: [
                  if (_specialDateForms.isEmpty)
                    Text(
                      'No special date overrides.',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  for (
                    var index = 0;
                    index < _specialDateForms.length;
                    index++
                  ) ...[
                    _SpecialDateEditor(
                      index: index,
                      form: _specialDateForms[index],
                      enabled: !isBusy,
                      onClosedChanged: (value) =>
                          _setSpecialDateClosed(index, value),
                      onAddInterval: () => _addSpecialDateInterval(index),
                      onRemoveInterval: (intervalIndex) =>
                          _removeSpecialDateInterval(index, intervalIndex),
                      onRemove: () => _removeSpecialDate(index),
                    ),
                    const SizedBox(height: 12),
                  ],
                  OutlinedButton.icon(
                    onPressed: isBusy ? null : _addSpecialDate,
                    icon: const Icon(Icons.add),
                    label: const Text('Add special date'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _SettingsCard(
                title: 'Public Holidays',
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Closed by default on listed holidays'),
                    value: _publicHolidaysClosedByDefault,
                    onChanged: isBusy
                        ? null
                        : (value) {
                            setState(() {
                              _publicHolidaysClosedByDefault = value;
                            });
                          },
                  ),
                  if (_holidayDateForms.isEmpty)
                    Text(
                      'No public holidays listed.',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  for (
                    var index = 0;
                    index < _holidayDateForms.length;
                    index++
                  ) ...[
                    _HolidayDateEditor(
                      form: _holidayDateForms[index],
                      enabled: !isBusy,
                      onRemove: () => _removeHolidayDate(index),
                    ),
                    const SizedBox(height: 12),
                  ],
                  OutlinedButton.icon(
                    onPressed: isBusy ? null : _addHolidayDate,
                    icon: const Icon(Icons.add),
                    label: const Text('Add holiday'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: FilledButton.icon(
          onPressed: isBusy ? null : _saveSettings,
          icon: provider.isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(provider.isSaving ? 'Saving' : 'Save settings'),
        ),
      ),
    );
  }

  String _pickupDisplay() {
    final min = int.tryParse(_pickupMinController.text.trim()) ?? 0;
    final max = int.tryParse(_pickupMaxController.text.trim()) ?? 0;
    return '$min-$max min';
  }

  String _storeAddressDisplayFallback() {
    return [
      _addressLine1Controller.text.trim(),
      _addressCityController.text.trim(),
      _addressRegionController.text.trim(),
      _addressCountryController.text.trim(),
    ].where((part) => part.isNotEmpty).join(', ');
  }
}

class _ScopeNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'These settings update the buyer app defaults for order_client / CA / MB / dev.',
                style: TextStyle(color: Colors.grey.shade800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _SettingsError extends StatelessWidget {
  const _SettingsError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      title: 'Settings could not be loaded',
      children: [
        Text(message, style: TextStyle(color: Colors.red.shade700)),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      ],
    );
  }
}

class _BusinessDayEditor extends StatelessWidget {
  const _BusinessDayEditor({
    required this.day,
    required this.enabled,
    required this.intervals,
    required this.onOpenChanged,
    required this.onAddInterval,
    required this.onRemoveInterval,
  });

  final String day;
  final bool enabled;
  final List<_IntervalForm> intervals;
  final ValueChanged<bool> onOpenChanged;
  final VoidCallback onAddInterval;
  final ValueChanged<int> onRemoveInterval;

  @override
  Widget build(BuildContext context) {
    final label = _humanizeDay(day);
    final isOpen = intervals.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          value: isOpen,
          onChanged: enabled ? onOpenChanged : null,
        ),
        if (isOpen) ...[
          for (var index = 0; index < intervals.length; index++) ...[
            _IntervalEditor(
              form: intervals[index],
              enabled: enabled,
              onRemove: enabled ? () => onRemoveInterval(index) : null,
            ),
            const SizedBox(height: 10),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: enabled ? onAddInterval : null,
              icon: const Icon(Icons.add),
              label: const Text('Add interval'),
            ),
          ),
        ],
      ],
    );
  }
}

class _SpecialDateEditor extends StatelessWidget {
  const _SpecialDateEditor({
    required this.index,
    required this.form,
    required this.enabled,
    required this.onClosedChanged,
    required this.onAddInterval,
    required this.onRemoveInterval,
    required this.onRemove,
  });

  final int index;
  final _SpecialDateForm form;
  final bool enabled;
  final ValueChanged<bool> onClosedChanged;
  final VoidCallback onAddInterval;
  final ValueChanged<int> onRemoveInterval;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return _BorderedPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Special date ${index + 1}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                tooltip: 'Remove special date',
                onPressed: enabled ? onRemove : null,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _ResponsivePair(
            first: TextFormField(
              controller: form.dateController,
              enabled: enabled,
              keyboardType: TextInputType.datetime,
              decoration: const InputDecoration(
                labelText: 'Date',
                hintText: '2026-12-25',
                border: OutlineInputBorder(),
              ),
              validator: _dateValidator,
            ),
            second: TextFormField(
              controller: form.nameController,
              enabled: enabled,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
              validator: _requiredValidator,
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Closed all day'),
            value: form.closed,
            onChanged: enabled ? onClosedChanged : null,
          ),
          if (!form.closed) ...[
            for (var index = 0; index < form.intervals.length; index++) ...[
              _IntervalEditor(
                form: form.intervals[index],
                enabled: enabled,
                onRemove: enabled ? () => onRemoveInterval(index) : null,
              ),
              const SizedBox(height: 10),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: enabled ? onAddInterval : null,
                icon: const Icon(Icons.add),
                label: const Text('Add interval'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HolidayDateEditor extends StatelessWidget {
  const _HolidayDateEditor({
    required this.form,
    required this.enabled,
    required this.onRemove,
  });

  final _HolidayDateForm form;
  final bool enabled;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return _BorderedPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              tooltip: 'Remove holiday',
              onPressed: enabled ? onRemove : null,
              icon: const Icon(Icons.delete_outline),
            ),
          ),
          _ResponsivePair(
            first: TextFormField(
              controller: form.dateController,
              enabled: enabled,
              keyboardType: TextInputType.datetime,
              decoration: const InputDecoration(
                labelText: 'Date',
                hintText: '2026-07-01',
                border: OutlineInputBorder(),
              ),
              validator: _dateValidator,
            ),
            second: TextFormField(
              controller: form.nameController,
              enabled: enabled,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
              validator: _requiredValidator,
            ),
          ),
        ],
      ),
    );
  }
}

class _IntervalEditor extends StatelessWidget {
  const _IntervalEditor({
    required this.form,
    required this.enabled,
    required this.onRemove,
  });

  final _IntervalForm form;
  final bool enabled;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 460;
        final openField = TextFormField(
          controller: form.openController,
          enabled: enabled,
          keyboardType: TextInputType.datetime,
          decoration: const InputDecoration(
            labelText: 'Open',
            hintText: '09:00',
            border: OutlineInputBorder(),
          ),
          validator: _timeValidator,
        );
        final closeField = TextFormField(
          controller: form.closeController,
          enabled: enabled,
          keyboardType: TextInputType.datetime,
          decoration: const InputDecoration(
            labelText: 'Close',
            hintText: '22:00',
            border: OutlineInputBorder(),
          ),
          validator: _timeValidator,
        );
        final removeButton = IconButton(
          tooltip: 'Remove interval',
          onPressed: onRemove,
          icon: const Icon(Icons.remove_circle_outline),
        );

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              openField,
              const SizedBox(height: 10),
              closeField,
              removeButton,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: openField),
            const SizedBox(width: 12),
            Expanded(child: closeField),
            const SizedBox(width: 4),
            removeButton,
          ],
        );
      },
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
        if (constraints.maxWidth < 460) {
          return Column(children: [first, const SizedBox(height: 12), second]);
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: 12),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}

class _BorderedPanel extends StatelessWidget {
  const _BorderedPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).dividerColor;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}

class _LogoEditor extends StatelessWidget {
  const _LogoEditor({
    required this.controller,
    required this.enabled,
    required this.isUploading,
    required this.onUpload,
    required this.onUrlChanged,
    required this.onRemove,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool isUploading;
  final VoidCallback onUpload;
  final VoidCallback onUrlChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final rawUrl = controller.text.trim();
    final imageUrl = _resolveImageUrl(rawUrl);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 3,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: imageUrl.isEmpty
                  ? Center(
                      child: Icon(
                        Icons.storefront_outlined,
                        color: Colors.grey.shade600,
                        size: 44,
                      ),
                    )
                  : Image.network(
                      imageUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: Colors.grey.shade600,
                          size: 40,
                        ),
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: controller,
          enabled: enabled,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Logo URL',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => onUrlChanged(),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: enabled && !isUploading ? onUpload : null,
              icon: isUploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file_outlined),
              label: Text(isUploading ? 'Uploading' : 'Upload logo'),
            ),
            if (rawUrl.isNotEmpty)
              TextButton.icon(
                onPressed: enabled && !isUploading ? onRemove : null,
                icon: const Icon(Icons.close),
                label: const Text('Remove logo'),
              ),
          ],
        ),
      ],
    );
  }
}

class _MoneyField extends StatelessWidget {
  const _MoneyField({
    required this.controller,
    required this.label,
    required this.enabled,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        prefixText: 'CAD \$',
        border: const OutlineInputBorder(),
      ),
      validator: (value) => _numberRangeValidator(value, min: 0),
    );
  }
}

class _IntegerField extends StatelessWidget {
  const _IntegerField({
    required this.controller,
    required this.label,
    required this.enabled,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) => onChanged?.call(),
      validator: (value) => _integerRangeValidator(value, min: 0),
    );
  }
}

class _InStorePaymentOptionEditor extends StatelessWidget {
  const _InStorePaymentOptionEditor({
    required this.title,
    required this.buyerLabel,
    required this.enabled,
    required this.cashEnabled,
    required this.posCardEnabled,
    required this.collectionTiming,
    required this.isBusy,
    required this.onEnabledChanged,
    required this.onCashChanged,
    required this.onPosCardChanged,
    required this.onTimingChanged,
  });

  final String title;
  final String buyerLabel;
  final bool enabled;
  final bool cashEnabled;
  final bool posCardEnabled;
  final String collectionTiming;
  final bool isBusy;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<bool> onCashChanged;
  final ValueChanged<bool> onPosCardChanged;
  final ValueChanged<String> onTimingChanged;

  @override
  Widget build(BuildContext context) {
    final active = enabled && !isBusy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(buyerLabel),
          value: enabled,
          onChanged: isBusy ? null : onEnabledChanged,
        ),
        if (enabled) ...[
          DropdownButtonFormField<String>(
            value: collectionTiming,
            decoration: const InputDecoration(
              labelText: 'Collection timing',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                value: 'before_fulfillment',
                child: Text('Before fulfillment'),
              ),
              DropdownMenuItem(value: 'at_pickup', child: Text('At pickup')),
              DropdownMenuItem(
                value: 'after_service',
                child: Text('After service'),
              ),
            ],
            onChanged: active
                ? (value) {
                    if (value != null) onTimingChanged(value);
                  }
                : null,
          ),
          const SizedBox(height: 8),
          Text(
            'Available methods',
            style: TextStyle(color: Colors.grey.shade700),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Cash'),
            value: cashEnabled,
            onChanged: active ? onCashChanged : null,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('POS card'),
            value: posCardEnabled,
            onChanged: active ? onPosCardChanged : null,
          ),
        ],
      ],
    );
  }
}

class _IntervalForm {
  _IntervalForm({String open = '09:00', String close = '22:00'})
    : openController = TextEditingController(text: open),
      closeController = TextEditingController(text: close);

  final TextEditingController openController;
  final TextEditingController closeController;

  Map<String, dynamic> toJson() {
    return {
      'open': openController.text.trim(),
      'close': closeController.text.trim(),
    };
  }

  void dispose() {
    openController.dispose();
    closeController.dispose();
  }
}

class _SpecialDateForm {
  _SpecialDateForm({
    required String date,
    required String name,
    required this.closed,
    required this.intervals,
  }) : dateController = TextEditingController(text: date),
       nameController = TextEditingController(text: name);

  final TextEditingController dateController;
  final TextEditingController nameController;
  bool closed;
  final List<_IntervalForm> intervals;

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'date': dateController.text.trim(),
      'name': nameController.text.trim(),
      'closed': closed,
    };
    if (!closed) {
      json['hours'] = intervals.map((item) => item.toJson()).toList();
    }
    return json;
  }

  void dispose() {
    dateController.dispose();
    nameController.dispose();
    for (final interval in intervals) {
      interval.dispose();
    }
  }
}

class _HolidayDateForm {
  _HolidayDateForm({required String date, required String name})
    : dateController = TextEditingController(text: date),
      nameController = TextEditingController(text: name);

  final TextEditingController dateController;
  final TextEditingController nameController;

  Map<String, dynamic> toJson() {
    return {
      'date': dateController.text.trim(),
      'name': nameController.text.trim(),
    };
  }

  void dispose() {
    dateController.dispose();
    nameController.dispose();
  }
}

class _ParsedInterval {
  const _ParsedInterval({required this.open, required this.close});

  final int open;
  final int close;
}

_IntervalForm _defaultIntervalForm([String? day]) {
  return _IntervalForm(
    open: _defaultOpenForDay(day),
    close: _defaultCloseForDay(day),
  );
}

String _defaultOpenForDay(String? day) {
  return day == 'sunday' ? '10:00' : '09:00';
}

String _defaultCloseForDay(String? day) {
  return day == 'friday' || day == 'saturday' ? '23:00' : '22:00';
}

String? _requiredValidator(String? value) {
  return (value?.trim().isEmpty ?? true) ? 'Required' : null;
}

String? _numberRangeValidator(String? value, {double min = 0, double? max}) {
  final parsed = double.tryParse(value?.trim() ?? '');
  if (parsed == null) return 'Enter a valid number';
  if (parsed < min) return 'Must be at least $min';
  if (max != null && parsed > max) return 'Must be at most $max';
  return null;
}

String? _integerRangeValidator(String? value, {int min = 0}) {
  final parsed = int.tryParse(value?.trim() ?? '');
  if (parsed == null) return 'Enter a whole number';
  if (parsed < min) return 'Must be at least $min';
  return null;
}

String? _timeValidator(String? value) {
  return _parseTimeToMinutes(value ?? '') == null ? 'Use HH:mm' : null;
}

String? _dateValidator(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return 'Required';
  return _isValidDateText(text) ? null : 'Use YYYY-MM-DD';
}

int? _parseTimeToMinutes(String value) {
  final text = value.trim();
  final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text);
  if (match == null) return null;
  final hour = int.tryParse(match.group(1) ?? '');
  final minute = int.tryParse(match.group(2) ?? '');
  if (hour == null || minute == null) return null;
  if (hour < 0 || hour > 24 || minute < 0 || minute > 59) return null;
  if (hour == 24 && minute != 0) return null;
  return hour * 60 + minute;
}

bool _isValidDateText(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return false;
  final year = int.tryParse(match.group(1) ?? '');
  final month = int.tryParse(match.group(2) ?? '');
  final day = int.tryParse(match.group(3) ?? '');
  if (year == null || month == null || day == null) return false;
  final date = DateTime.utc(year, month, day);
  return date.year == year && date.month == month && date.day == day;
}

String _resolveImageUrl(String imageUrl) {
  final trimmed = imageUrl.trim();
  if (trimmed.isEmpty ||
      trimmed.startsWith('http://') ||
      trimmed.startsWith('https://')) {
    return trimmed;
  }

  final baseUrl = MerchantServiceConfig.baseUrl.endsWith('/')
      ? MerchantServiceConfig.baseUrl.substring(
          0,
          MerchantServiceConfig.baseUrl.length - 1,
        )
      : MerchantServiceConfig.baseUrl;
  if (trimmed.startsWith('/')) return '$baseUrl$trimmed';
  return '$baseUrl/$trimmed';
}

String _pickedLogoFilename(XFile image) {
  final name = image.name.trim();
  if (name.contains('.') && name.split('.').last.trim().isNotEmpty) {
    return name;
  }

  final path = image.path.trim();
  final pathName = path.split(RegExp(r'[\\/]')).last;
  if (pathName.contains('.') && pathName.split('.').last.trim().isNotEmpty) {
    return pathName;
  }

  return 'store-logo.jpg';
}

double _readDouble(String value) {
  return double.tryParse(value.trim()) ?? 0;
}

int _readInt(String value) {
  return int.tryParse(value.trim()) ?? 0;
}

bool _readBool(dynamic value) {
  if (value is bool) return value;
  final text = value?.toString().trim().toLowerCase();
  return text == 'true' || text == '1' || text == 'yes';
}

String _readString(dynamic value) {
  return value?.toString().trim() ?? '';
}

Map<String, dynamic> _readDynamicMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map<String, dynamic>(
      (key, value) => MapEntry(key.toString(), value),
    );
  }
  return <String, dynamic>{};
}

String _humanizeDay(String day) {
  if (day.isEmpty) return day;
  return '${day[0].toUpperCase()}${day.substring(1)}';
}
