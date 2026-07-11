class MerchantBuyerConfig {
  const MerchantBuyerConfig({
    required this.storeProfile,
    required this.pricing,
    required this.businessHours,
    required this.pickupEta,
    required this.inStorePayment,
  });

  final MerchantStoreProfileConfig storeProfile;
  final MerchantPricingConfig pricing;
  final MerchantBusinessHoursConfig businessHours;
  final MerchantPickupEtaConfig pickupEta;
  final MerchantInStorePaymentConfig inStorePayment;

  factory MerchantBuyerConfig.defaults() {
    return MerchantBuyerConfig(
      storeProfile: MerchantStoreProfileConfig.defaults(),
      pricing: const MerchantPricingConfig(
        currency: 'CAD',
        deliveryFee: 4.25,
        deliveryServiceFee: 2.02,
        taxName: 'GST/PST',
        taxRate: 0.13,
      ),
      businessHours: MerchantBusinessHoursConfig.defaults(),
      pickupEta: const MerchantPickupEtaConfig(minMinutes: 15, maxMinutes: 20),
      inStorePayment: MerchantInStorePaymentConfig.defaults(),
    );
  }

  factory MerchantBuyerConfig.fromJson(Map<String, dynamic> json) {
    final store = _readMap(json['store']);
    final pricing = _readMap(json['pricing']);
    final operations = _readMap(json['operations']);
    final fulfillment = _readMap(json['fulfillment']);
    final payment = _readMap(json['payment']);

    return MerchantBuyerConfig(
      storeProfile: MerchantStoreProfileConfig.fromJson(
        _readMap(
          store['profile'] ??
              json['store_profile'] ??
              json['storeProfile'] ??
              json['store.profile'],
        ),
      ),
      pricing: MerchantPricingConfig.fromJson(pricing),
      businessHours: MerchantBusinessHoursConfig.fromJson(
        _readMap(operations['business_hours'] ?? operations['businessHours']),
      ),
      pickupEta: MerchantPickupEtaConfig.fromJson(
        _readMap(fulfillment['pickup_eta'] ?? fulfillment['pickupEta']),
      ),
      inStorePayment: MerchantInStorePaymentConfig.fromJson(
        _readMap(payment['in_store'] ?? payment['inStore']),
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'store': {'profile': storeProfile.toJson()},
      'pricing': pricing.toJson(),
      'operations': {'business_hours': businessHours.toJson()},
      'fulfillment': {'pickup_eta': pickupEta.toJson()},
      'payment': {'in_store': inStorePayment.toJson()},
    };
  }
}

class MerchantInStorePaymentConfig {
  const MerchantInStorePaymentConfig({
    required this.dineIn,
    required this.takeout,
  });

  final MerchantInStorePaymentOption dineIn;
  final MerchantInStorePaymentOption takeout;

  factory MerchantInStorePaymentConfig.defaults() {
    return const MerchantInStorePaymentConfig(
      dineIn: MerchantInStorePaymentOption(
        enabled: true,
        collectionTiming: 'after_service',
        cashEnabled: true,
        posCardEnabled: true,
      ),
      takeout: MerchantInStorePaymentOption(
        enabled: true,
        collectionTiming: 'at_pickup',
        cashEnabled: true,
        posCardEnabled: true,
      ),
    );
  }

  factory MerchantInStorePaymentConfig.fromJson(Map<String, dynamic> json) {
    final fallback = MerchantInStorePaymentConfig.defaults();
    return MerchantInStorePaymentConfig(
      dineIn: MerchantInStorePaymentOption.fromJson(
        _readMap(json['dine_in'] ?? json['dineIn']),
        fallback: fallback.dineIn,
      ),
      takeout: MerchantInStorePaymentOption.fromJson(
        _readMap(json['takeout']),
        fallback: fallback.takeout,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {'dine_in': dineIn.toJson(), 'takeout': takeout.toJson()};
  }
}

class MerchantInStorePaymentOption {
  const MerchantInStorePaymentOption({
    required this.enabled,
    required this.collectionTiming,
    required this.cashEnabled,
    required this.posCardEnabled,
  });

  final bool enabled;
  final String collectionTiming;
  final bool cashEnabled;
  final bool posCardEnabled;

  factory MerchantInStorePaymentOption.fromJson(
    Map<String, dynamic> json, {
    required MerchantInStorePaymentOption fallback,
  }) {
    final methods = _readMap(json['methods']);
    final timing = _firstString(json, const [
      'collection_timing',
      'collectionTiming',
    ], fallback.collectionTiming);
    return MerchantInStorePaymentOption(
      enabled: _firstBool(json, const ['enabled'], fallback.enabled),
      collectionTiming: _isCollectionTiming(timing)
          ? timing
          : fallback.collectionTiming,
      cashEnabled: _firstBool(methods, const ['cash'], fallback.cashEnabled),
      posCardEnabled: _firstBool(methods, const [
        'pos_card',
        'posCard',
      ], fallback.posCardEnabled),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'collection_timing': collectionTiming,
      'methods': {'cash': cashEnabled, 'pos_card': posCardEnabled},
    };
  }
}

class MerchantStoreProfileConfig {
  const MerchantStoreProfileConfig({
    required this.name,
    required this.phone,
    required this.addressLine1,
    required this.city,
    required this.region,
    required this.country,
    required this.postalCode,
    required this.addressDisplay,
    required this.logoAssetId,
    required this.logoUrl,
    required this.logoAlt,
  });

  final String name;
  final String phone;
  final String addressLine1;
  final String city;
  final String region;
  final String country;
  final String postalCode;
  final String addressDisplay;
  final String logoAssetId;
  final String logoUrl;
  final String logoAlt;

  factory MerchantStoreProfileConfig.defaults() {
    return const MerchantStoreProfileConfig(
      name: 'SpeedFeast Restaurant',
      phone: '+1 (204) 555-0138',
      addressLine1: '630 Guelph Street',
      city: 'Winnipeg',
      region: 'MB',
      country: 'Canada',
      postalCode: 'R3M 3B2',
      addressDisplay: '630 Guelph Street, Winnipeg, MB, Canada',
      logoAssetId: '',
      logoUrl: '',
      logoAlt: 'SpeedFeast Restaurant logo',
    );
  }

  factory MerchantStoreProfileConfig.fromJson(Map<String, dynamic> json) {
    final fallback = MerchantStoreProfileConfig.defaults();
    final address = _readMap(json['address']);
    final logo = _readMap(json['logo']);
    final line1 = _firstString(address, const ['line1'], fallback.addressLine1);
    final city = _firstString(address, const ['city'], fallback.city);
    final region = _firstString(address, const ['region'], fallback.region);
    final country = _firstString(address, const ['country'], fallback.country);
    final postalCode = _firstString(address, const [
      'postal_code',
      'postalCode',
    ], fallback.postalCode);
    final display = _firstString(
      address,
      const ['display'],
      [
        line1,
        city,
        region,
        country,
      ].where((part) => part.trim().isNotEmpty).join(', '),
    );

    return MerchantStoreProfileConfig(
      name: _firstString(json, const ['name'], fallback.name),
      phone: _firstString(json, const ['phone'], fallback.phone),
      addressLine1: line1,
      city: city,
      region: region,
      country: country,
      postalCode: postalCode,
      addressDisplay: display,
      logoAssetId: _firstString(logo, const ['asset_id', 'assetId'], ''),
      logoUrl: _firstString(logo, const ['url', 'public_url', 'publicUrl'], ''),
      logoAlt: _firstString(logo, const ['alt'], fallback.logoAlt),
    );
  }

  Map<String, dynamic> toJson() {
    final logo = <String, dynamic>{
      'alt': logoAlt,
      'asset_id': logoAssetId.trim().isEmpty ? null : logoAssetId.trim(),
    };
    if (logoUrl.trim().isNotEmpty) {
      logo['url'] = logoUrl.trim();
    }

    return {
      'name': name,
      'phone': phone,
      'address': {
        'line1': addressLine1,
        'city': city,
        'region': region,
        'country': country,
        'postal_code': postalCode,
        'display': addressDisplay,
      },
      'logo': logo,
    };
  }
}

class MerchantPricingConfig {
  const MerchantPricingConfig({
    required this.currency,
    required this.deliveryFee,
    required this.deliveryServiceFee,
    required this.taxName,
    required this.taxRate,
  });

  final String currency;
  final double deliveryFee;
  final double deliveryServiceFee;
  final String taxName;
  final double taxRate;

  factory MerchantPricingConfig.fromJson(Map<String, dynamic> json) {
    final tax = _readMap(json['tax']);
    return MerchantPricingConfig(
      currency: _firstString(json, const ['currency'], 'CAD').toUpperCase(),
      deliveryFee: _firstDouble(json, const [
        'delivery_fee',
        'deliveryFee',
      ], 4.25),
      deliveryServiceFee: _firstDouble(json, const [
        'delivery_service_fee',
        'deliveryServiceFee',
      ], 2.02),
      taxName: _firstString(tax, const [
        'tax_name',
        'taxName',
        'name',
      ], 'GST/PST'),
      taxRate: _firstDouble(tax, const ['tax_rate', 'taxRate', 'rate'], 0.13),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'currency': currency,
      'delivery_fee': deliveryFee,
      'delivery_service_fee': deliveryServiceFee,
      'tax': {'tax_name': taxName, 'tax_rate': taxRate},
    };
  }
}

class MerchantPickupEtaConfig {
  const MerchantPickupEtaConfig({
    required this.minMinutes,
    required this.maxMinutes,
  });

  final int minMinutes;
  final int maxMinutes;

  String get display => '$minMinutes-$maxMinutes min';

  factory MerchantPickupEtaConfig.fromJson(Map<String, dynamic> json) {
    return MerchantPickupEtaConfig(
      minMinutes: _firstInt(json, const ['min_minutes', 'minMinutes'], 15),
      maxMinutes: _firstInt(json, const ['max_minutes', 'maxMinutes'], 20),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'min_minutes': minMinutes,
      'max_minutes': maxMinutes,
      'display': display,
    };
  }
}

class MerchantBusinessHoursConfig {
  const MerchantBusinessHoursConfig({
    required this.timezone,
    required this.weekly,
    required this.specialDates,
    required this.publicHolidays,
  });

  final String timezone;
  final Map<String, List<MerchantBusinessInterval>> weekly;
  final List<dynamic> specialDates;
  final Map<String, dynamic> publicHolidays;

  factory MerchantBusinessHoursConfig.defaults() {
    return const MerchantBusinessHoursConfig(
      timezone: 'America/Winnipeg',
      weekly: {
        'monday': [MerchantBusinessInterval(open: '09:00', close: '22:00')],
        'tuesday': [MerchantBusinessInterval(open: '09:00', close: '22:00')],
        'wednesday': [MerchantBusinessInterval(open: '09:00', close: '22:00')],
        'thursday': [MerchantBusinessInterval(open: '09:00', close: '22:00')],
        'friday': [MerchantBusinessInterval(open: '09:00', close: '23:00')],
        'saturday': [MerchantBusinessInterval(open: '09:00', close: '23:00')],
        'sunday': [MerchantBusinessInterval(open: '10:00', close: '21:00')],
      },
      specialDates: [],
      publicHolidays: {'closed_by_default': false, 'dates': []},
    );
  }

  factory MerchantBusinessHoursConfig.fromJson(Map<String, dynamic> json) {
    final fallback = MerchantBusinessHoursConfig.defaults();
    final weeklyJson = _readMap(json['weekly']);
    final weekly = <String, List<MerchantBusinessInterval>>{};

    for (final day in merchantWeekdayKeys) {
      final intervals = weeklyJson[day];
      if (intervals is List && intervals.isNotEmpty) {
        weekly[day] = intervals
            .whereType<Map>()
            .map(
              (item) => MerchantBusinessInterval.fromJson(
                item.map<String, dynamic>(
                  (key, value) => MapEntry(key.toString(), value),
                ),
              ),
            )
            .where(
              (interval) =>
                  interval.open.isNotEmpty && interval.close.isNotEmpty,
            )
            .toList(growable: false);
      } else {
        weekly[day] = const [];
      }
    }

    return MerchantBusinessHoursConfig(
      timezone: _firstString(json, const ['timezone'], fallback.timezone),
      weekly: weekly,
      specialDates: json['special_dates'] is List
          ? List<dynamic>.from(json['special_dates'] as List)
          : fallback.specialDates,
      publicHolidays: json['public_holidays'] is Map
          ? Map<String, dynamic>.from(json['public_holidays'] as Map)
          : fallback.publicHolidays,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'timezone': timezone,
      'weekly': {
        for (final day in merchantWeekdayKeys)
          day: (weekly[day] ?? const [])
              .map((interval) => interval.toJson())
              .toList(growable: false),
      },
      'special_dates': specialDates,
      'public_holidays': publicHolidays,
    };
  }
}

class MerchantBusinessInterval {
  const MerchantBusinessInterval({required this.open, required this.close});

  final String open;
  final String close;

  factory MerchantBusinessInterval.fromJson(Map<String, dynamic> json) {
    return MerchantBusinessInterval(
      open: _firstString(json, const ['open'], ''),
      close: _firstString(json, const ['close'], ''),
    );
  }

  Map<String, dynamic> toJson() {
    return {'open': open, 'close': close};
  }
}

const merchantWeekdayKeys = [
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
];

Map<String, dynamic> _readMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map<String, dynamic>(
      (key, value) => MapEntry(key.toString(), value),
    );
  }
  return <String, dynamic>{};
}

String _firstString(
  Map<String, dynamic> json,
  List<String> keys,
  String fallback,
) {
  for (final key in keys) {
    final value = json[key];
    if (value == null) continue;
    final text = value.toString().trim();
    if (text.isNotEmpty) return text;
  }
  return fallback;
}

double _firstDouble(
  Map<String, dynamic> json,
  List<String> keys,
  double fallback,
) {
  for (final key in keys) {
    final value = json[key];
    if (value is num) return value.toDouble();
    final parsed = double.tryParse(value?.toString() ?? '');
    if (parsed != null) return parsed;
  }
  return fallback;
}

int _firstInt(Map<String, dynamic> json, List<String> keys, int fallback) {
  for (final key in keys) {
    final value = json[key];
    if (value is int) return value;
    if (value is num) return value.round();
    final parsed = int.tryParse(value?.toString() ?? '');
    if (parsed != null) return parsed;
  }
  return fallback;
}

bool _firstBool(Map<String, dynamic> json, List<String> keys, bool fallback) {
  for (final key in keys) {
    final value = json[key];
    if (value is bool) return value;
    if (value is num) return value != 0;
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    if (['true', '1', 'yes'].contains(normalized)) return true;
    if (['false', '0', 'no'].contains(normalized)) return false;
  }
  return fallback;
}

bool _isCollectionTiming(String value) {
  return const {
    'before_fulfillment',
    'at_pickup',
    'after_service',
  }.contains(value);
}
