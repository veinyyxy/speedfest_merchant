import 'package:flutter/foundation.dart';

import '../Common/merchant_service_config.dart';
import '../Models/merchant_dining_table.dart';
import 'signed_api_client.dart';

class MerchantDiningTablesProvider with ChangeNotifier {
  bool _isLoading = false;
  bool _isSaving = false;
  String? _errorMessage;
  List<MerchantDiningTable> _tables = const [];

  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;
  List<MerchantDiningTable> get tables => _tables;

  Future<void> fetchTables({
    required SignedApiClient apiClient,
    required String token,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final rawResponse = await apiClient.get(
        MerchantServiceConfig.merchantDiningTablesPath,
        queryParameters: const {'include_inactive': true},
        token: token,
      );
      final response = Map<String, dynamic>.from(rawResponse as Map);
      _tables = _readTables(response['tables']);
    } on AppException catch (e) {
      _errorMessage = e.message;
    } catch (e) {
      _errorMessage = 'Unable to load dine-in tables: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> createTable({
    required SignedApiClient apiClient,
    required String token,
    required String tableNumber,
  }) {
    return _saveOne(
      apiClient: apiClient,
      token: token,
      path: MerchantServiceConfig.merchantDiningTableCreatePath,
      body: {'table_number': tableNumber},
    );
  }

  Future<int?> createTables({
    required SignedApiClient apiClient,
    required String token,
    required List<String> tableNumbers,
  }) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final rawResponse = await apiClient.post(
        MerchantServiceConfig.merchantDiningTableBatchCreatePath,
        {'table_numbers': tableNumbers},
        token: token,
      );
      final response = Map<String, dynamic>.from(rawResponse as Map);
      final created = _readTables(response['tables']);
      for (final table in created) {
        _replaceTable(table);
      }
      return created.length;
    } on AppException catch (e) {
      _errorMessage = e.message;
      return null;
    } catch (e) {
      _errorMessage = 'Unable to create dine-in tables: $e';
      return null;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<bool> updateTable({
    required SignedApiClient apiClient,
    required String token,
    required String tableId,
    String? tableNumber,
    bool? isActive,
  }) {
    return _saveOne(
      apiClient: apiClient,
      token: token,
      path: MerchantServiceConfig.merchantDiningTableUpdatePath,
      body: {
        'table_id': tableId,
        if (tableNumber != null) 'table_number': tableNumber,
        if (isActive != null) 'is_active': isActive,
      },
    );
  }

  Future<bool> rotateToken({
    required SignedApiClient apiClient,
    required String token,
    required String tableId,
  }) {
    return _saveOne(
      apiClient: apiClient,
      token: token,
      path: MerchantServiceConfig.merchantDiningTableRotateTokenPath,
      body: {'table_id': tableId},
    );
  }

  Future<bool> _saveOne({
    required SignedApiClient apiClient,
    required String token,
    required String path,
    required Map<String, dynamic> body,
  }) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final rawResponse = await apiClient.post(path, body, token: token);
      final response = Map<String, dynamic>.from(rawResponse as Map);
      final rawTable = response['table'];
      if (rawTable is! Map) {
        _errorMessage = 'The server response did not include a table.';
        return false;
      }
      _replaceTable(
        MerchantDiningTable.fromJson(Map<String, dynamic>.from(rawTable)),
      );
      return true;
    } on AppException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (e) {
      _errorMessage = 'Unable to save dine-in table: $e';
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  void _replaceTable(MerchantDiningTable table) {
    final next = [..._tables];
    final index = next.indexWhere((item) => item.id == table.id);
    if (index == -1) {
      next.add(table);
    } else {
      next[index] = table;
    }
    next.sort(_compareTables);
    _tables = List.unmodifiable(next);
  }
}

List<MerchantDiningTable> _readTables(dynamic value) {
  if (value is! List) return const [];
  final tables = value
      .whereType<Map>()
      .map(
        (item) => MerchantDiningTable.fromJson(
          item.map((key, value) => MapEntry(key.toString(), value)),
        ),
      )
      .toList(growable: false);
  return [...tables]..sort(_compareTables);
}

int _compareTables(MerchantDiningTable left, MerchantDiningTable right) {
  if (left.isActive != right.isActive) return left.isActive ? -1 : 1;
  return _naturalCompare(left.tableNumber, right.tableNumber);
}

int _naturalCompare(String left, String right) {
  final pattern = RegExp(r'(\d+)|(\D+)');
  final leftParts = pattern.allMatches(left.toLowerCase()).map((m) => m[0]!);
  final rightParts = pattern.allMatches(right.toLowerCase()).map((m) => m[0]!);
  final leftIterator = leftParts.iterator;
  final rightIterator = rightParts.iterator;
  while (leftIterator.moveNext() && rightIterator.moveNext()) {
    final leftPart = leftIterator.current;
    final rightPart = rightIterator.current;
    final leftNumber = int.tryParse(leftPart);
    final rightNumber = int.tryParse(rightPart);
    final comparison = leftNumber != null && rightNumber != null
        ? leftNumber.compareTo(rightNumber)
        : leftPart.compareTo(rightPart);
    if (comparison != 0) return comparison;
  }
  return left.length.compareTo(right.length);
}
