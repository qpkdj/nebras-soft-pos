import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:url_launcher/url_launcher.dart';

typedef DbRow = Map<String, dynamic>;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NebrasPosApp());
}

class CsvExportService {
  static String _escapeCsv(dynamic value) {
    final raw = (value ?? '').toString().replaceAll('"', '""');
    return '"$raw"';
  }

  static Uint8List _buildUtf8BomCsvBytes(List<List<dynamic>> rows) {
    final buffer = StringBuffer();
    for (final row in rows) {
      buffer.writeln(row.map(_escapeCsv).join(','));
    }
    final utf8Body = utf8.encode(buffer.toString());
    final out = Uint8List(3 + utf8Body.length);
    out[0] = 0xEF;
    out[1] = 0xBB;
    out[2] = 0xBF;
    out.setRange(3, out.length, utf8Body);
    return out;
  }

  static Future<void> exportAndShareCsv({
    required BuildContext context,
    required String fileBaseName,
    required List<List<dynamic>> rows,
  }) async {
    final bytes = _buildUtf8BomCsvBytes(rows);
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final fileName = '${fileBaseName}_$stamp.csv';

    try {
      final dbPath = await DatabaseHelper.instance.getDatabaseFilePath();
      final exportDir = Directory(p.join(p.dirname(dbPath), 'nebras_exports'));
      if (!await exportDir.exists()) {
        await exportDir.create(recursive: true);
      }
      final savedFile = File(p.join(exportDir.path, fileName));
      await savedFile.writeAsBytes(bytes, flush: true);
    } catch (_) {}

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم تجهيز ملف CSV: $fileName')),
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename: fileName,
    );
  }
}

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('nebras_soft_pos.db');
    return _database!;
  }

  Future<String> getDatabaseFilePath() async {
    final dbPath = await getDatabasesPath();
    return p.join(dbPath, 'nebras_soft_pos.db');
  }

  Future<void> closeDatabase() async {
    if (_database != null && _database!.isOpen) {
      await _database!.close();
      _database = null;
    }
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 5,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';
    const textNullable = 'TEXT';
    const intType = 'INTEGER NOT NULL';
    const doubleType = 'REAL NOT NULL';
    const doubleDefaultZero = 'REAL NOT NULL DEFAULT 0.0';

    await db.execute('''
      CREATE TABLE categories (
        id $idType,
        name $textType UNIQUE,
        color $textNullable
      )
    ''');

    await db.execute('''
      CREATE TABLE products (
        id $idType,
        barcode $textNullable UNIQUE,
        name $textType,
        category_id INTEGER,
        purchase_price $doubleDefaultZero,
        sale_price $doubleType,
        wholesale_price $doubleDefaultZero,
        special_price $doubleDefaultZero,
        stock_quantity $doubleDefaultZero,
        min_stock $doubleDefaultZero,
        image_path $textNullable,
        is_active $intType DEFAULT 1,
        FOREIGN KEY (category_id) REFERENCES categories (id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE contacts (
        id $idType,
        code $textNullable,
        barcode $textNullable,
        name $textType,
        phone $textNullable,
        address $textNullable,
        type $textType,
        price_tier $textType DEFAULT 'تجزئة',
        credit_limit $doubleDefaultZero,
        due_days $intType DEFAULT 30,
        balance $doubleDefaultZero
      )
    ''');

    await db.execute('''
      CREATE TABLE invoices (
        id $idType,
        invoice_number $textType UNIQUE,
        contact_id INTEGER,
        type $textType,
        date $textType,
        total_amount $doubleType,
        discount $doubleDefaultZero,
        tax $doubleDefaultZero,
        paid_amount $doubleDefaultZero,
        payment_method $textType,
        user_id INTEGER,
        FOREIGN KEY (contact_id) REFERENCES contacts (id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE invoice_items (
        id $idType,
        invoice_id $intType,
        product_id $intType,
        quantity $doubleType,
        price $doubleType,
        total $doubleType,
        FOREIGN KEY (invoice_id) REFERENCES invoices (id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE vouchers (
        id $idType,
        voucher_number $textType UNIQUE,
        contact_id INTEGER,
        type $textType,
        amount $doubleType,
        date $textType,
        notes $textNullable,
        user_id INTEGER,
        FOREIGN KEY (contact_id) REFERENCES contacts (id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE expenses (
        id $idType,
        title $textType,
        category $textType,
        amount $doubleType,
        date $textType,
        notes $textNullable
      )
    ''');

    await db.execute('''
      CREATE TABLE settings (
        id $idType,
        key $textType UNIQUE,
        value $textType
      )
    ''');

    final generatedDeviceId = 'NS-${DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase()}';
    await db.insert('categories', {'name': 'عام', 'color': '#1545B5'});
    await db.insert('settings', {'key': 'shop_name', 'value': 'نبراس SofT لنقاط البيع'});
    await db.insert('settings', {'key': 'shop_phone', 'value': ''});
    await db.insert('settings', {'key': 'shop_address', 'value': ''});
    await db.insert('settings', {'key': 'currency_name', 'value': 'YER'});
    await db.insert('settings', {'key': 'currency_symbol', 'value': 'ر.ي'});
    await db.insert('settings', {'key': 'tax_percentage', 'value': '0'});
    await db.insert('settings', {'key': 'printer_paper', 'value': '80mm'});
    await db.insert('settings', {'key': 'desktop_sync_host', 'value': ''});
    await db.insert('settings', {'key': 'admin_pin', 'value': ''});
    await db.insert('settings', {'key': 'receipt_footer', 'value': 'شكراً لتعاملكم معنا • Nebras SofT Pos'});
    await db.insert('settings', {'key': 'device_id', 'value': generatedDeviceId});
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE contacts ADD COLUMN code TEXT');
      await db.execute('ALTER TABLE contacts ADD COLUMN barcode TEXT');
      await db.execute('ALTER TABLE contacts ADD COLUMN address TEXT');
      await db.execute("ALTER TABLE contacts ADD COLUMN price_tier TEXT NOT NULL DEFAULT 'تجزئة'");
      await db.execute('ALTER TABLE contacts ADD COLUMN credit_limit REAL NOT NULL DEFAULT 0.0');
      await db.execute('ALTER TABLE contacts ADD COLUMN due_days INTEGER NOT NULL DEFAULT 30');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE products ADD COLUMN wholesale_price REAL NOT NULL DEFAULT 0.0');
      await db.execute('ALTER TABLE products ADD COLUMN special_price REAL NOT NULL DEFAULT 0.0');
    }
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS expenses (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          category TEXT NOT NULL,
          amount REAL NOT NULL,
          date TEXT NOT NULL,
          notes TEXT
        )
      ''');
    }
    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS categories (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE,
          color TEXT
        )
      ''');
      await db.insert(
        'categories',
        {'name': 'عام', 'color': '#1545B5'},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future<void> clearDemoTransactionsOnly() async {
    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.delete('invoice_items');
      await txn.delete('invoices');
      await txn.delete('vouchers');
      await txn.delete('expenses');
      await txn.update('contacts', {'balance': 0.0});
    });
  }

  Future<List<DbRow>> queryAllCategories() async {
    final db = await instance.database;
    return await db.query('categories', orderBy: 'id ASC');
  }

  Future<int> insertCategory(String name) async {
    final db = await instance.database;
    return await db.insert(
      'categories',
      {'name': name, 'color': '#0D7C66'},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<int> deleteCategory(int id) async {
    final db = await instance.database;
    return await db.delete('categories', where: 'id = ?', whereArgs: [id]);
  }

  Future getSettingsMap() async {
    final db = await instance.database;
    final rows = await db.query('settings');
    final map = <String, String>{
      'shop_name': 'نبراس SofT لنقاط البيع',
      'shop_phone': '',
      'shop_address': '',
      'currency_name': 'YER',
      'currency_symbol': 'ر.ي',
      'tax_percentage': '0',
      'printer_paper': '80mm',
      'desktop_sync_host': '',
      'admin_pin': '',
      'receipt_footer': 'شكراً لتعاملكم معنا • Nebras SofT Pos',
      'device_id': '',
    };
    for (final r in rows) {
      final k = r['key']?.toString();
      final v = r['value']?.toString() ?? '';
      if (k != null && k.isNotEmpty) {
        map[k] = v;
      }
    }
    if ((map['device_id'] ?? '').trim().isEmpty) {
      final newDevId = 'NS-${DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase()}';
      map['device_id'] = newDevId;
      await db.insert(
        'settings',
        {'key': 'device_id', 'value': newDevId},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    return map;
  }

  Future saveSettingsMap(Map<String, String> values) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      for (final entry in values.entries) {
        await txn.insert(
          'settings',
          {'key': entry.key, 'value': entry.value},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<int> insertExpense({
    required String title,
    required String category,
    required double amount,
    DateTime? date,
    String? notes,
  }) async {
    final db = await instance.database;
    final dt = date ?? DateTime.now();
    return await db.insert('expenses', {
      'title': title,
      'category': category,
      'amount': amount,
      'date': dt.toIso8601String(),
      'notes': notes,
    });
  }

  Future<int> deleteExpense(int id) async {
    final db = await instance.database;
    return await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> insertProduct(DbRow row) async {
    final db = await instance.database;
    return await db.insert(
      'products',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<DbRow>> queryAllProducts() async {
    final db = await instance.database;
    return await db.rawQuery('''
      SELECT p.*, COALESCE(c.name, 'عام') AS category_name
      FROM products p
      LEFT JOIN categories c ON c.id = p.category_id
      WHERE p.is_active = 1
      ORDER BY p.id DESC
    ''');
  }

  Future<int> updateProduct(DbRow row) async {
    final db = await instance.database;
    final int id = row['id'] as int;
    return await db.update('products', row, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> updateProductBarcode(int productId, String barcode) async {
    final db = await instance.database;
    return await db.update(
      'products',
      {'barcode': barcode.trim().isEmpty ? null : barcode.trim()},
      where: 'id = ?',
      whereArgs: [productId],
    );
  }

  Future<int> deleteProduct(int id) async {
    final db = await instance.database;
    return await db.update(
      'products',
      {'is_active': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<DbRow>> queryContactsByType(String type) async {
    final db = await instance.database;
    return await db.query(
      'contacts',
      where: 'type = ?',
      whereArgs: [type],
      orderBy: 'id DESC',
    );
  }

  Future<List<DbRow>> querySuppliers() async {
    return queryContactsByType('supplier');
  }

  Future<List<DbRow>> queryCustomers() async {
    return queryContactsByType('customer');
  }

  Future<int> insertContact(DbRow row) async {
    final db = await instance.database;
    return await db.insert('contacts', row);
  }

  Future<int> updateContact(DbRow row) async {
    final db = await instance.database;
    final int id = row['id'] as int;
    return await db.update('contacts', row, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> insertSupplier(String name, {String? phone}) async {
    return insertContact({
      'code': 'SUP-${DateTime.now().millisecondsSinceEpoch % 100000}',
      'name': name,
      'phone': phone,
      'type': 'supplier',
      'balance': 0.0,
    });
  }

  String _describeInvoiceType(String type, String method) {
    switch (type) {
      case 'sale':
        return 'فاتورة مبيعات ($method)';
      case 'purchase':
        return 'فاتورة مشتريات ($method)';
      case 'sale_return':
        return 'مرتجع مبيعات ($method)';
      case 'purchase_return':
        return 'مرتجع مشتريات ($method)';
      default:
        return 'حركة فاتورة ($method)';
    }
  }

  Future getContactStatementData(int contactId) async {
    final db = await instance.database;
    final contactRows = await db.query(
      'contacts',
      where: 'id = ?',
      whereArgs: [contactId],
      limit: 1,
    );
    if (contactRows.isEmpty) {
      return <String, dynamic>{};
    }

    final contact = contactRows.first;
    final invoices = await db.query(
      'invoices',
      where: 'contact_id = ?',
      whereArgs: [contactId],
      orderBy: 'date DESC, id DESC',
    );
    final vouchers = await db.query(
      'vouchers',
      where: 'contact_id = ?',
      whereArgs: [contactId],
      orderBy: 'date DESC, id DESC',
    );

    final List<DbRow> movements = [];

    for (final inv in invoices) {
      final invType = (inv['type'] ?? '').toString();
      final method = (inv['payment_method'] ?? '').toString();
      final total = (inv['total_amount'] as num?)?.toDouble() ?? 0.0;
      movements.add({
        'date': (inv['date'] ?? '').toString(),
        'reference': (inv['invoice_number'] ?? '').toString(),
        'description': _describeInvoiceType(invType, method),
        'amount': total,
        'kind': invType,
      });
    }

    for (final v in vouchers) {
      final isReceipt = v['type'] == 'receipt';
      final amt = (v['amount'] as num?)?.toDouble() ?? 0.0;
      final notes = (v['notes'] ?? '').toString();
      movements.add({
        'date': (v['date'] ?? '').toString(),
        'reference': (v['voucher_number'] ?? '').toString(),
        'description': isReceipt
            ? 'سند قبض${notes.isNotEmpty ? ' - $notes' : ''}'
            : 'سند صرف${notes.isNotEmpty ? ' - $notes' : ''}',
        'amount': amt,
        'kind': isReceipt ? 'receipt' : 'payment',
      });
    }

    movements.sort((a, b) => (b['date'] ?? '').toString().compareTo((a['date'] ?? '').toString()));

    return {
      'contact': contact,
      'movements': movements,
    };
  }

  Future<String> createVoucher({
    required int contactId,
    required String type,
    required double amount,
    String? notes,
  }) async {
    final db = await instance.database;
    final now = DateTime.now();
    final prefix = type == 'receipt' ? 'RCV' : 'PAY';
    final voucherNumber = '$prefix-${now.millisecondsSinceEpoch}';

    await db.transaction((txn) async {
      await txn.insert('vouchers', {
        'voucher_number': voucherNumber,
        'contact_id': contactId,
        'type': type,
        'amount': amount,
        'date': now.toIso8601String(),
        'notes': notes,
        'user_id': 1,
      });

      final rows = await txn.query(
        'contacts',
        columns: ['balance'],
        where: 'id = ?',
        whereArgs: [contactId],
      );
      if (rows.isNotEmpty) {
        final oldBalance = (rows.first['balance'] as num?)?.toDouble() ?? 0.0;
        final nextBalance = (oldBalance - amount) < 0 ? 0.0 : (oldBalance - amount);
        await txn.update(
          'contacts',
          {'balance': nextBalance},
          where: 'id = ?',
          whereArgs: [contactId],
        );
      }
    });

    return voucherNumber;
  }

  Future<String> createSaleInvoice({
    required List<DbRow> cartItems,
    required double totalAmount,
    double discount = 0.0,
    String paymentMethod = 'نقدي',
    int? customerId,
  }) async {
    final db = await instance.database;
    final now = DateTime.now();
    final invoiceNumber = 'INV-${now.millisecondsSinceEpoch}';
    final netTotal = (totalAmount - discount) < 0 ? 0.0 : (totalAmount - discount);
    final paidAmount = paymentMethod == 'نقدي' ? netTotal : 0.0;

    await db.transaction((txn) async {
      final invoiceId = await txn.insert('invoices', {
        'invoice_number': invoiceNumber,
        'contact_id': customerId,
        'type': 'sale',
        'date': now.toIso8601String(),
        'total_amount': netTotal,
        'discount': discount,
        'tax': 0.0,
        'paid_amount': paidAmount,
        'payment_method': paymentMethod,
        'user_id': 1,
      });

      for (final item in cartItems) {
        final int productId = item['product_id'] as int;
        final double qty = (item['quantity'] as num).toDouble();
        final double price = (item['price'] as num).toDouble();
        final double lineTotal = qty * price;
        final double currentStock = (item['stock_quantity'] as num).toDouble();
        final double newStock = (currentStock - qty) < 0 ? 0.0 : (currentStock - qty);

        await txn.insert('invoice_items', {
          'invoice_id': invoiceId,
          'product_id': productId,
          'quantity': qty,
          'price': price,
          'total': lineTotal,
        });

        await txn.update(
          'products',
          {'stock_quantity': newStock},
          where: 'id = ?',
          whereArgs: [productId],
        );
      }

      if (customerId != null && paymentMethod == 'آجل' && netTotal > 0) {
        final rows = await txn.query(
          'contacts',
          columns: ['balance'],
          where: 'id = ?',
          whereArgs: [customerId],
        );
        if (rows.isNotEmpty) {
          final oldBalance = (rows.first['balance'] as num?)?.toDouble() ?? 0.0;
          await txn.update(
            'contacts',
            {'balance': oldBalance + netTotal},
            where: 'id = ?',
            whereArgs: [customerId],
          );
        }
      }
    });

    return invoiceNumber;
  }

  Future<String> createPurchaseInvoice({
    required List<DbRow> purchaseItems,
    required double totalAmount,
    required double discount,
    required double paidAmount,
    required String paymentMethod,
    int? supplierId,
  }) async {
    final db = await instance.database;
    final now = DateTime.now();
    final invoiceNumber = 'PUR-${now.millisecondsSinceEpoch}';
    final netTotal = (totalAmount - discount) < 0 ? 0.0 : (totalAmount - discount);

    await db.transaction((txn) async {
      final invoiceId = await txn.insert('invoices', {
        'invoice_number': invoiceNumber,
        'contact_id': supplierId,
        'type': 'purchase',
        'date': now.toIso8601String(),
        'total_amount': netTotal,
        'discount': discount,
        'tax': 0.0,
        'paid_amount': paidAmount,
        'payment_method': paymentMethod,
        'user_id': 1,
      });

      for (final item in purchaseItems) {
        final int productId = item['product_id'] as int;
        final double qty = (item['quantity'] as num).toDouble();
        final double costPrice = (item['price'] as num).toDouble();
        final double lineTotal = qty * costPrice;
        final double currentStock = (item['stock_quantity'] as num).toDouble();
        final double updatedStock = currentStock + qty;

        await txn.insert('invoice_items', {
          'invoice_id': invoiceId,
          'product_id': productId,
          'quantity': qty,
          'price': costPrice,
          'total': lineTotal,
        });

        await txn.update(
          'products',
          {
            'stock_quantity': updatedStock,
            'purchase_price': costPrice,
          },
          where: 'id = ?',
          whereArgs: [productId],
        );
      }

      if (supplierId != null) {
        final remaining = netTotal - paidAmount;
        if (remaining > 0) {
          final rows = await txn.query(
            'contacts',
            columns: ['balance'],
            where: 'id = ?',
            whereArgs: [supplierId],
          );
          if (rows.isNotEmpty) {
            final oldBalance = (rows.first['balance'] as num?)?.toDouble() ?? 0.0;
            await txn.update(
              'contacts',
              {'balance': oldBalance + remaining},
              where: 'id = ?',
              whereArgs: [supplierId],
            );
          }
        }
      }
    });

    return invoiceNumber;
  }

  Future<String> createReturnFromInvoice({
    required String originalInvoiceNumber,
    required List<DbRow> returnItems,
  }) async {
    final db = await instance.database;
    final details = await getInvoiceDetailsByNumber(originalInvoiceNumber);
    if (details.isEmpty) {
      throw Exception('الفاتورة الأصلية غير موجودة');
    }

    final originalInv = details['invoice'] as DbRow;
    final String origType = (originalInv['type'] ?? '').toString();
    final bool isSaleReturn = origType == 'sale' || origType == 'sale_return';
    final String returnType = isSaleReturn ? 'sale_return' : 'purchase_return';
    final String paymentMethod = (originalInv['payment_method'] ?? 'نقدي').toString();
    final int? contactId = originalInv['contact_id'] as int?;

    double returnTotal = 0.0;
    for (final item in returnItems) {
      final double qty = (item['return_qty'] as num?)?.toDouble() ?? 0.0;
      final double price = (item['price'] as num?)?.toDouble() ?? 0.0;
      if (qty > 0) {
        returnTotal += qty * price;
      }
    }

    if (returnTotal <= 0) {
      throw Exception('يرجى تحديد كمية مرتجعة أكبر من صفر');
    }

    final now = DateTime.now();
    final returnNumber = 'RET-${now.millisecondsSinceEpoch}';

    await db.transaction((txn) async {
      final returnInvId = await txn.insert('invoices', {
        'invoice_number': returnNumber,
        'contact_id': contactId,
        'type': returnType,
        'date': now.toIso8601String(),
        'total_amount': returnTotal,
        'discount': 0.0,
        'tax': 0.0,
        'paid_amount': paymentMethod == 'نقدي' ? returnTotal : 0.0,
        'payment_method': paymentMethod,
        'user_id': 1,
      });

      for (final item in returnItems) {
        final int productId = item['product_id'] as int;
        final double retQty = (item['return_qty'] as num?)?.toDouble() ?? 0.0;
        final double price = (item['price'] as num?)?.toDouble() ?? 0.0;
        if (retQty <= 0) continue;

        await txn.insert('invoice_items', {
          'invoice_id': returnInvId,
          'product_id': productId,
          'quantity': retQty,
          'price': price,
          'total': retQty * price,
        });

        final prodRows = await txn.query(
          'products',
          columns: ['stock_quantity'],
          where: 'id = ?',
          whereArgs: [productId],
        );
        if (prodRows.isNotEmpty) {
          final currentStock = (prodRows.first['stock_quantity'] as num?)?.toDouble() ?? 0.0;
          final nextStock = isSaleReturn
              ? (currentStock + retQty)
              : ((currentStock - retQty) < 0 ? 0.0 : (currentStock - retQty));
          await txn.update(
            'products',
            {'stock_quantity': nextStock},
            where: 'id = ?',
            whereArgs: [productId],
          );
        }
      }

      if (contactId != null) {
        final contactRows = await txn.query(
          'contacts',
          columns: ['balance'],
          where: 'id = ?',
          whereArgs: [contactId],
        );
        if (contactRows.isNotEmpty) {
          final oldBalance = (contactRows.first['balance'] as num?)?.toDouble() ?? 0.0;
          final nextBalance = (oldBalance - returnTotal) < 0 ? 0.0 : (oldBalance - returnTotal);
          await txn.update(
            'contacts',
            {'balance': nextBalance},
            where: 'id = ?',
            whereArgs: [contactId],
          );
        }
      }
    });

    return returnNumber;
  }

  Future<DbRow> getInvoiceDetailsByNumber(String invoiceNumber) async {
    final db = await instance.database;
    final invRows = await db.rawQuery('''
      SELECT inv.*, c.name AS contact_name
      FROM invoices inv
      LEFT JOIN contacts c ON c.id = inv.contact_id
      WHERE inv.invoice_number = ?
      LIMIT 1
    ''', [invoiceNumber]);

    if (invRows.isEmpty) {
      return <String, dynamic>{};
    }

    final inv = invRows.first;
    final int invId = inv['id'] as int;

    final itemRows = await db.rawQuery('''
      SELECT ii.*, COALESCE(p.name, 'صنف') AS name
      FROM invoice_items ii
      LEFT JOIN products p ON p.id = ii.product_id
      WHERE ii.invoice_id = ?
    ''', [invId]);

    return {
      'invoice': inv,
      'items': itemRows,
    };
  }

  bool _isWithinRange(String rawDate, DateTime? start, DateTime? end) {
    if (start == null && end == null) return true;
    final parsed = DateTime.tryParse(rawDate);
    if (parsed == null) return false;
    final d = DateTime(parsed.year, parsed.month, parsed.day);
    if (start != null) {
      final s = DateTime(start.year, start.month, start.day);
      if (d.isBefore(s)) return false;
    }
    if (end != null) {
      final e = DateTime(end.year, end.month, end.day);
      if (d.isAfter(e)) return false;
    }
    return true;
  }

  Future getCashboxSummary({DateTime? startDate, DateTime? endDate}) async {
    final db = await instance.database;
    final allInvoices = await db.query('invoices', orderBy: 'id DESC');
    final allVouchers = await db.query('vouchers', orderBy: 'id DESC');
    final allExpenses = await db.query('expenses', orderBy: 'id DESC');

    final filteredInvoices = allInvoices.where((inv) {
      return _isWithinRange((inv['date'] ?? '').toString(), startDate, endDate);
    }).toList();
    final filteredVouchers = allVouchers.where((v) {
      return _isWithinRange((v['date'] ?? '').toString(), startDate, endDate);
    }).toList();
    final filteredExpenses = allExpenses.where((e) {
      return _isWithinRange((e['date'] ?? '').toString(), startDate, endDate);
    }).toList();

    double cashSales = 0.0;
    double cashSaleReturns = 0.0;
    double cashPurchases = 0.0;
    double cashPurchaseReturns = 0.0;

    for (final inv in filteredInvoices) {
      final method = (inv['payment_method'] ?? '').toString();
      if (method != 'نقدي') continue;
      final t = (inv['type'] ?? '').toString();
      final amt = (inv['total_amount'] as num?)?.toDouble() ?? 0.0;
      if (t == 'sale') {
        cashSales += amt;
      } else if (t == 'sale_return') {
        cashSaleReturns += amt;
      } else if (t == 'purchase') {
        cashPurchases += amt;
      } else if (t == 'purchase_return') {
        cashPurchaseReturns += amt;
      }
    }

    double receiptsTotal = 0.0;
    double paymentsTotal = 0.0;
    for (final v in filteredVouchers) {
      final amt = (v['amount'] as num?)?.toDouble() ?? 0.0;
      if (v['type'] == 'receipt') {
        receiptsTotal += amt;
      } else {
        paymentsTotal += amt;
      }
    }

    double expensesTotal = 0.0;
    for (final e in filteredExpenses) {
      expensesTotal += (e['amount'] as num?)?.toDouble() ?? 0.0;
    }

    final netCashIn = (cashSales - cashSaleReturns) + cashPurchaseReturns + receiptsTotal;
    final netCashOut = cashPurchases + paymentsTotal + expensesTotal;
    final cashInBox = netCashIn - netCashOut;

    final List<DbRow> entries = [];
    for (final inv in filteredInvoices) {
      if ((inv['payment_method'] ?? '').toString() != 'نقدي') continue;
      final t = (inv['type'] ?? '').toString();
      final amt = (inv['total_amount'] as num?)?.toDouble() ?? 0.0;
      final isIncoming = t == 'sale' || t == 'purchase_return';
      entries.add({
        'date': (inv['date'] ?? '').toString(),
        'title': '${_describeInvoiceType(t, 'نقدي')} • ${inv['invoice_number'] ?? ''}',
        'amount': amt,
        'incoming': isIncoming,
      });
    }
    for (final v in filteredVouchers) {
      final isReceipt = v['type'] == 'receipt';
      entries.add({
        'date': (v['date'] ?? '').toString(),
        'title': '${isReceipt ? 'سند قبض' : 'سند صرف'} • ${v['voucher_number'] ?? ''}',
        'amount': (v['amount'] as num?)?.toDouble() ?? 0.0,
        'incoming': isReceipt,
      });
    }
    for (final e in filteredExpenses) {
      entries.add({
        'date': (e['date'] ?? '').toString(),
        'title': 'مصروف: ${e['title'] ?? ''}',
        'amount': (e['amount'] as num?)?.toDouble() ?? 0.0,
        'incoming': false,
      });
    }
    entries.sort((a, b) => (b['date'] ?? '').toString().compareTo((a['date'] ?? '').toString()));

    return {
      'cashSales': cashSales,
      'receiptsTotal': receiptsTotal,
      'paymentsTotal': paymentsTotal,
      'expensesTotal': expensesTotal,
      'cashInBox': cashInBox,
      'entries': entries,
    };
  }

  Future getFinancialSummary({DateTime? startDate, DateTime? endDate}) async {
    final db = await instance.database;

    final allInvoices = await db.query('invoices', orderBy: 'id DESC');
    final allExpenses = await db.query('expenses', orderBy: 'id DESC');
    final lowStockProducts = await db.rawQuery(
      'SELECT * FROM products WHERE is_active = 1 AND stock_quantity <= min_stock ORDER BY stock_quantity ASC',
    );

    final filteredInvoices = allInvoices.where((inv) {
      return _isWithinRange((inv['date'] ?? '').toString(), startDate, endDate);
    }).toList();

    final filteredExpenses = allExpenses.where((exp) {
      return _isWithinRange((exp['date'] ?? '').toString(), startDate, endDate);
    }).toList();

    double rawSales = 0.0;
    double saleReturns = 0.0;
    double rawPurchases = 0.0;
    double purchaseReturns = 0.0;
    final List<int> saleInvoiceIds = [];

    for (final inv in filteredInvoices) {
      final t = (inv['type'] ?? '').toString();
      final amt = (inv['total_amount'] as num?)?.toDouble() ?? 0.0;
      if (t == 'sale') {
        rawSales += amt;
        final id = inv['id'] as int?;
        if (id != null) saleInvoiceIds.add(id);
      } else if (t == 'sale_return') {
        saleReturns += amt;
      } else if (t == 'purchase') {
        rawPurchases += amt;
      } else if (t == 'purchase_return') {
        purchaseReturns += amt;
      }
    }

    double totalCogs = 0.0;
    if (saleInvoiceIds.isNotEmpty) {
      final placeholders = List.filled(saleInvoiceIds.length, '?').join(',');
      final cogsRows = await db.rawQuery('''
        SELECT COALESCE(SUM(ii.quantity * p.purchase_price), 0) AS cost
        FROM invoice_items ii
        LEFT JOIN products p ON p.id = ii.product_id
        WHERE ii.invoice_id IN ($placeholders)
      ''', saleInvoiceIds);
      totalCogs = (cogsRows.first['cost'] as num?)?.toDouble() ?? 0.0;
    }

    double totalExpenses = 0.0;
    for (final exp in filteredExpenses) {
      totalExpenses += (exp['amount'] as num?)?.toDouble() ?? 0.0;
    }

    final netSales = (rawSales - saleReturns) < 0 ? 0.0 : (rawSales - saleReturns);
    final netPurchases = (rawPurchases - purchaseReturns) < 0 ? 0.0 : (rawPurchases - purchaseReturns);
    final grossProfit = netSales - totalCogs;
    final realNetProfit = grossProfit - totalExpenses;

    return {
      'totalSales': netSales,
      'totalPurchases': netPurchases,
      'totalCogs': totalCogs,
      'totalExpenses': totalExpenses,
      'grossProfit': grossProfit,
      'realNetProfit': realNetProfit,
      'recentInvoices': filteredInvoices.take(25).toList(),
      'expenses': filteredExpenses.take(25).toList(),
      'lowStockProducts': lowStockProducts,
    };
  }
}

class BarcodeScannerScreen extends StatefulWidget {
  final String title;

  const BarcodeScannerScreen({
    super.key,
    this.title = 'مسح الباركود بالكاميرا',
  });

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
    torchEnabled: false,
  );
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue?.trim();
      if (raw != null && raw.isNotEmpty) {
        _handled = true;
        Navigator.of(context).pop(raw);
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title,
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF0F2C7E),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: 'تشغيل/إطفاء الفلاش',
            icon: const Icon(Icons.flash_on),
            onPressed: () async {
              try {
                await _controller.toggleTorch();
              } catch (_) {}
            },
          ),
          IconButton(
            tooltip: 'تبديل الكاميرا',
            icon: const Icon(Icons.cameraswitch),
            onPressed: () async {
              try {
                await _controller.switchCamera();
              } catch (_) {}
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.videocam_off, size: 52, color: Colors.redAccent),
                      const SizedBox(height: 12),
                      const Text(
                        'تعذر تشغيل الكاميرا، تأكد من منح إذن الكاميرا للتطبيق أو أن الكاميرا غير مشغلة بتطبيق آخر.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: () async {
                          try {
                            await _controller.stop();
                            await _controller.start();
                          } catch (_) {}
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('إعادة تشغيل الكاميرا'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          Center(
            child: Container(
              width: 260,
              height: 160,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.greenAccent, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            bottom: 32,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'وجّه الكاميرا نحو الباركود ليتم التقاطه تلقائياً',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ThermalPdfService {
  static String generateUniqueBarcode(int productId) {
    final suffix = DateTime.now().millisecondsSinceEpoch % 1000000;
    final idPart = productId.toString().padLeft(3, '0');
    return '200$idPart$suffix';
  }

  static Future<Uint8List> buildBarcodeLabelsPdf({
    required DbRow product,
    required String barcodeValue,
    required int copies,
    required bool isA4Sheet,
    required Map<String, String> settings,
  }) async {
    final fontRegular = await PdfGoogleFonts.cairoRegular();
    final fontBold = await PdfGoogleFonts.cairoBold();

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: fontRegular,
        bold: fontBold,
      ),
    );

    final String shopName = (settings['shop_name'] ?? 'نبراس SofT').trim();
    final String currency = (settings['currency_symbol'] ?? 'ر.ي').trim();
    final String productName = (product['name'] ?? 'صنف').toString();
    final double salePrice = (product['sale_price'] as num?)?.toDouble() ?? 0.0;
    final int safeCopies = copies < 1 ? 1 : (copies > 60 ? 60 : copies);

    pw.Widget buildSingleLabelWidget({
      required double width,
      required double height,
      required double barHeight,
    }) {
      return pw.Container(
        width: width,
        height: height,
        padding: const pw.EdgeInsets.all(5),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(width: 0.6, color: PdfColors.grey600),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Text(
                shopName,
                maxLines: 1,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                productName,
                maxLines: 1,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                '${salePrice.toStringAsFixed(2)} $currency',
                maxLines: 1,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 2),
              pw.BarcodeWidget(
                barcode: pw.Barcode.code128(),
                data: barcodeValue,
                width: width - 12,
                height: barHeight,
                drawText: false,
              ),
              pw.SizedBox(height: 1.5),
              pw.Text(
                barcodeValue,
                maxLines: 1,
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 7),
              ),
            ],
          ),
        ),
      );
    }

    if (isA4Sheet) {
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(14),
          build: (pw.Context ctx) {
            return [
              pw.Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(
                  safeCopies,
                  (_) => buildSingleLabelWidget(
                    width: 175,
                    height: 92,
                    barHeight: 28,
                  ),
                ),
              ),
            ];
          },
        ),
      );
    } else {
      for (int i = 0; i < safeCopies; i++) {
        pdf.addPage(
          pw.Page(
            pageFormat: const PdfPageFormat(58 * PdfPageFormat.mm, 40 * PdfPageFormat.mm),
            margin: const pw.EdgeInsets.all(4),
            build: (pw.Context ctx) {
              return buildSingleLabelWidget(
                width: 54 * PdfPageFormat.mm,
                height: 36 * PdfPageFormat.mm,
                barHeight: 30,
              );
            },
          ),
        );
      }
    }

    return pdf.save();
  }

  static Future<void> showBarcodeGeneratorPrinterDialog(
    BuildContext context,
    DbRow product, {
    VoidCallback? onBarcodeSaved,
  }) async {
    final settings = await DatabaseHelper.instance.getSettingsMap() as Map<String, String>;
    if (!context.mounted) return;

    final int productId = product['id'] as int;
    String initialCode = (product['barcode'] ?? '').toString().trim();
    if (initialCode.isEmpty) {
      initialCode = generateUniqueBarcode(productId);
    }

    final barcodeCtrl = TextEditingController(text: initialCode);
    int copies = 4;
    bool isA4Sheet = (settings['printer_paper'] ?? '80mm') != '58mm';
    bool busy = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> runAction({required bool shareOnly}) async {
            final code = barcodeCtrl.text.trim();
            if (code.isEmpty || busy) return;
            setDialogState(() => busy = true);
            try {
              await DatabaseHelper.instance.updateProductBarcode(productId, code);
              onBarcodeSaved?.call();
              final bytes = await buildBarcodeLabelsPdf(
                product: product,
                barcodeValue: code,
                copies: copies,
                isA4Sheet: isA4Sheet,
                settings: settings,
              );
              if (ctx.mounted) Navigator.of(ctx).pop();
              if (shareOnly) {
                await Printing.sharePdf(
                  bytes: bytes,
                  filename: 'barcodes_${code}_x$copies.pdf',
                );
              } else {
                await Printing.layoutPdf(
                  name: 'barcodes_${code}_x$copies.pdf',
                  onLayout: (_) async => bytes,
                );
              }
            } finally {
              if (ctx.mounted) setDialogState(() => busy = false);
            }
          }

          return AlertDialog(
            title: Text(
              'توليد وطباعة باركود: ${product['name'] ?? ''}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: barcodeCtrl,
                          decoration: const InputDecoration(
                            labelText: 'رقم الباركود',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton.filled(
                        tooltip: 'توليد باركود جديد',
                        style: IconButton.styleFrom(backgroundColor: const Color(0xFF0D7C66)),
                        onPressed: busy
                            ? null
                            : () {
                                setDialogState(() {
                                  barcodeCtrl.text = generateUniqueBarcode(productId);
                                });
                              },
                        icon: const Icon(Icons.autorenew),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('نوع الورق / الملصق:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('ورقة A4 شبكة')),
                      ButtonSegment(value: false, label: Text('حراري 58mm')),
                    ],
                    selected: {isA4Sheet},
                    onSelectionChanged: (sel) {
                      setDialogState(() => isA4Sheet = sel.first);
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('عدد الملصقات:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      Row(
                        children: [
                          IconButton(
                            onPressed: busy || copies <= 1
                                ? null
                                : () => setDialogState(() => copies--),
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          Text('$copies', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          IconButton(
                            onPressed: busy || copies >= 48
                                ? null
                                : () => setDialogState(() => copies++),
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 6,
                    children: [1, 4, 8, 12, 20].map((preset) {
                      return ChoiceChip(
                        label: Text('$preset'),
                        selected: copies == preset,
                        onSelected: (_) => setDialogState(() => copies = preset),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.of(ctx).pop(),
                child: const Text('إلغاء'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : () => runAction(shareOnly: true),
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('PDF'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0369A1)),
                onPressed: busy ? null : () => runAction(shareOnly: false),
                icon: const Icon(Icons.print),
                label: Text(busy ? 'جاري التوليد...' : 'طباعة'),
              ),
            ],
          );
        },
      ),
    );
  }

  static Future<void> printProductBarcodeLabel(
    BuildContext context,
    DbRow product, {
    VoidCallback? onBarcodeSaved,
  }) async {
    await showBarcodeGeneratorPrinterDialog(
      context,
      product,
      onBarcodeSaved: onBarcodeSaved,
    );
  }

  static String _invoiceTitleArabic(String type) {
    switch (type) {
      case 'sale':
        return 'فاتورة مبيعات';
      case 'purchase':
        return 'فاتورة مشتريات';
      case 'sale_return':
        return 'إشعار مرتجع مبيعات';
      case 'purchase_return':
        return 'إشعار مرتجع مشتريات';
      default:
        return 'فاتورة';
    }
  }

  static Future<Uint8List> buildReceiptPdf({
    required DbRow invoice,
    required List<DbRow> items,
    required Map<String, String> settings,
    bool? is80mm,
  }) async {
    final fontRegular = await PdfGoogleFonts.cairoRegular();
    final fontBold = await PdfGoogleFonts.cairoBold();

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: fontRegular,
        bold: fontBold,
      ),
    );

    final bool resolved80mm = is80mm ?? ((settings['printer_paper'] ?? '80mm') != '58mm');
    final pageFormat = resolved80mm ? PdfPageFormat.roll80 : PdfPageFormat.roll57;
    final String invType = (invoice['type'] ?? 'sale').toString();
    final bool isCustomerSide = invType == 'sale' || invType == 'sale_return';
    final String shopName = (settings['shop_name'] ?? 'نبراس SofT لنقاط البيع').trim();
    final String shopPhone = (settings['shop_phone'] ?? '').trim();
    final String shopAddress = (settings['shop_address'] ?? '').trim();
    final String currency = (settings['currency_symbol'] ?? 'ر.ي').trim();
    final String footerText = (settings['receipt_footer'] ?? 'شكراً لتعاملكم معنا • Nebras SofT Pos').trim();

    final String invNum = (invoice['invoice_number'] ?? '').toString();
    final String rawDate = (invoice['date'] ?? '').toString();
    final String formattedDate = rawDate.replaceFirst('T', ' ').split('.').first;
    final String contactName = (invoice['contact_name'] ?? (isCustomerSide ? 'عميل نقدي عام' : 'مورد نقدي عام')).toString();
    final String payMethod = (invoice['payment_method'] ?? 'نقدي').toString();
    final double netTotal = (invoice['total_amount'] as num?)?.toDouble() ?? 0.0;
    final double discount = (invoice['discount'] as num?)?.toDouble() ?? 0.0;
    final double subTotal = netTotal + discount;

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        build: (pw.Context ctx) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Text(
                  shopName.isEmpty ? 'Nebras SofT Pos' : shopName,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(fontSize: 13.5, fontWeight: pw.FontWeight.bold),
                ),
                if (shopPhone.isNotEmpty)
                  pw.Text(
                    'هاتف: $shopPhone',
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                if (shopAddress.isNotEmpty)
                  pw.Text(
                    shopAddress,
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                pw.SizedBox(height: 3),
                pw.Text(
                  _invoiceTitleArabic(invType),
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 4),
                pw.Divider(thickness: 0.8),
                pw.Text('رقم المستند: $invNum', style: const pw.TextStyle(fontSize: 8.5)),
                pw.Text('التاريخ: $formattedDate', style: const pw.TextStyle(fontSize: 8.5)),
                pw.Text(
                  '${isCustomerSide ? 'العميل' : 'المورد'}: $contactName',
                  style: const pw.TextStyle(fontSize: 8.5),
                ),
                pw.Text('طريقة الدفع: $payMethod', style: const pw.TextStyle(fontSize: 8.5)),
                pw.Divider(thickness: 0.8),
                pw.Row(
                  children: [
                    pw.Expanded(
                      flex: 4,
                      child: pw.Text('الصنف', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                    ),
                    pw.Expanded(
                      flex: 2,
                      child: pw.Text(
                        'الكمية',
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                    pw.Expanded(
                      flex: 2,
                      child: pw.Text(
                        'السعر',
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                    pw.Expanded(
                      flex: 2,
                      child: pw.Text(
                        'الإجمالي',
                        textAlign: pw.TextAlign.left,
                        style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                pw.Divider(thickness: 0.5),
                ...items.map((item) {
                  final name = (item['name'] ?? '').toString();
                  final qty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
                  final price = (item['price'] as num?)?.toDouble() ?? 0.0;
                  final total = (item['total'] as num?)?.toDouble() ?? (qty * price);

                  return pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 2),
                    child: pw.Row(
                      children: [
                        pw.Expanded(
                          flex: 4,
                          child: pw.Text(name, style: const pw.TextStyle(fontSize: 8)),
                        ),
                        pw.Expanded(
                          flex: 2,
                          child: pw.Text(
                            qty.toString(),
                            textAlign: pw.TextAlign.center,
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                        ),
                        pw.Expanded(
                          flex: 2,
                          child: pw.Text(
                            price.toStringAsFixed(1),
                            textAlign: pw.TextAlign.center,
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                        ),
                        pw.Expanded(
                          flex: 2,
                          child: pw.Text(
                            total.toStringAsFixed(1),
                            textAlign: pw.TextAlign.left,
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                pw.Divider(thickness: 0.8),
                if (discount > 0) ...[
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('الإجمالي قبل الخصم:', style: const pw.TextStyle(fontSize: 8.5)),
                      pw.Text(
                        '${subTotal.toStringAsFixed(2)} $currency',
                        style: const pw.TextStyle(fontSize: 8.5),
                      ),
                    ],
                  ),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('الخصم:', style: const pw.TextStyle(fontSize: 8.5)),
                      pw.Text(
                        '${discount.toStringAsFixed(2)} $currency',
                        style: const pw.TextStyle(fontSize: 8.5),
                      ),
                    ],
                  ),
                ],
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'الصافي:',
                      style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text(
                      '${netTotal.toStringAsFixed(2)} $currency',
                      style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
                pw.SizedBox(height: 8),
                pw.Divider(thickness: 0.5),
                pw.Text(
                  footerText.isEmpty ? 'شكراً لتعاملكم معنا • Nebras SofT Pos' : footerText,
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ],
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  static Future<Uint8List> buildContactStatementPdf({
    required DbRow contact,
    required List<DbRow> movements,
    required Map<String, String> settings,
  }) async {
    final fontRegular = await PdfGoogleFonts.cairoRegular();
    final fontBold = await PdfGoogleFonts.cairoBold();

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: fontRegular,
        bold: fontBold,
      ),
    );

    final bool isCustomer = contact['type'] == 'customer';
    final String shopName = (settings['shop_name'] ?? 'نبراس SofT لنقاط البيع').trim();
    final String shopPhone = (settings['shop_phone'] ?? '').trim();
    final String shopAddress = (settings['shop_address'] ?? '').trim();
    final String currency = (settings['currency_symbol'] ?? 'ر.ي').trim();

    final String contactName = (contact['name'] ?? '').toString();
    final String contactPhone = (contact['phone'] ?? '').toString();
    final String contactCode = (contact['code'] ?? '').toString();
    final double balance = (contact['balance'] as num?)?.toDouble() ?? 0.0;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        textDirection: pw.TextDirection.rtl,
        build: (pw.Context ctx) {
          return [
            pw.Text(
              shopName.isEmpty ? 'Nebras SofT Pos' : shopName,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            if (shopPhone.isNotEmpty || shopAddress.isNotEmpty)
              pw.Text(
                [
                  if (shopPhone.isNotEmpty) 'هاتف: $shopPhone',
                  if (shopAddress.isNotEmpty) shopAddress,
                ].join(' • '),
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 9.5),
              ),
            pw.SizedBox(height: 6),
            pw.Text(
              isCustomer ? 'كشف حساب عميل تفصيلي' : 'كشف حساب مورد تفصيلي',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
            pw.Divider(thickness: 1),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  '${isCustomer ? 'العميل' : 'المورد'}: $contactName ${contactCode.isNotEmpty ? '($contactCode)' : ''}',
                  style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(
                  'تاريخ الكشف: ${DateTime.now().toString().split(' ').first}',
                  style: const pw.TextStyle(fontSize: 9.5),
                ),
              ],
            ),
            if (contactPhone.isNotEmpty)
              pw.Text('رقم الهاتف: $contactPhone', style: const pw.TextStyle(fontSize: 9.5)),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(width: 0.6, color: PdfColors.grey600),
              columnWidths: {
                0: const pw.FlexColumnWidth(2.2),
                1: const pw.FlexColumnWidth(2.2),
                2: const pw.FlexColumnWidth(3.6),
                3: const pw.FlexColumnWidth(2.0),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text('التاريخ', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text('المرجع', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text('البيان', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text(
                        'المبلغ ($currency)',
                        textAlign: pw.TextAlign.left,
                        style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                if (movements.isEmpty)
                  pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('لا توجد حركات مسجلة', style: const pw.TextStyle(fontSize: 9)),
                      ),
                      pw.SizedBox(),
                      pw.SizedBox(),
                      pw.SizedBox(),
                    ],
                  )
                else
                  ...movements.map((m) {
                    final rawDate = (m['date'] ?? '').toString().split('T').first;
                    final ref = (m['reference'] ?? '').toString();
                    final desc = (m['description'] ?? '').toString();
                    final amt = (m['amount'] as num?)?.toDouble() ?? 0.0;

                    return pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text(rawDate, style: const pw.TextStyle(fontSize: 8.5)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text(ref, style: const pw.TextStyle(fontSize: 8.5)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text(desc, style: const pw.TextStyle(fontSize: 8.5)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text(
                            amt.toStringAsFixed(2),
                            textAlign: pw.TextAlign.left,
                            style: const pw.TextStyle(fontSize: 8.5),
                          ),
                        ),
                      ],
                    );
                  }),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'الرصيد الحالي:',
                  style: pw.TextStyle(fontSize: 11.5, fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(
                  '${balance.toStringAsFixed(2)} $currency',
                  style: pw.TextStyle(fontSize: 11.5, fontWeight: pw.FontWeight.bold),
                ),
              ],
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  static Future<void> showContactStatementSheet(BuildContext context, int contactId) async {
    final statementData = await DatabaseHelper.instance.getContactStatementData(contactId) as DbRow;
    if (statementData.isEmpty) return;

    final settings = await DatabaseHelper.instance.getSettingsMap() as Map<String, String>;
    final contact = statementData['contact'] as DbRow;
    final movements = (statementData['movements'] as List<DbRow>?) ?? [];
    final String contactName = (contact['name'] ?? '').toString();

    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.description_outlined, size: 38, color: Color(0xFF7C3AED)),
            const SizedBox(height: 8),
            Text(
              'كشف حساب: $contactName',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              'عدد الحركات: ${movements.length} • الرصيد الحالي: ${((contact['balance'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)} ${settings['currency_symbol'] ?? 'ر.ي'}',
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF7C3AED)),
                    onPressed: () async {
                      Navigator.of(ctx).pop();
                      final bytes = await buildContactStatementPdf(
                        contact: contact,
                        movements: movements,
                        settings: settings,
                      );
                      await Printing.layoutPdf(
                        name: 'statement_$contactId.pdf',
                        onLayout: (_) async => bytes,
                      );
                    },
                    icon: const Icon(Icons.print),
                    label: const Text('طباعة الكشف'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.of(ctx).pop();
                      final bytes = await buildContactStatementPdf(
                        contact: contact,
                        movements: movements,
                        settings: settings,
                      );
                      await Printing.sharePdf(
                        bytes: bytes,
                        filename: 'statement_$contactId.pdf',
                      );
                    },
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('مشاركة PDF'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  static Future<void> printThermalInvoice(
    BuildContext context,
    String invoiceNumber, {
    bool? is80mm,
  }) async {
    final details = await DatabaseHelper.instance.getInvoiceDetailsByNumber(invoiceNumber);
    if (details.isEmpty) return;

    final settings = await DatabaseHelper.instance.getSettingsMap() as Map<String, String>;
    final inv = details['invoice'] as DbRow;
    final items = (details['items'] as List<DbRow>?) ?? [];
    final bytes = await buildReceiptPdf(
      invoice: inv,
      items: items,
      settings: settings,
      is80mm: is80mm,
    );

    await Printing.layoutPdf(
      name: '$invoiceNumber.pdf',
      onLayout: (_) async => bytes,
    );
  }

  static Future<void> shareInvoicePdf(
    BuildContext context,
    String invoiceNumber, {
    bool? is80mm,
  }) async {
    final details = await DatabaseHelper.instance.getInvoiceDetailsByNumber(invoiceNumber);
    if (details.isEmpty) return;

    final settings = await DatabaseHelper.instance.getSettingsMap() as Map<String, String>;
    final inv = details['invoice'] as DbRow;
    final items = (details['items'] as List<DbRow>?) ?? [];
    final bytes = await buildReceiptPdf(
      invoice: inv,
      items: items,
      settings: settings,
      is80mm: is80mm,
    );

    await Printing.sharePdf(
      bytes: bytes,
      filename: '$invoiceNumber.pdf',
    );
  }

  static Future<void> showReturnDialog(
    BuildContext context,
    String invoiceNumber, {
    VoidCallback? onReturnSaved,
  }) async {
    final details = await DatabaseHelper.instance.getInvoiceDetailsByNumber(invoiceNumber);
    if (details.isEmpty || !context.mounted) return;

    final inv = details['invoice'] as DbRow;
    final rawItems = (details['items'] as List<DbRow>?) ?? [];
    if (rawItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد أصناف قابلة للإرجاع في هذه الفاتورة')),
      );
      return;
    }

    final String origType = (inv['type'] ?? 'sale').toString();
    final bool isSaleSide = origType == 'sale' || origType == 'sale_return';

    final List<DbRow> editableItems = rawItems.map((it) {
      final double maxQty = (it['quantity'] as num?)?.toDouble() ?? 0.0;
      final double price = (it['price'] as num?)?.toDouble() ?? 0.0;
      return {
        'product_id': it['product_id'],
        'name': (it['name'] ?? '').toString(),
        'max_qty': maxQty,
        'return_qty': maxQty,
        'price': price,
      };
    }).toList();

    bool submitting = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          double calcTotal() {
            double sum = 0.0;
            for (final it in editableItems) {
              final q = (it['return_qty'] as num?)?.toDouble() ?? 0.0;
              final pPrice = (it['price'] as num?)?.toDouble() ?? 0.0;
              if (q > 0) sum += q * pPrice;
            }
            return sum;
          }

          return AlertDialog(
            title: Text(
              isSaleSide ? 'مرتجع مبيعات من $invoiceNumber' : 'مرتجع مشتريات من $invoiceNumber',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ...editableItems.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final it = entry.value;
                      final double maxQty = (it['max_qty'] as num).toDouble();
                      final double retQty = (it['return_qty'] as num).toDouble();
                      final double price = (it['price'] as num).toDouble();

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                it['name'].toString(),
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'سعر الوحدة: ${price.toStringAsFixed(2)} • أقصى كمية في الفاتورة: $maxQty',
                                style: const TextStyle(fontSize: 12, color: Colors.black54),
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle_outline),
                                    onPressed: submitting
                                        ? null
                                        : () {
                                            if (retQty > 0) {
                                              setDialogState(() {
                                                editableItems[idx]['return_qty'] =
                                                    (retQty - 1) < 0 ? 0.0 : (retQty - 1);
                                              });
                                            }
                                          },
                                  ),
                                  Text(
                                    'مرتجع: $retQty',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.add_circle_outline),
                                    onPressed: submitting
                                        ? null
                                        : () {
                                            if (retQty + 1 <= maxQty) {
                                              setDialogState(() {
                                                editableItems[idx]['return_qty'] = retQty + 1;
                                              });
                                            }
                                          },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('إجمالي المرتجع:', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text(
                          calcTotal().toStringAsFixed(2),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Color(0xFFDC2626),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: submitting ? null : () => Navigator.of(ctx).pop(),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
                onPressed: submitting || calcTotal() <= 0
                    ? null
                    : () async {
                        setDialogState(() => submitting = true);
                        try {
                          final retNum = await DatabaseHelper.instance.createReturnFromInvoice(
                            originalInvoiceNumber: invoiceNumber,
                            returnItems: editableItems,
                          );
                          if (!ctx.mounted) return;
                          Navigator.of(ctx).pop();
                          onReturnSaved?.call();
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('تم حفظ المرتجع رقم $retNum وتحديث المخزون والرصيد')),
                          );
                          await showInvoiceActionSheet(context, retNum, onReturnSaved: onReturnSaved);
                        } catch (_) {
                          if (ctx.mounted) {
                            setDialogState(() => submitting = false);
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(content: Text('تعذر حفظ المرتجع، تحقق من الكميات')),
                            );
                          }
                        }
                      },
                child: Text(submitting ? 'جاري الحفظ...' : 'تأكيد المرتجع'),
              ),
            ],
          );
        },
      ),
    );
  }

  static Future<void> showInvoiceActionSheet(
    BuildContext context,
    String invoiceNumber, {
    VoidCallback? onReturnSaved,
  }) async {
    final settings = await DatabaseHelper.instance.getSettingsMap() as Map<String, String>;
    bool is80mm = (settings['printer_paper'] ?? '80mm') != '58mm';
    final details = await DatabaseHelper.instance.getInvoiceDetailsByNumber(invoiceNumber);
    final invType = ((details['invoice'] as DbRow?)?['type'] ?? '').toString();
    final bool canReturn = invType == 'sale' || invType == 'purchase';

    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.receipt_long, size: 40, color: Color(0xFF1545B5)),
              const SizedBox(height: 8),
              Text(
                'مستند رقم: $invoiceNumber',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('ورق حراري 80mm')),
                  ButtonSegment(value: false, label: Text('ورق حراري 58mm')),
                ],
                selected: {is80mm},
                onSelectionChanged: (sel) {
                  setSheetState(() => is80mm = sel.first);
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        Navigator.of(ctx).pop();
                        await printThermalInvoice(context, invoiceNumber, is80mm: is80mm);
                      },
                      icon: const Icon(Icons.print),
                      label: const Text('طباعة / PDF'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.of(ctx).pop();
                        await shareInvoicePdf(context, invoiceNumber, is80mm: is80mm);
                      },
                      icon: const Icon(Icons.share),
                      label: const Text('مشاركة PDF'),
                    ),
                  ),
                ],
              ),
              if (canReturn) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFDC2626),
                    ),
                    onPressed: () async {
                      Navigator.of(ctx).pop();
                      await showReturnDialog(
                        context,
                        invoiceNumber,
                        onReturnSaved: onReturnSaved,
                      );
                    },
                    icon: const Icon(Icons.assignment_return),
                    label: Text(
                      invType == 'sale' ? 'إنشاء مرتجع مبيعات من الفاتورة' : 'إنشاء مرتجع مشتريات من الفاتورة',
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class NebrasPosApp extends StatelessWidget {
  const NebrasPosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nebras SofT Pos',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1545B5),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF4F6FA),
      ),
      home: const DashboardScreen(),
    );
  }
}

class _ModuleItem {
  final String title;
  final IconData icon;
  final Color color;

  const _ModuleItem(this.title, this.icon, this.color);
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const String _appVersion = 'v1.6.0';
  static const String _whatsappUrl = 'https://wa.me/967735114406';
  static const String _telegramUrl = 'https://t.me/softnebras';
  static const String _youtubeUrl = 'https://youtube.com/@nebras-soft?si=KALKhHKx4ya-97xJ';
  static const String _githubUrl = 'https://github.com/qpkdj';

  int _productsCount = 0;
  String _shopName = 'نبراس SofT لنقاط البيع';
  String _currencySymbol = 'ر.ي';
  String _printerPaper = '80mm';
  String _desktopSyncHost = '';
  String _adminPin = '';
  String _receiptFooter = 'شكراً لتعاملكم معنا • Nebras SofT Pos';
  String _deviceId = '';
  bool _dbReady = false;

  static const List<_ModuleItem> _modules = [
    _ModuleItem('نقطة البيع (POS)', Icons.point_of_sale, Color(0xFF1545B5)),
    _ModuleItem('إدارة الأصناف', Icons.inventory_2, Color(0xFF0D7C66)),
    _ModuleItem('فواتير المشتريات', Icons.shopping_cart, Color(0xFFD97706)),
    _ModuleItem('العملاء والموردين', Icons.people, Color(0xFF7C3AED)),
    _ModuleItem('حركات اليومية والصندوق', Icons.account_balance_wallet, Color(0xFF0F766E)),
    _ModuleItem('التقارير والأرباح', Icons.bar_chart, Color(0xFFDC2626)),
    _ModuleItem('النسخ الاحتياطي', Icons.settings_backup_restore, Color(0xFF334155)),
  ];

  @override
  void initState() {
    super.initState();
    _refreshStats();
  }

  Future<void> _refreshStats() async {
    try {
      final products = await DatabaseHelper.instance.queryAllProducts();
      final settings = await DatabaseHelper.instance.getSettingsMap() as Map<String, String>;
      if (!mounted) return;
      setState(() {
        _productsCount = products.length;
        _shopName = settings['shop_name'] ?? 'نبراس SofT لنقاط البيع';
        _currencySymbol = settings['currency_symbol'] ?? 'ر.ي';
        _printerPaper = settings['printer_paper'] ?? '80mm';
        _desktopSyncHost = settings['desktop_sync_host'] ?? '';
        _adminPin = settings['admin_pin'] ?? '';
        _receiptFooter = settings['receipt_footer'] ?? 'شكراً لتعاملكم معنا • Nebras SofT Pos';
        _deviceId = settings['device_id'] ?? '';
        _dbReady = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _dbReady = true;
      });
    }
  }

  Future<bool> _verifyPinIfRequired(String sectionTitle) async {
    if (_adminPin.trim().isEmpty) return true;
    final pinCtrl = TextEditingController();
    bool allowed = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('رمز الحماية PIN • $sectionTitle', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        content: TextField(
          controller: pinCtrl,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 8,
          decoration: const InputDecoration(
            labelText: 'أدخل رمز PIN',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              if (pinCtrl.text.trim() == _adminPin.trim()) {
                allowed = true;
                Navigator.of(ctx).pop();
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('رمز PIN غير صحيح')),
                );
              }
            },
            child: const Text('دخول'),
          ),
        ],
      ),
    );
    return allowed;
  }

  Future<void> _onModuleTap(String moduleName) async {
    if (moduleName == 'التقارير والأرباح' || moduleName == 'النسخ الاحتياطي') {
      final ok = await _verifyPinIfRequired(moduleName);
      if (!ok || !mounted) return;
    }

    Widget? targetScreen;
    if (moduleName == 'إدارة الأصناف') {
      targetScreen = const ProductsScreen();
    } else if (moduleName == 'نقطة البيع (POS)') {
      targetScreen = const PosScreen();
    } else if (moduleName == 'فواتير المشتريات') {
      targetScreen = const PurchasesScreen();
    } else if (moduleName == 'العملاء والموردين') {
      targetScreen = const ContactsScreen();
    } else if (moduleName == 'حركات اليومية والصندوق') {
      targetScreen = const CashboxScreen();
    } else if (moduleName == 'التقارير والأرباح') {
      targetScreen = const ReportsScreen();
    } else if (moduleName == 'النسخ الاحتياطي') {
      targetScreen = const BackupScreen();
    }

    if (targetScreen != null) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => targetScreen!),
      );
      _refreshStats();
    }
  }

  Future<void> _triggerChannelAction({
    required BuildContext dialogContext,
    required String targetUrl,
    required String feedbackMessage,
  }) async {
    final uri = Uri.parse(targetUrl);
    bool opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }

    if (!opened) {
      await Clipboard.setData(ClipboardData(text: targetUrl));
    }

    if (dialogContext.mounted) {
      Navigator.of(dialogContext).pop();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          opened
              ? feedbackMessage
              : 'تعذر فتح التطبيق مباشرة، تم نسخ الرابط إلى الحافظة',
        ),
      ),
    );
  }

  Future<void> _showContactDeveloperDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('التواصل مع المطور', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0x2216A34A),
                  child: Icon(Icons.business_center, color: Color(0xFF16A34A)),
                ),
                title: const Text('التواصل واتساب أعمال', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                trailing: const Icon(Icons.chat_bubble_outline, color: Color(0xFF16A34A)),
                onTap: () => _triggerChannelAction(
                  dialogContext: ctx,
                  targetUrl: _whatsappUrl,
                  feedbackMessage: 'جاري فتح واتساب أعمال للمطور...',
                ),
              ),
            ),
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0x220369A1),
                  child: Icon(Icons.send, color: Color(0xFF0369A1)),
                ),
                title: const Text('مراسلة المطور عن طريق التليجرام', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                trailing: const Icon(Icons.open_in_new, size: 18, color: Color(0xFF0369A1)),
                onTap: () => _triggerChannelAction(
                  dialogContext: ctx,
                  targetUrl: _telegramUrl,
                  feedbackMessage: 'جاري فتح تليجرام للمطور...',
                ),
              ),
            ),
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0x22DC2626),
                  child: Icon(Icons.smart_display, color: Color(0xFFDC2626)),
                ),
                title: const Text('تابع قناة المطور على يوتيوب', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                trailing: const Icon(Icons.play_arrow_rounded, size: 24, color: Color(0xFFDC2626)),
                onTap: () => _triggerChannelAction(
                  dialogContext: ctx,
                  targetUrl: _youtubeUrl,
                  feedbackMessage: 'جاري فتح قناة المطور على يوتيوب...',
                ),
              ),
            ),
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0x22334155),
                  child: Icon(Icons.code, color: Color(0xFF334155)),
                ),
                title: const Text(
                  'لمتابعة مشاريع المطور على منصة GitHub اضغط هنا ( github )',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Color(0xFF334155)),
                onTap: () => _triggerChannelAction(
                  dialogContext: ctx,
                  targetUrl: _githubUrl,
                  feedbackMessage: 'جاري فتح صفحة المطور على GitHub...',
                ),
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Future<void> _showPinSetupDialog() async {
    final pinCtrl = TextEditingController(text: _adminPin);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('رمز حماية PIN للشاشات الحساسة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'اتركه فارغاً لإلغاء القفل، أو أدخل رمزاً رقمياً لحماية التقارير والنسخ الاحتياطي والإعدادات.',
              style: TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: pinCtrl,
              keyboardType: TextInputType.number,
              maxLength: 8,
              decoration: const InputDecoration(
                labelText: 'رمز PIN الجديد',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () async {
              await DatabaseHelper.instance.saveSettingsMap({'admin_pin': pinCtrl.text.trim()});
              if (ctx.mounted) Navigator.of(ctx).pop();
              await _refreshStats();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    pinCtrl.text.trim().isEmpty
                        ? 'تم إيقاف رمز الحماية PIN'
                        : 'تم حفظ رمز الحماية PIN بنجاح',
                  ),
                ),
              );
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  Future<void> _showReceiptFooterDialog() async {
    final footerCtrl = TextEditingController(text: _receiptFooter);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تذييل الفاتورة المخصص', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        content: TextField(
          controller: footerCtrl,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'النص الختامي أسفل الفاتورة',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () async {
              final nextFooter = footerCtrl.text.trim().isEmpty
                  ? 'شكراً لتعاملكم معنا • Nebras SofT Pos'
                  : footerCtrl.text.trim();
              await DatabaseHelper.instance.saveSettingsMap({'receipt_footer': nextFooter});
              if (ctx.mounted) Navigator.of(ctx).pop();
              await _refreshStats();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم حفظ تذييل الفاتورة المخصص')),
              );
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  Future<void> _showClearDemoDataDialog() async {
    bool confirmed = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('تصفير بيانات التجربة', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFDC2626))),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'سيتم حذف الفواتير وعناصرها والسندات والمصروفات وتصفير أرصدة العملاء/الموردين مع الإبقاء على الأصناف والإعدادات.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 10),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: confirmed,
                onChanged: (v) => setDialogState(() => confirmed = v ?? false),
                title: const Text('أؤكد رغبتي في مسح العمليات التجريبية', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
              onPressed: !confirmed
                  ? null
                  : () async {
                      await DatabaseHelper.instance.clearDemoTransactionsOnly();
                      if (ctx.mounted) Navigator.of(ctx).pop();
                      await _refreshStats();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم تصفير الفواتير والعمليات التجريبية بنجاح')),
                      );
                    },
              child: const Text('تنفيذ التصفير'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showQuickGuideDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('دليل الاستخدام السريع', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('1. أضف التصنيفات والأصناف مع الأسعار والكميات والباركود من "إدارة الأصناف".'),
              SizedBox(height: 8),
              Text('2. سجّل فواتير الشراء من "فواتير المشتريات" لزيادة المخزون وتحديث تكلفة الشراء.'),
              SizedBox(height: 8),
              Text('3. نفّذ البيع واطبع أو شارك الفاتورة الحرارية PDF من "نقطة البيع (POS)".'),
              SizedBox(height: 8),
              Text('4. راجع المتوفر النقدي في "حركات اليومية والصندوق" وصافي الربح في "التقارير والأرباح".'),
              SizedBox(height: 8),
              Text('5. خذ نسخة احتياطية بانتظام من "النسخ الاحتياطي".'),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAboutDeviceDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حول التطبيق ومعرّف الجهاز', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('البرنامج: Nebras SofT Pos'),
            const SizedBox(height: 6),
            const Text('الإصدار: $_appVersion'),
            const SizedBox(height: 6),
            Text('معرّف الجهاز (Device ID): $_deviceId'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _deviceId));
              if (ctx.mounted) {
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم نسخ معرّف الجهاز إلى الحافظة')),
                );
              }
            },
            child: const Text('نسخ Device ID'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Future<void> _showCheckUpdateDialog() async {
    bool checking = true;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          if (checking) {
            Future.delayed(const Duration(milliseconds: 650), () {
              if (ctx.mounted) {
                setDialogState(() => checking = false);
              }
            });
          }
          return AlertDialog(
            title: const Text('البحث عن تحديث جديد', style: TextStyle(fontWeight: FontWeight.bold)),
            content: checking
                ? const Row(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(width: 14),
                      Expanded(child: Text('جاري التحقق من رقم الإصدار...')),
                    ],
                  )
                : const Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('الإصدار الحالي المثبت: $_appVersion'),
                      SizedBox(height: 8),
                      Text('أنت تعمل على أحدث إصدار متاح في هذه الحزمة. عند توفر إصدار جديد يمكنك تحميله وتثبيته مباشرة.'),
                    ],
                  ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('حسناً'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showPrinterSettingsDialog() async {
    bool selected80mm = _printerPaper != '58mm';
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('إعدادات الطابعة', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('اختر مقاس الورق الافتراضي للطباعة الحرارية:'),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('80mm')),
                  ButtonSegment(value: false, label: Text('58mm')),
                ],
                selected: {selected80mm},
                onSelectionChanged: (sel) {
                  setDialogState(() => selected80mm = sel.first);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () async {
                final nextPaper = selected80mm ? '80mm' : '58mm';
                await DatabaseHelper.instance.saveSettingsMap({'printer_paper': nextPaper});
                if (ctx.mounted) Navigator.of(ctx).pop();
                await _refreshStats();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('تم حفظ مقاس الطابعة الافتراضي: $nextPaper')),
                );
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDesktopSyncDialog() async {
    final hostCtrl = TextEditingController(text: _desktopSyncHost);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('الربط مع نسخة الكمبيوتر', style: TextStyle(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'أدخل عنوان جهاز الكمبيوتر أو مسار المزامنة على الشبكة المحلية، أو صدّر قاعدة البيانات للمشاركة مع نسخة سطح المكتب:',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: hostCtrl,
                decoration: const InputDecoration(
                  labelText: 'عنوان جهاز الكمبيوتر / رابط الربط',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  final ok = await _verifyPinIfRequired('النسخ الاحتياطي');
                  if (!ok || !mounted) return;
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const BackupScreen()),
                  );
                  _refreshStats();
                },
                icon: const Icon(Icons.folder_shared),
                label: const Text('فتح شاشة تصدير واستعادة قاعدة البيانات'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () async {
              await DatabaseHelper.instance.saveSettingsMap({
                'desktop_sync_host': hostCtrl.text.trim(),
              });
              if (ctx.mounted) Navigator.of(ctx).pop();
              await _refreshStats();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم حفظ إعدادات الربط مع نسخة الكمبيوتر')),
              );
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  Future<void> _showPrivacyPolicyDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('سياسة الخصوصية', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const SingleChildScrollView(
          child: Text(
            'يُخزِّن تطبيق Nebras SofT Pos جميع بيانات المحل والأصناف والعملاء والموردين والفواتير والمصروفات محلياً على جهازك داخل قاعدة البيانات المحلية دون رفع بياناتك إلى خوادم خارجية تلقائياً. أنت تملك تحكماً كاملاً في إنشاء النسخ الاحتياطية ومشاركتها أو تصديرها.',
            style: TextStyle(fontSize: 13.5, height: 1.5),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Future<void> _shareAppInfo() async {
    const shareText =
        'تطبيق Nebras SofT Pos لإدارة نقاط البيع والمخزون والفواتير والعملاء والموردين والحسابات — من تطوير نبراس SofT.\n$_githubUrl';
    try {
      await Share.share(shareText, subject: 'Nebras SofT Pos');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح قائمة المشاركة على هذا الجهاز')),
      );
    }
  }

  Widget _buildSpecialDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              color: const Color(0xFF0F2C7E),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.tune, color: Colors.white, size: 30),
                  const SizedBox(height: 10),
                  const Text(
                    'إعدادات وخدمات خاصة',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$_shopName • $_appVersion',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  ListTile(
                    leading: const Icon(Icons.lock_outline, color: Color(0xFFDC2626)),
                    title: const Text('رمز حماية PIN'),
                    subtitle: Text(_adminPin.isEmpty ? 'غير مفعّل' : 'مفعّل'),
                    onTap: () {
                      Navigator.of(context).pop();
                      _showPinSetupDialog();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.edit_note, color: Color(0xFF0D7C66)),
                    title: const Text('تذييل الفاتورة المخصص'),
                    onTap: () {
                      Navigator.of(context).pop();
                      _showReceiptFooterDialog();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.delete_sweep, color: Color(0xFFDC2626)),
                    title: const Text('تصفير بيانات التجربة'),
                    onTap: () async {
                      Navigator.of(context).pop();
                      final ok = await _verifyPinIfRequired('تصفير بيانات التجربة');
                      if (!ok || !mounted) return;
                      await _showClearDemoDataDialog();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.menu_book_outlined, color: Color(0xFF0369A1)),
                    title: const Text('دليل الاستخدام السريع'),
                    onTap: () {
                      Navigator.of(context).pop();
                      _showQuickGuideDialog();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.perm_device_information, color: Color(0xFF334155)),
                    title: const Text('حول التطبيق ومعرّف الجهاز'),
                    subtitle: Text(_deviceId.isEmpty ? _appVersion : 'ID: $_deviceId'),
                    onTap: () {
                      Navigator.of(context).pop();
                      _showAboutDeviceDialog();
                    },
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.support_agent, color: Color(0xFF0F2C7E)),
                    title: const Text('التواصل مع المطور'),
                    onTap: () {
                      Navigator.of(context).pop();
                      _showContactDeveloperDialog();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.system_update, color: Color(0xFF0D7C66)),
                    title: const Text('البحث عن تحديث جديد'),
                    onTap: () {
                      Navigator.of(context).pop();
                      _showCheckUpdateDialog();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.print, color: Color(0xFFD97706)),
                    title: const Text('إعدادات الطابعة'),
                    subtitle: Text('المقاس الحالي: $_printerPaper'),
                    onTap: () {
                      Navigator.of(context).pop();
                      _showPrinterSettingsDialog();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.computer, color: Color(0xFF7C3AED)),
                    title: const Text('الربط مع نسخة الكمبيوتر'),
                    subtitle: Text(_desktopSyncHost.isEmpty ? 'غير مضبوط' : _desktopSyncHost),
                    onTap: () {
                      Navigator.of(context).pop();
                      _showDesktopSyncDialog();
                    },
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.settings, color: Color(0xFF0369A1)),
                    title: const Text('الإعدادات'),
                    onTap: () async {
                      Navigator.of(context).pop();
                      final ok = await _verifyPinIfRequired('الإعدادات');
                      if (!ok || !mounted) return;
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SettingsScreen()),
                      );
                      _refreshStats();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.privacy_tip_outlined, color: Color(0xFF334155)),
                    title: const Text('سياسة الخصوصية'),
                    onTap: () {
                      Navigator.of(context).pop();
                      _showPrivacyPolicyDialog();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.share, color: Color(0xFF0F766E)),
                    title: const Text('مشاركة البرنامج'),
                    onTap: () {
                      Navigator.of(context).pop();
                      _shareAppInfo();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: _buildSpecialDrawer(),
      appBar: AppBar(
        title: const Text(
          'Nebras SofT Pos',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF0F2C7E),
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0F2C7E), Color(0xFF1E56D9)],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _shopName,
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _dbReady
                        ? 'الأصناف: $_productsCount • العملة: $_currencySymbol'
                        : 'جاري تهيئة قاعدة البيانات...',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: GridView.builder(
                itemCount: _modules.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: 1.15,
                ),
                itemBuilder: (context, index) {
                  final item = _modules[index];
                  return Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _onModuleTap(item.title),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            radius: 26,
                            backgroundColor: item.color.withAlpha(30),
                            child: Icon(item.icon, color: item.color, size: 28),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            item.title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CashboxScreen extends StatefulWidget {
  const CashboxScreen({super.key});

  @override
  State<CashboxScreen> createState() => _CashboxScreenState();
}

class _CashboxScreenState extends State<CashboxScreen> {
  bool _loading = true;
  String _periodMode = 'today';
  DateTime? _startDate;
  DateTime? _endDate;

  double _cashSales = 0.0;
  double _receiptsTotal = 0.0;
  double _paymentsTotal = 0.0;
  double _expensesTotal = 0.0;
  double _cashInBox = 0.0;
  List<DbRow> _entries = [];

  @override
  void initState() {
    super.initState();
    _applyPeriod('today');
  }

  void _applyPeriod(String mode) {
    final now = DateTime.now();
    DateTime? s;
    DateTime? e;
    if (mode == 'today') {
      s = DateTime(now.year, now.month, now.day);
      e = DateTime(now.year, now.month, now.day);
    } else if (mode == 'month') {
      s = DateTime(now.year, now.month, 1);
      e = DateTime(now.year, now.month, now.day);
    }
    setState(() {
      _periodMode = mode;
      _startDate = s;
      _endDate = e;
    });
    _loadCashbox();
  }

  Future<void> _loadCashbox() async {
    setState(() => _loading = true);
    final data = await DatabaseHelper.instance.getCashboxSummary(
      startDate: _startDate,
      endDate: _endDate,
    ) as DbRow;
    if (!mounted) return;
    setState(() {
      _cashSales = (data['cashSales'] as num?)?.toDouble() ?? 0.0;
      _receiptsTotal = (data['receiptsTotal'] as num?)?.toDouble() ?? 0.0;
      _paymentsTotal = (data['paymentsTotal'] as num?)?.toDouble() ?? 0.0;
      _expensesTotal = (data['expensesTotal'] as num?)?.toDouble() ?? 0.0;
      _cashInBox = (data['cashInBox'] as num?)?.toDouble() ?? 0.0;
      _entries = (data['entries'] as List<DbRow>?) ?? [];
      _loading = false;
    });
  }

  Widget _boxStat(String title, double amount, Color color) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: Colors.black54, fontSize: 12)),
            const SizedBox(height: 6),
            Text(
              amount.toStringAsFixed(2),
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'حركات اليومية والصندوق',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF0F766E),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            onPressed: _loadCashbox,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('اليوم'),
                  selected: _periodMode == 'today',
                  onSelected: (_) => _applyPeriod('today'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('هذا الشهر'),
                  selected: _periodMode == 'month',
                  onSelected: (_) => _applyPeriod('month'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('الكل'),
                  selected: _periodMode == 'all',
                  onSelected: (_) => _applyPeriod('all'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      Card(
                        color: const Color(0xFF0F766E),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'المتوفر النقدي الفعلي في الصندوق',
                                style: TextStyle(color: Colors.white70, fontSize: 13),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _cashInBox.toStringAsFixed(2),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 24,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 1.65,
                        children: [
                          _boxStat('مبيعات نقدية', _cashSales, const Color(0xFF1545B5)),
                          _boxStat('سندات قبض', _receiptsTotal, const Color(0xFF0D7C66)),
                          _boxStat('سندات صرف', _paymentsTotal, const Color(0xFFD97706)),
                          _boxStat('المصروفات', _expensesTotal, const Color(0xFFDC2626)),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'سجل الحركات النقدية',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 8),
                      if (_entries.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(14),
                            child: Text('لا توجد حركات نقدية مسجلة في هذه الفترة'),
                          ),
                        )
                      else
                        ..._entries.map((e) {
                          final bool inc = e['incoming'] == true;
                          final double amt = (e['amount'] as num?)?.toDouble() ?? 0.0;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              dense: true,
                              leading: CircleAvatar(
                                backgroundColor: (inc ? Colors.green : Colors.red).withAlpha(25),
                                child: Icon(
                                  inc ? Icons.arrow_downward : Icons.arrow_upward,
                                  color: inc ? Colors.green[800] : Colors.red[700],
                                ),
                              ),
                              title: Text(
                                e['title'].toString(),
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text((e['date'] ?? '').toString().replaceFirst('T', ' ').split('.').first),
                              trailing: Text(
                                '${inc ? '+' : '-'}${amt.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: inc ? Colors.green[800] : Colors.red[700],
                                ),
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _shopNameCtrl = TextEditingController();
  final TextEditingController _shopPhoneCtrl = TextEditingController();
  final TextEditingController _shopAddressCtrl = TextEditingController();
  final TextEditingController _currencySymbolCtrl = TextEditingController();
  final TextEditingController _taxCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _shopNameCtrl.dispose();
    _shopPhoneCtrl.dispose();
    _shopAddressCtrl.dispose();
    _currencySymbolCtrl.dispose();
    _taxCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final map = await DatabaseHelper.instance.getSettingsMap() as Map<String, String>;
    if (!mounted) return;
    _shopNameCtrl.text = map['shop_name'] ?? 'نبراس SofT لنقاط البيع';
    _shopPhoneCtrl.text = map['shop_phone'] ?? '';
    _shopAddressCtrl.text = map['shop_address'] ?? '';
    _currencySymbolCtrl.text = map['currency_symbol'] ?? 'ر.ي';
    _taxCtrl.text = map['tax_percentage'] ?? '0';
    setState(() => _loading = false);
  }

  Future<void> _saveSettings() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await DatabaseHelper.instance.saveSettingsMap({
        'shop_name': _shopNameCtrl.text.trim().isEmpty
            ? 'نبراس SofT لنقاط البيع'
            : _shopNameCtrl.text.trim(),
        'shop_phone': _shopPhoneCtrl.text.trim(),
        'shop_address': _shopAddressCtrl.text.trim(),
        'currency_symbol': _currencySymbolCtrl.text.trim().isEmpty
            ? 'ر.ي'
            : _currencySymbolCtrl.text.trim(),
        'tax_percentage': _taxCtrl.text.trim().isEmpty ? '0' : _taxCtrl.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ إعدادات المحل والعملة بنجاح')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'إعدادات المحل والعملة',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF0369A1),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(14),
              children: [
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'بيانات الفاتورة والطباعة',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _shopNameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'اسم المحل / المنشأة',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _shopPhoneCtrl,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'رقم الهاتف (يظهر في الفاتورة)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _shopAddressCtrl,
                          decoration: const InputDecoration(
                            labelText: 'العنوان (يظهر في الفاتورة)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'العملة والضريبة',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _currencySymbolCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'رمز العملة (مثلاً: ر.ي)',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _taxCtrl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'نسبة الضريبة %',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          height: 48,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF0369A1),
                            ),
                            onPressed: _saving ? null : _saveSettings,
                            icon: const Icon(Icons.save),
                            label: Text(_saving ? 'جاري الحفظ...' : 'حفظ الإعدادات'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  bool _loading = true;
  String _periodMode = 'all';
  DateTime? _startDate;
  DateTime? _endDate;

  double _totalSales = 0.0;
  double _totalPurchases = 0.0;
  double _totalExpenses = 0.0;
  double _realNetProfit = 0.0;
  List<DbRow> _recentInvoices = [];
  List<DbRow> _expenses = [];
  List<DbRow> _lowStock = [];

  @override
  void initState() {
    super.initState();
    _applyPeriod('all');
  }

  void _applyPeriod(String mode) {
    final now = DateTime.now();
    DateTime? s;
    DateTime? e;

    if (mode == 'today') {
      s = DateTime(now.year, now.month, now.day);
      e = DateTime(now.year, now.month, now.day);
    } else if (mode == 'month') {
      s = DateTime(now.year, now.month, 1);
      e = DateTime(now.year, now.month, now.day);
    } else if (mode == 'custom') {
      s = _startDate ?? DateTime(now.year, now.month, 1);
      e = _endDate ?? DateTime(now.year, now.month, now.day);
    }

    setState(() {
      _periodMode = mode;
      _startDate = s;
      _endDate = e;
    });
    _loadReport();
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 2),
      initialDateRange: DateTimeRange(
        start: _startDate ?? DateTime(now.year, now.month, 1),
        end: _endDate ?? DateTime(now.year, now.month, now.day),
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _periodMode = 'custom';
        _startDate = picked.start;
        _endDate = picked.end;
      });
      await _loadReport();
    }
  }

  Future<void> _exportInvoicesCsv() async {
    final rows = <List<dynamic>>[
      ['رقم المستند', 'النوع', 'التاريخ', 'الإجمالي الصافي', 'الخصم', 'طريقة الدفع'],
      ..._recentInvoices.map((inv) => [
            inv['invoice_number'] ?? '',
            _typeBadgeLabel((inv['type'] ?? '').toString()),
            (inv['date'] ?? '').toString().replaceFirst('T', ' ').split('.').first,
            ((inv['total_amount'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2),
            ((inv['discount'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2),
            inv['payment_method'] ?? '',
          ]),
    ];
    await CsvExportService.exportAndShareCsv(
      context: context,
      fileBaseName: 'nebras_invoices',
      rows: rows,
    );
  }

  Future<void> _exportExpensesCsv() async {
    final rows = <List<dynamic>>[
      ['البيان', 'التصنيف', 'المبلغ', 'التاريخ', 'ملاحظات'],
      ..._expenses.map((exp) => [
            exp['title'] ?? '',
            exp['category'] ?? '',
            ((exp['amount'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2),
            (exp['date'] ?? '').toString().split('T').first,
            exp['notes'] ?? '',
          ]),
    ];
    await CsvExportService.exportAndShareCsv(
      context: context,
      fileBaseName: 'nebras_expenses',
      rows: rows,
    );
  }

  Future<void> _openAddExpenseDialog() async {
    final titleCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String category = 'إيجار ومصاريف ثابتة';

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text(
            'تسجيل مصروف تشغيلي',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'بيان المصروف *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: category,
                  decoration: const InputDecoration(
                    labelText: 'تصنيف المصروف',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'إيجار ومصاريف ثابتة', child: Text('إيجار ومصاريف ثابتة')),
                    DropdownMenuItem(value: 'كهرباء ونت', child: Text('كهرباء ونت')),
                    DropdownMenuItem(value: 'رواتب وأجور', child: Text('رواتب وأجور')),
                    DropdownMenuItem(value: 'نقل ومواصلات', child: Text('نقل ومواصلات')),
                    DropdownMenuItem(value: 'مصروفات متنوعة', child: Text('مصروفات متنوعة')),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => category = v);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'المبلغ *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات (اختياري)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
              onPressed: () async {
                final title = titleCtrl.text.trim();
                final amt = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                if (title.isEmpty || amt <= 0) return;
                await DatabaseHelper.instance.insertExpense(
                  title: title,
                  category: category,
                  amount: amt,
                  notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                );
                if (ctx.mounted) Navigator.of(ctx).pop(true);
              },
              child: const Text('حفظ المصروف'),
            ),
          ],
        ),
      ),
    );

    if (saved == true) {
      await _loadReport();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تسجيل المصروف وتحديث صافي الربح الحقيقي')),
      );
    }
  }

  Future<void> _loadReport() async {
    setState(() => _loading = true);
    final summary = await DatabaseHelper.instance.getFinancialSummary(
      startDate: _startDate,
      endDate: _endDate,
    ) as DbRow;
    if (!mounted) return;
    setState(() {
      _totalSales = (summary['totalSales'] as num?)?.toDouble() ?? 0.0;
      _totalPurchases = (summary['totalPurchases'] as num?)?.toDouble() ?? 0.0;
      _totalExpenses = (summary['totalExpenses'] as num?)?.toDouble() ?? 0.0;
      _realNetProfit = (summary['realNetProfit'] as num?)?.toDouble() ?? 0.0;
      _recentInvoices = (summary['recentInvoices'] as List<DbRow>?) ?? [];
      _expenses = (summary['expenses'] as List<DbRow>?) ?? [];
      _lowStock = (summary['lowStockProducts'] as List<DbRow>?) ?? [];
      _loading = false;
    });
  }

  String _typeBadgeLabel(String type) {
    switch (type) {
      case 'sale':
        return 'بيع';
      case 'purchase':
        return 'شراء';
      case 'sale_return':
        return 'مرتجع بيع';
      case 'purchase_return':
        return 'مرتجع شراء';
      default:
        return type;
    }
  }

  Widget _buildStatCard(String title, double value, Color color) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: Colors.black54, fontSize: 12.5)),
            const SizedBox(height: 6),
            Text(
              value.toStringAsFixed(2),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 17.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rangeHint = _periodMode == 'custom' && _startDate != null && _endDate != null
        ? 'من ${_startDate!.toString().split(' ').first} إلى ${_endDate!.toString().split(' ').first}'
        : _periodMode == 'today'
            ? 'فترة اليوم'
            : _periodMode == 'month'
                ? 'فترة الشهر الحالي'
                : 'جميع الفترات';

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'التقارير والأرباح',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: const Color(0xFFDC2626),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: 'تصدير الفواتير CSV',
            onPressed: _exportInvoicesCsv,
            icon: const Icon(Icons.table_view),
          ),
          IconButton(
            tooltip: 'إضافة مصروف تشغيلي',
            onPressed: _openAddExpenseDialog,
            icon: const Icon(Icons.add_card),
          ),
          IconButton(
            tooltip: 'تحديث التقرير',
            onPressed: _loadReport,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddExpenseDialog,
        backgroundColor: const Color(0xFFDC2626),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.remove_circle_outline),
        label: const Text('تسجيل مصروف'),
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('الكل'),
                  selected: _periodMode == 'all',
                  onSelected: (_) => _applyPeriod('all'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('اليوم'),
                  selected: _periodMode == 'today',
                  onSelected: (_) => _applyPeriod('today'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('هذا الشهر'),
                  selected: _periodMode == 'month',
                  onSelected: (_) => _applyPeriod('month'),
                ),
                const SizedBox(width: 8),
                ActionChip(
                  avatar: const Icon(Icons.date_range, size: 18),
                  label: Text(_periodMode == 'custom' ? rangeHint : 'فترة مخصصة'),
                  onPressed: _pickCustomRange,
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _loadReport,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 84),
                      children: [
                        Text(
                          'الفترة المعروضة: $rangeHint • النواقص: ${_lowStock.length}',
                          style: const TextStyle(color: Colors.black54, fontSize: 12.5),
                        ),
                        const SizedBox(height: 8),
                        GridView.count(
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 1.55,
                          children: [
                            _buildStatCard('صافي المبيعات', _totalSales, const Color(0xFF1545B5)),
                            _buildStatCard('صافي المشتريات', _totalPurchases, const Color(0xFFD97706)),
                            _buildStatCard('المصروفات التشغيلية', _totalExpenses, const Color(0xFFDC2626)),
                            _buildStatCard(
                              'صافي الربح الحقيقي',
                              _realNetProfit,
                              _realNetProfit >= 0 ? const Color(0xFF0D7C66) : Colors.red,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'المصروفات المسجلة في الفترة',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            TextButton.icon(
                              onPressed: _expenses.isEmpty ? null : _exportExpensesCsv,
                              icon: const Icon(Icons.download, size: 18),
                              label: const Text('تصدير CSV'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        if (_expenses.isEmpty)
                          const Card(
                            child: Padding(
                              padding: EdgeInsets.all(14),
                              child: Text('لا توجد مصروفات مسجلة في هذه الفترة'),
                            ),
                          )
                        else
                          ..._expenses.map((exp) {
                            final int expId = exp['id'] as int;
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                dense: true,
                                leading: const CircleAvatar(
                                  backgroundColor: Color(0x22DC2626),
                                  child: Icon(Icons.receipt, color: Color(0xFFDC2626)),
                                ),
                                title: Text(
                                  '${exp['title']} (${exp['category'] ?? ''})',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text((exp['date'] ?? '').toString().split('T').first),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      ((exp['amount'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFDC2626),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, size: 20, color: Colors.black54),
                                      onPressed: () async {
                                        await DatabaseHelper.instance.deleteExpense(expId);
                                        await _loadReport();
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Expanded(
                              child: Text(
                                'الفواتير والمرتجعات في الفترة',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _recentInvoices.isEmpty ? null : _exportInvoicesCsv,
                              icon: const Icon(Icons.download, size: 18),
                              label: const Text('تصدير CSV'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        if (_recentInvoices.isEmpty)
                          const Card(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('لا توجد فواتير مسجلة في هذه الفترة'),
                            ),
                          )
                        else
                          ..._recentInvoices.map((inv) {
                            final invType = (inv['type'] ?? '').toString();
                            final isReturn = invType.endsWith('_return');
                            final isSaleSide = invType.startsWith('sale');
                            final method = inv['payment_method']?.toString() ?? '';
                            final invNum = (inv['invoice_number'] ?? '').toString();

                            final Color badgeColor = isReturn
                                ? const Color(0xFFDC2626)
                                : (isSaleSide ? const Color(0xFF1545B5) : const Color(0xFFD97706));

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                onTap: () => ThermalPdfService.showInvoiceActionSheet(
                                  context,
                                  invNum,
                                  onReturnSaved: _loadReport,
                                ),
                                leading: CircleAvatar(
                                  backgroundColor: badgeColor.withAlpha(25),
                                  child: Icon(
                                    isReturn
                                        ? Icons.assignment_return
                                        : (isSaleSide ? Icons.arrow_upward : Icons.arrow_downward),
                                    color: badgeColor,
                                  ),
                                ),
                                title: Text(
                                  '$invNum (${_typeBadgeLabel(invType)})',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text('الدفع: $method • ${inv['date'].toString().split('T').first}'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${((inv['total_amount'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.more_vert, size: 20, color: Colors.black54),
                                  ],
                                ),
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  String _dbPath = '';
  String _externalDirPath = '';
  int _dbSizeBytes = 0;
  List<FileSystemEntity> _backups = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadBackupInfo();
  }

  Future<Directory> _getInternalBackupDir() async {
    final dbPath = await DatabaseHelper.instance.getDatabaseFilePath();
    final dir = Directory(p.join(p.dirname(dbPath), 'nebras_backups'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory?> _getExternalAppDir() async {
    try {
      final extDirs = await getExternalStorageDirectories();
      if (extDirs != null && extDirs.isNotEmpty) {
        final dir = Directory(p.join(extDirs.first.path, 'NebrasSofT_Backups'));
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        return dir;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _loadBackupInfo() async {
    final dbPath = await DatabaseHelper.instance.getDatabaseFilePath();
    final dbFile = File(dbPath);
    final size = await dbFile.exists() ? await dbFile.length() : 0;
    final backupDir = await _getInternalBackupDir();
    final extDir = await _getExternalAppDir();

    final files = await backupDir.list().toList();
    files.sort((a, b) => b.path.compareTo(a.path));

    if (!mounted) return;
    setState(() {
      _dbPath = dbPath;
      _externalDirPath = extDir?.path ?? 'غير متوفر على هذا الجهاز';
      _dbSizeBytes = size;
      _backups = files;
    });
  }

  Future<void> _createInternalBackup() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await DatabaseHelper.instance.database;
      final dbPath = await DatabaseHelper.instance.getDatabaseFilePath();
      final dbFile = File(dbPath);
      if (!await dbFile.exists()) return;

      final backupDir = await _getInternalBackupDir();
      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final destPath = p.join(backupDir.path, 'nebras_backup_$stamp.db');
      await dbFile.copy(destPath);
      await _loadBackupInfo();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إنشاء نسخة احتياطية في الذاكرة الداخلية بنجاح')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportToExternalOrPickedFolder() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await DatabaseHelper.instance.database;
      final dbPath = await DatabaseHelper.instance.getDatabaseFilePath();
      final dbFile = File(dbPath);
      if (!await dbFile.exists()) return;

      final selectedDir = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'اختر مجلد الذاكرة الداخلية أو بطاقة SD الخارجية',
      );

      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final fileName = 'nebras_soft_pos_backup_$stamp.db';

      if (selectedDir != null && selectedDir.isNotEmpty) {
        final targetPath = p.join(selectedDir, fileName);
        await dbFile.copy(targetPath);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم تصدير النسخة الاحتياطية إلى: $targetPath')),
        );
        return;
      }

      final extDir = await _getExternalAppDir();
      if (extDir != null) {
        final fallbackPath = p.join(extDir.path, fileName);
        await dbFile.copy(fallbackPath);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم حفظ النسخة في التخزين الخارجي للتطبيق: $fallbackPath')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر التصدير إلى المسار المختار، جرّب مشاركة الملف')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreFromAnyStorageFile() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'اختر ملف النسخة الاحتياطية (.db)',
        type: FileType.any,
      );
      if (result == null || result.files.isEmpty) return;
      final pickedPath = result.files.single.path;
      if (pickedPath == null || pickedPath.isEmpty) return;

      final sourceFile = File(pickedPath);
      if (!await sourceFile.exists()) return;

      await _restoreFromFile(sourceFile);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreFromFile(File sourceFile) async {
    await DatabaseHelper.instance.closeDatabase();
    final dbPath = await DatabaseHelper.instance.getDatabaseFilePath();
    await sourceFile.copy(dbPath);
    await DatabaseHelper.instance.database;
    await _loadBackupInfo();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تمت استعادة قاعدة البيانات بنجاح')),
    );
  }

  Future<void> _shareBackupFile(File file) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (!await file.exists()) return;
      final bytes = await file.readAsBytes();
      await Printing.sharePdf(
        bytes: bytes,
        filename: p.basename(file.path),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteBackupFile(File file) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (await file.exists()) {
        await file.delete();
      }
      await _loadBackupInfo();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف النسخة الاحتياطية')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sizeKb = (_dbSizeBytes / 1024).toStringAsFixed(1);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'النسخ الاحتياطي والاستعادة',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF334155),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'حالة قاعدة البيانات المحلية',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 6),
                  Text('الحجم الحالي: $sizeKb KB'),
                  Text(
                    'قاعدة البيانات: $_dbPath',
                    style: const TextStyle(fontSize: 11.5, color: Colors.black54),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'التخزين الخارجي للتطبيق: $_externalDirPath',
                    style: const TextStyle(fontSize: 11.5, color: Colors.black54),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _busy ? null : _createInternalBackup,
                    icon: const Icon(Icons.save),
                    label: Text(_busy ? 'جاري التنفيذ...' : 'نسخة احتياطية في الذاكرة الداخلية'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _exportToExternalOrPickedFolder,
                    icon: const Icon(Icons.sd_storage),
                    label: const Text('تصدير إلى ذاكرة خارجية / مجلد مختار'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _restoreFromAnyStorageFile,
                    icon: const Icon(Icons.restore),
                    label: const Text('استعادة من ملف (داخلية / خارجية)'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'النسخ المحفوظة في الذاكرة الداخلية',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),
          if (_backups.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text('لا توجد نسخ احتياطية محفوظة بعد'),
              ),
            )
          else
            ..._backups.map((entity) {
              final name = p.basename(entity.path);
              final file = File(entity.path);
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.storage, color: Color(0xFF334155)),
                  title: Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                setState(() => _busy = true);
                                try {
                                  await _restoreFromFile(file);
                                } finally {
                                  if (mounted) setState(() => _busy = false);
                                }
                              },
                        child: const Text('استعادة'),
                      ),
                      IconButton(
                        tooltip: 'مشاركة الملف خارج التطبيق',
                        icon: const Icon(Icons.share, size: 20, color: Color(0xFF0369A1)),
                        onPressed: _busy ? null : () => _shareBackupFile(file),
                      ),
                      IconButton(
                        tooltip: 'حذف النسخة',
                        icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                        onPressed: _busy ? null : () => _deleteBackupFile(file),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  String _activeType = 'customer';
  List<DbRow> _contacts = [];
  String _search = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    setState(() => _loading = true);
    final rows = await DatabaseHelper.instance.queryContactsByType(_activeType);
    if (!mounted) return;
    setState(() {
      _contacts = rows;
      _loading = false;
    });
  }

  List<DbRow> get _filteredContacts {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return _contacts;
    return _contacts.where((c) {
      final name = (c['name'] ?? '').toString().toLowerCase();
      final phone = (c['phone'] ?? '').toString().toLowerCase();
      final code = (c['code'] ?? '').toString().toLowerCase();
      final barcode = (c['barcode'] ?? '').toString().toLowerCase();
      return name.contains(q) || phone.contains(q) || code.contains(q) || barcode.contains(q);
    }).toList();
  }

  String _generateContactBarcode() {
    final prefix = _activeType == 'customer' ? '100' : '300';
    return '$prefix${DateTime.now().millisecondsSinceEpoch % 1000000000}';
  }

  Future<void> _openContactDialog({DbRow? existing}) async {
    final isEdit = existing != null;
    final isCustomer = _activeType == 'customer';
    final defaultCode = isCustomer
        ? 'CUS-${DateTime.now().millisecondsSinceEpoch % 100000}'
        : 'SUP-${DateTime.now().millisecondsSinceEpoch % 100000}';

    final codeCtrl = TextEditingController(
      text: existing?['code']?.toString() ?? defaultCode,
    );
    final nameCtrl = TextEditingController(
      text: existing?['name']?.toString() ?? '',
    );
    final barcodeCtrl = TextEditingController(
      text: existing?['barcode']?.toString() ?? '',
    );
    final phoneCtrl = TextEditingController(
      text: existing?['phone']?.toString() ?? '',
    );
    final addressCtrl = TextEditingController(
      text: existing?['address']?.toString() ?? '',
    );
    final limitCtrl = TextEditingController(
      text: (existing?['credit_limit'] ?? 0).toString(),
    );
    final dueDaysCtrl = TextEditingController(
      text: (existing?['due_days'] ?? 30).toString(),
    );
    final balanceCtrl = TextEditingController(
      text: (existing?['balance'] ?? 0).toString(),
    );
    String priceTier = (existing?['price_tier'] ?? 'تجزئة').toString();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            isEdit
                ? (isCustomer ? 'تعديل بيانات العميل' : 'تعديل بيانات المورد')
                : (isCustomer ? 'إضافة عميل جديد' : 'إضافة مورد جديد'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: isCustomer ? 'اسم العميل *' : 'اسم المورد *',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: codeCtrl,
                        decoration: InputDecoration(
                          labelText: isCustomer ? 'رقم العميل' : 'رقم المورد',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'رقم الهاتف',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: barcodeCtrl,
                        decoration: InputDecoration(
                          labelText: isCustomer ? 'باركود العميل' : 'باركود المورد',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: 'توليد باركود',
                      onPressed: () {
                        barcodeCtrl.text = _generateContactBarcode();
                      },
                      icon: const Icon(Icons.qr_code_2, size: 28),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: addressCtrl,
                  decoration: const InputDecoration(
                    labelText: 'العنوان',
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (isCustomer) ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: priceTier,
                    decoration: const InputDecoration(
                      labelText: 'فئة سعر البيع للعميل',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'تجزئة', child: Text('سعر التجزئة')),
                      DropdownMenuItem(value: 'جملة', child: Text('سعر الجملة')),
                      DropdownMenuItem(value: 'خاص', child: Text('سعر خاص')),
                    ],
                    onChanged: (val) {
                      if (val != null) setDialogState(() => priceTier = val);
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: limitCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'سقف الآجل',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: dueDaysCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'مهلة السداد (يوم)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                TextField(
                  controller: balanceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: isCustomer ? 'الرصيد الحالي (مديونية العميل)' : 'الرصيد الحالي (مستحق للمورد)',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('يرجى إدخال الاسم')),
                  );
                  return;
                }

                final row = <String, dynamic>{
                  'code': codeCtrl.text.trim().isEmpty ? null : codeCtrl.text.trim(),
                  'barcode': barcodeCtrl.text.trim().isEmpty ? null : barcodeCtrl.text.trim(),
                  'name': name,
                  'phone': phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
                  'address': addressCtrl.text.trim().isEmpty ? null : addressCtrl.text.trim(),
                  'type': _activeType,
                  'price_tier': priceTier,
                  'credit_limit': double.tryParse(limitCtrl.text.trim()) ?? 0.0,
                  'due_days': int.tryParse(dueDaysCtrl.text.trim()) ?? 30,
                  'balance': double.tryParse(balanceCtrl.text.trim()) ?? 0.0,
                };

                if (isEdit) {
                  row['id'] = existing['id'];
                  await DatabaseHelper.instance.updateContact(row);
                } else {
                  await DatabaseHelper.instance.insertContact(row);
                }

                if (ctx.mounted) Navigator.of(ctx).pop(true);
              },
              child: Text(isEdit ? 'تحديث' : 'حفظ'),
            ),
          ],
        ),
      ),
    );

    if (saved == true) {
      await _loadContacts();
    }
  }

  Future<void> _openVoucherDialog(DbRow contact) async {
    final isCustomer = _activeType == 'customer';
    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    final done = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          isCustomer
              ? 'سند قبض من: ${contact['name']}'
              : 'سند صرف إلى: ${contact['name']}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('الرصيد الحالي: ${contact['balance']}'),
            const SizedBox(height: 10),
            TextField(
              controller: amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'المبلغ المدفوع *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: notesCtrl,
              decoration: const InputDecoration(
                labelText: 'ملاحظات (اختياري)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () async {
              final amt = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
              if (amt <= 0) return;
              await DatabaseHelper.instance.createVoucher(
                contactId: contact['id'] as int,
                type: isCustomer ? 'receipt' : 'payment',
                amount: amt,
                notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
              );
              if (ctx.mounted) Navigator.of(ctx).pop(true);
            },
            child: const Text('تسجيل السند'),
          ),
        ],
      ),
    );

    if (done == true) {
      await _loadContacts();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تسجيل السند وتحديث الرصيد بنجاح')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _filteredContacts;
    final isCustomer = _activeType == 'customer';

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'العملاء والموردين',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF7C3AED),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openContactDialog(),
        backgroundColor: const Color(0xFF7C3AED),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add),
        label: Text(isCustomer ? 'عميل جديد' : 'مورد جديد'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'customer',
                  label: Text('العملاء'),
                  icon: Icon(Icons.person_outline),
                ),
                ButtonSegment(
                  value: 'supplier',
                  label: Text('الموردون'),
                  icon: Icon(Icons.local_shipping_outlined),
                ),
              ],
              selected: {_activeType},
              onSelectionChanged: (sel) {
                setState(() => _activeType = sel.first);
                _loadContacts();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: TextField(
              onChanged: (val) => setState(() => _search = val),
              decoration: InputDecoration(
                hintText: 'ابحث بالاسم أو الهاتف أو الباركود أو الرقم...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : list.isEmpty
                    ? Center(
                        child: Text(
                          isCustomer
                              ? 'لا يوجد عملاء مسجلون بعد، اضغط "عميل جديد"'
                              : 'لا يوجد موردون مسجلون بعد، اضغط "مورد جديد"',
                          style: const TextStyle(color: Colors.black54),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 84),
                        itemCount: list.length,
                        itemBuilder: (context, index) {
                          final c = list[index];
                          final balance = (c['balance'] as num?)?.toDouble() ?? 0.0;
                          final limit = (c['credit_limit'] as num?)?.toDouble() ?? 0.0;
                          final overLimit = isCustomer && limit > 0 && balance >= limit;
                          final phone = c['phone']?.toString() ?? '';
                          final code = c['code']?.toString() ?? '';
                          final tier = (c['price_tier'] ?? 'تجزئة').toString();
                          final int contactId = c['id'] as int;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: ListTile(
                              onTap: () => _openContactDialog(existing: c),
                              title: Text(
                                '${c['name']} ${code.isNotEmpty ? '($code)' : ''}',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                'الرصيد: ${balance.toStringAsFixed(2)}'
                                '${isCustomer ? ' • فئة: $tier' : ''}'
                                '${phone.isNotEmpty ? ' • هاتف: $phone' : ''}'
                                '${isCustomer && limit > 0 ? ' • سقف الآجل: $limit' : ''}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (overLimit)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.red.withAlpha(25),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'تجاوز الحد',
                                        style: TextStyle(
                                          color: Colors.red,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  IconButton(
                                    tooltip: 'كشف حساب PDF',
                                    icon: const Icon(Icons.description_outlined, color: Color(0xFF0369A1)),
                                    onPressed: () => ThermalPdfService.showContactStatementSheet(context, contactId),
                                  ),
                                  IconButton(
                                    tooltip: isCustomer ? 'سند قبض' : 'سند صرف',
                                    icon: const Icon(Icons.payments_outlined, color: Color(0xFF7C3AED)),
                                    onPressed: () => _openVoucherDialog(c),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({super.key});

  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  List<DbRow> _products = [];
  List<DbRow> _suppliers = [];
  List<DbRow> _items = [];
  int? _selectedSupplierId;
  String _paymentMethod = 'نقدي';
  String _search = '';
  bool _loading = true;
  bool _saving = false;

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _discountController = TextEditingController(text: '0');

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _discountController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _loading = true);
    final products = await DatabaseHelper.instance.queryAllProducts();
    final suppliers = await DatabaseHelper.instance.querySuppliers();
    if (!mounted) return;
    setState(() {
      _products = products;
      _suppliers = suppliers;
      _loading = false;
    });
  }

  List<DbRow> get _filteredProducts {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return _products;
    return _products.where((item) {
      final name = (item['name'] ?? '').toString().toLowerCase();
      final barcode = (item['barcode'] ?? '').toString().toLowerCase();
      return name.contains(q) || barcode.contains(q);
    }).toList();
  }

  double get _subTotal {
    double sum = 0.0;
    for (final item in _items) {
      final qty = (item['quantity'] as num).toDouble();
      final price = (item['price'] as num).toDouble();
      sum += qty * price;
    }
    return sum;
  }

  double get _discount => double.tryParse(_discountController.text.trim()) ?? 0.0;

  double get _netTotal {
    final net = _subTotal - _discount;
    return net < 0 ? 0.0 : net;
  }

  void _addProductToPurchase(DbRow product) {
    final int productId = product['id'] as int;
    final double stock = (product['stock_quantity'] as num?)?.toDouble() ?? 0.0;
    final double purchasePrice = (product['purchase_price'] as num?)?.toDouble() ?? 0.0;
    final String name = (product['name'] ?? '').toString();

    final index = _items.indexWhere((e) => e['product_id'] == productId);
    if (index >= 0) {
      setState(() {
        _items[index]['quantity'] = (_items[index]['quantity'] as num).toDouble() + 1;
      });
    } else {
      setState(() {
        _items.add({
          'product_id': productId,
          'name': name,
          'price': purchasePrice,
          'quantity': 1.0,
          'stock_quantity': stock,
        });
      });
    }
  }

  Future<void> _scanBarcodeForPurchase() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const BarcodeScannerScreen(title: 'مسح باركود للمشتريات'),
      ),
    );
    if (code == null || code.isEmpty || !mounted) return;

    final matches = _products.where(
      (item) => (item['barcode'] ?? '').toString().trim() == code.trim(),
    ).toList();

    if (matches.isNotEmpty) {
      _addProductToPurchase(matches.first);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تمت إضافة "${matches.first['name']}" لفاتورة الشراء')),
      );
    } else {
      setState(() {
        _search = code;
        _searchController.text = code;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('لم يتم العثور على صنف بالباركود: $code')),
      );
    }
  }

  Future<void> _editItemDialog(int index) async {
    final current = _items[index];
    final qtyCtrl = TextEditingController(text: current['quantity'].toString());
    final priceCtrl = TextEditingController(text: current['price'].toString());

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('تعديل "${current['name']}"'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: qtyCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'الكمية المشتراة',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: priceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'سعر الشراء للوحدة',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('تطبيق'),
          ),
        ],
      ),
    );

    if (ok == true) {
      final newQty = double.tryParse(qtyCtrl.text.trim()) ?? 0.0;
      final newPrice = double.tryParse(priceCtrl.text.trim()) ?? 0.0;
      if (newQty <= 0) {
        setState(() => _items.removeAt(index));
      } else {
        setState(() {
          _items[index]['quantity'] = newQty;
          _items[index]['price'] = newPrice < 0 ? 0.0 : newPrice;
        });
      }
    }
  }

  Future<void> _quickAddSupplier() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة مورد جديد'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'اسم المورد *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'رقم الهاتف (اختياري)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              final newId = await DatabaseHelper.instance.insertSupplier(
                name,
                phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
              );
              _selectedSupplierId = newId;
              if (ctx.mounted) Navigator.of(ctx).pop(true);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );

    if (created == true) {
      final suppliers = await DatabaseHelper.instance.querySuppliers();
      if (!mounted) return;
      setState(() => _suppliers = suppliers);
    }
  }

  Future<void> _savePurchase() async {
    if (_items.isEmpty || _saving) return;

    if (_paymentMethod == 'آجل' && _selectedSupplierId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار مورد عند تسجيل فاتورة مشتريات آجلة')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final paid = _paymentMethod == 'نقدي' ? _netTotal : 0.0;
      final purNumber = await DatabaseHelper.instance.createPurchaseInvoice(
        purchaseItems: _items,
        totalAmount: _subTotal,
        discount: _discount,
        paidAmount: paid,
        paymentMethod: _paymentMethod,
        supplierId: _selectedSupplierId,
      );

      if (!mounted) return;
      setState(() {
        _items.clear();
        _discountController.text = '0';
        _saving = false;
      });
      await _loadInitialData();
      if (!mounted) return;
      await ThermalPdfService.showInvoiceActionSheet(context, purNumber);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حدث خطأ أثناء حفظ فاتورة المشتريات')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = _filteredProducts;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'فواتير المشتريات',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: const Color(0xFFD97706),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int?>(
                    value: _selectedSupplierId,
                    decoration: InputDecoration(
                      labelText: 'المورد (اختياري للنقدي)',
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('مورد نقدي عام'),
                      ),
                      ..._suppliers.map(
                        (s) => DropdownMenuItem<int?>(
                          value: s['id'] as int,
                          child: Text((s['name'] ?? '').toString()),
                        ),
                      ),
                    ],
                    onChanged: (val) => setState(() => _selectedSupplierId = val),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _quickAddSupplier,
                  style: IconButton.styleFrom(backgroundColor: const Color(0xFFD97706)),
                  tooltip: 'إضافة مورد',
                  icon: const Icon(Icons.person_add_alt_1),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _search = val),
                    decoration: InputDecoration(
                      hintText: 'اختر صنفاً لإضافته لفاتورة الشراء...',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _scanBarcodeForPurchase,
                  style: IconButton.styleFrom(backgroundColor: const Color(0xFFD97706)),
                  tooltip: 'مسح باركود بالكاميرا',
                  icon: const Icon(Icons.qr_code_scanner),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 4,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : products.isEmpty
                    ? const Center(child: Text('أضف أصنافاً أولاً من شاشة إدارة الأصناف'))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: products.length,
                        itemBuilder: (context, index) {
                          final pRow = products[index];
                          final qty = (pRow['stock_quantity'] as num?)?.toDouble() ?? 0.0;
                          final cost = (pRow['purchase_price'] as num?)?.toDouble() ?? 0.0;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 6),
                            child: ListTile(
                              dense: true,
                              onTap: () => _addProductToPurchase(pRow),
                              title: Text(
                                (pRow['name'] ?? '').toString(),
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text('المخزون الحالي: $qty • آخر شراء: $cost'),
                              trailing: const Icon(Icons.add_shopping_cart, color: Color(0xFFD97706)),
                            ),
                          );
                        },
                      ),
          ),
          const Divider(height: 1),
          Expanded(
            flex: 5,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'أصناف فاتورة الشراء (اضغط لتعديل السعر/الكمية)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      Text(
                        'الصافي: ${_netTotal.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Color(0xFFD97706),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: _items.isEmpty
                        ? const Center(
                            child: Text(
                              'اضغط على أي صنف بالأعلى لإضافته لفاتورة الشراء',
                              style: TextStyle(color: Colors.black54),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _items.length,
                            itemBuilder: (context, index) {
                              final item = _items[index];
                              final qty = (item['quantity'] as num).toDouble();
                              final price = (item['price'] as num).toDouble();
                              final total = qty * price;

                              return ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                onTap: () => _editItemDialog(index),
                                title: Text(
                                  item['name'].toString(),
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text('الكمية: $qty × السعر: $price = ${total.toStringAsFixed(2)}'),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                  onPressed: () => setState(() => _items.removeAt(index)),
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _discountController,
                          onChanged: (_) => setState(() {}),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'الخصم',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _paymentMethod,
                          decoration: const InputDecoration(
                            labelText: 'طريقة الدفع',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'نقدي', child: Text('نقدي')),
                            DropdownMenuItem(value: 'آجل', child: Text('آجل')),
                          ],
                          onChanged: (val) {
                            if (val != null) setState(() => _paymentMethod = val);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFD97706),
                      ),
                      onPressed: _items.isEmpty || _saving ? null : _savePurchase,
                      icon: const Icon(Icons.save_alt),
                      label: Text(_saving ? 'جاري الحفظ...' : 'حفظ فاتورة المشتريات'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  List<DbRow> _products = [];
  List<DbRow> _categories = [];
  List<DbRow> _customers = [];
  List<DbRow> _cart = [];
  int? _selectedCustomerId;
  int? _selectedCategoryId;
  String _paymentMethod = 'نقدي';
  String _search = '';
  bool _loading = true;
  bool _saving = false;

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _discountController = TextEditingController(text: '0');

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _discountController.dispose();
    super.dispose();
  }

  String get _activePriceTier {
    if (_selectedCustomerId == null) return 'تجزئة';
    final customer = _customers.firstWhere(
      (c) => c['id'] == _selectedCustomerId,
      orElse: () => <String, dynamic>{},
    );
    final tier = (customer['price_tier'] ?? 'تجزئة').toString().trim();
    return tier.isEmpty ? 'تجزئة' : tier;
  }

  double _resolveProductPrice(DbRow product, String tier) {
    final double retail = (product['sale_price'] as num?)?.toDouble() ?? 0.0;
    final double wholesale = (product['wholesale_price'] as num?)?.toDouble() ?? 0.0;
    final double special = (product['special_price'] as num?)?.toDouble() ?? 0.0;

    if (tier == 'جملة' && wholesale > 0) {
      return wholesale;
    }
    if (tier == 'خاص' && special > 0) {
      return special;
    }
    return retail;
  }

  void _recalculateCartPrices() {
    final tier = _activePriceTier;
    for (final item in _cart) {
      final int pid = item['product_id'] as int;
      final prod = _products.firstWhere(
        (p) => p['id'] == pid,
        orElse: () => <String, dynamic>{},
      );
      if (prod.isNotEmpty) {
        item['price'] = _resolveProductPrice(prod, tier);
      }
    }
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final rows = await DatabaseHelper.instance.queryAllProducts();
    final cats = await DatabaseHelper.instance.queryAllCategories();
    final customers = await DatabaseHelper.instance.queryCustomers();
    if (!mounted) return;
    setState(() {
      _products = rows;
      _categories = cats;
      _customers = customers;
      _recalculateCartPrices();
      _loading = false;
    });
  }

  List<DbRow> get _filteredProducts {
    final q = _search.trim().toLowerCase();
    return _products.where((item) {
      if (_selectedCategoryId != null && item['category_id'] != _selectedCategoryId) {
        return false;
      }
      if (q.isEmpty) return true;
      final name = (item['name'] ?? '').toString().toLowerCase();
      final barcode = (item['barcode'] ?? '').toString().toLowerCase();
      return name.contains(q) || barcode.contains(q);
    }).toList();
  }

  double get _subTotal {
    double sum = 0.0;
    for (final item in _cart) {
      final qty = (item['quantity'] as num).toDouble();
      final price = (item['price'] as num).toDouble();
      sum += qty * price;
    }
    return sum;
  }

  double get _discount => double.tryParse(_discountController.text.trim()) ?? 0.0;

  double get _netTotal {
    final net = _subTotal - _discount;
    return net < 0 ? 0.0 : net;
  }

  void _addToCart(DbRow product) {
    final int productId = product['id'] as int;
    final double stock = (product['stock_quantity'] as num?)?.toDouble() ?? 0.0;
    final double price = _resolveProductPrice(product, _activePriceTier);
    final String name = (product['name'] ?? '').toString();

    final index = _cart.indexWhere((c) => c['product_id'] == productId);
    if (index >= 0) {
      final currentQty = (_cart[index]['quantity'] as num).toDouble();
      if (stock > 0 && currentQty + 1 > stock) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('الكمية المتوفرة للصنف "$name" هي $stock فقط')),
        );
        return;
      }
      setState(() {
        _cart[index]['quantity'] = currentQty + 1;
        _cart[index]['price'] = price;
      });
    } else {
      if (stock <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('الصنف "$name" غير متوفر في المخزون حالياً')),
        );
        return;
      }
      setState(() {
        _cart.add({
          'product_id': productId,
          'name': name,
          'price': price,
          'quantity': 1.0,
          'stock_quantity': stock,
        });
      });
    }
  }

  Future<void> _scanBarcodeForPos() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const BarcodeScannerScreen(title: 'مسح باركود البيع (POS)'),
      ),
    );
    if (code == null || code.isEmpty || !mounted) return;

    final matches = _products.where(
      (item) => (item['barcode'] ?? '').toString().trim() == code.trim(),
    ).toList();

    if (matches.isNotEmpty) {
      _addToCart(matches.first);
    } else {
      setState(() {
        _search = code;
        _searchController.text = code;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('لا يوجد صنف مسجل بالباركود: $code')),
      );
    }
  }

  void _changeQty(int index, double delta) {
    final currentQty = (_cart[index]['quantity'] as num).toDouble();
    final stock = (_cart[index]['stock_quantity'] as num).toDouble();
    final nextQty = currentQty + delta;

    if (nextQty <= 0) {
      setState(() => _cart.removeAt(index));
      return;
    }
    if (delta > 0 && nextQty > stock) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('الحد الأقصى المتوفر هو $stock')),
      );
      return;
    }
    setState(() {
      _cart[index]['quantity'] = nextQty;
    });
  }

  Future<void> _checkout() async {
    if (_cart.isEmpty || _saving) return;

    if (_paymentMethod == 'آجل') {
      if (_selectedCustomerId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يرجى اختيار عميل مسجل عند البيع الآجل')),
        );
        return;
      }

      final customer = _customers.firstWhere(
        (c) => c['id'] == _selectedCustomerId,
        orElse: () => <String, dynamic>{},
      );
      final limit = (customer['credit_limit'] as num?)?.toDouble() ?? 0.0;
      final balance = (customer['balance'] as num?)?.toDouble() ?? 0.0;
      if (limit > 0 && (balance + _netTotal) > limit) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تنبيه: الفاتورة ستتجاوز سقف الآجل للعميل ($limit) — رصيده الحالي $balance',
            ),
          ),
        );
        return;
      }
    }

    setState(() => _saving = true);

    try {
      final invNum = await DatabaseHelper.instance.createSaleInvoice(
        cartItems: _cart,
        totalAmount: _subTotal,
        discount: _discount,
        paymentMethod: _paymentMethod,
        customerId: _selectedCustomerId,
      );
      if (!mounted) return;
      setState(() {
        _cart.clear();
        _discountController.text = '0';
        _saving = false;
      });
      await _loadData();
      if (!mounted) return;
      await ThermalPdfService.showInvoiceActionSheet(context, invNum);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حدث خطأ أثناء حفظ الفاتورة')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _filteredProducts;
    final tierLabel = _activePriceTier;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'نقطة البيع (POS)',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF1545B5),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: DropdownButtonFormField<int?>(
              value: _selectedCustomerId,
              decoration: InputDecoration(
                labelText: 'العميل • فئة السعر الحالية: $tierLabel',
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('عميل نقدي عام (سعر تجزئة)'),
                ),
                ..._customers.map(
                  (c) => DropdownMenuItem<int?>(
                    value: c['id'] as int,
                    child: Text(
                      '${c['name']} • ${c['price_tier'] ?? 'تجزئة'} (الرصيد: ${c['balance']})',
                    ),
                  ),
                ),
              ],
              onChanged: (val) {
                setState(() {
                  _selectedCustomerId = val;
                  _recalculateCartPrices();
                });
              },
            ),
          ),
          if (_categories.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('الكل'),
                    selected: _selectedCategoryId == null,
                    onSelected: (_) => setState(() => _selectedCategoryId = null),
                  ),
                  ..._categories.map((cat) {
                    final int cid = cat['id'] as int;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text((cat['name'] ?? '').toString()),
                        selected: _selectedCategoryId == cid,
                        onSelected: (_) => setState(() => _selectedCategoryId = cid),
                      ),
                    );
                  }),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _search = val),
                    decoration: InputDecoration(
                      hintText: 'ابحث بالاسم أو الباركود...',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _scanBarcodeForPos,
                  style: IconButton.styleFrom(backgroundColor: const Color(0xFF1545B5)),
                  tooltip: 'مسح باركود بالكاميرا',
                  icon: const Icon(Icons.qr_code_scanner),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 4,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                    ? const Center(child: Text('لا توجد أصناف مطابقة'))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final pRow = items[index];
                          final qty = (pRow['stock_quantity'] as num?)?.toDouble() ?? 0.0;
                          final price = _resolveProductPrice(pRow, tierLabel);

                          return Card(
                            margin: const EdgeInsets.only(bottom: 6),
                            child: ListTile(
                              dense: true,
                              onTap: () => _addToCart(pRow),
                              title: Text(
                                (pRow['name'] ?? '').toString(),
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text('المتوفر: $qty • ${pRow['category_name'] ?? 'عام'}'),
                              trailing: Text(
                                price.toStringAsFixed(2),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: Color(0xFF1545B5),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
          const Divider(height: 1),
          Expanded(
            flex: 5,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'سلة الفاتورة',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      Text(
                        'الصافي: ${_netTotal.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Color(0xFF0D7C66),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: _cart.isEmpty
                        ? const Center(
                            child: Text(
                              'اضغط على أي صنف بالأعلى أو امسح الباركود بالكاميرا',
                              style: TextStyle(color: Colors.black54),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _cart.length,
                            itemBuilder: (context, index) {
                              final item = _cart[index];
                              final qty = (item['quantity'] as num).toDouble();
                              final price = (item['price'] as num).toDouble();
                              final lineTotal = qty * price;

                              return ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  item['name'].toString(),
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text('${price.toStringAsFixed(2)} × $qty = ${lineTotal.toStringAsFixed(2)}'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.remove_circle_outline),
                                      onPressed: () => _changeQty(index, -1),
                                    ),
                                    Text('$qty'),
                                    IconButton(
                                      icon: const Icon(Icons.add_circle_outline),
                                      onPressed: () => _changeQty(index, 1),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _discountController,
                          onChanged: (_) => setState(() {}),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'الخصم',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _paymentMethod,
                          decoration: const InputDecoration(
                            labelText: 'طريقة الدفع',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'نقدي', child: Text('نقدي')),
                            DropdownMenuItem(value: 'آجل', child: Text('آجل')),
                          ],
                          onChanged: (val) {
                            if (val != null) setState(() => _paymentMethod = val);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: FilledButton.icon(
                      onPressed: _cart.isEmpty || _saving ? null : _checkout,
                      icon: const Icon(Icons.check_circle_outline),
                      label: Text(_saving ? 'جاري الحفظ...' : 'إتمام الفاتورة'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  List<DbRow> _allProducts = [];
  List<DbRow> _categories = [];
  int? _selectedCategoryId;
  String _searchQuery = '';
  bool _loading = true;

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() => _loading = true);
    final rows = await DatabaseHelper.instance.queryAllProducts();
    final cats = await DatabaseHelper.instance.queryAllCategories();
    if (!mounted) return;
    setState(() {
      _allProducts = rows;
      _categories = cats;
      if (_selectedCategoryId != null &&
          !cats.any((c) => c['id'] == _selectedCategoryId)) {
        _selectedCategoryId = null;
      }
      _loading = false;
    });
  }

  Future<void> _openCategoriesManagerDialog() async {
    final nameCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> refreshCats() async {
            final updated = await DatabaseHelper.instance.queryAllCategories();
            setDialogState(() => _categories = updated);
          }

          return AlertDialog(
            title: const Text(
              'إدارة التصنيفات',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: nameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'اسم تصنيف جديد',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0D7C66)),
                          onPressed: () async {
                            final n = nameCtrl.text.trim();
                            if (n.isEmpty) return;
                            await DatabaseHelper.instance.insertCategory(n);
                            nameCtrl.clear();
                            await refreshCats();
                          },
                          child: const Text('إضافة'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ..._categories.map((cat) {
                      final int cid = cat['id'] as int;
                      final String cname = (cat['name'] ?? '').toString();
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.label_outline, color: Color(0xFF0D7C66)),
                        title: Text(cname, style: const TextStyle(fontWeight: FontWeight.bold)),
                        trailing: cname == 'عام'
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                onPressed: () async {
                                  await DatabaseHelper.instance.deleteCategory(cid);
                                  await refreshCats();
                                },
                              ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('إغلاق'),
              ),
            ],
          );
        },
      ),
    );

    await _loadProducts();
  }

  Future<void> _exportProductsCsv() async {
    final rows = <List<dynamic>>[
      [
        'المعرف',
        'الباركود',
        'اسم الصنف',
        'التصنيف',
        'سعر الشراء',
        'سعر التجزئة',
        'سعر الجملة',
        'السعر الخاص',
        'الكمية',
        'الحد الأدنى',
      ],
      ..._allProducts.map((pRow) => [
            pRow['id'] ?? '',
            pRow['barcode'] ?? '',
            pRow['name'] ?? '',
            pRow['category_name'] ?? 'عام',
            ((pRow['purchase_price'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2),
            ((pRow['sale_price'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2),
            ((pRow['wholesale_price'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2),
            ((pRow['special_price'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2),
            (pRow['stock_quantity'] ?? 0).toString(),
            (pRow['min_stock'] ?? 0).toString(),
          ]),
    ];

    await CsvExportService.exportAndShareCsv(
      context: context,
      fileBaseName: 'nebras_products',
      rows: rows,
    );
  }

  List<DbRow> get _filteredProducts {
    final q = _searchQuery.trim().toLowerCase();
    return _allProducts.where((item) {
      if (_selectedCategoryId != null && item['category_id'] != _selectedCategoryId) {
        return false;
      }
      if (q.isEmpty) return true;
      final name = (item['name'] ?? '').toString().toLowerCase();
      final barcode = (item['barcode'] ?? '').toString().toLowerCase();
      return name.contains(q) || barcode.contains(q);
    }).toList();
  }

  String _generateBarcode() {
    final millis = DateTime.now().millisecondsSinceEpoch;
    return '200${millis % 1000000000}';
  }

  Future<void> _scanInProductsSearch() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const BarcodeScannerScreen(title: 'بحث عن صنف بالباركود'),
      ),
    );
    if (code == null || code.isEmpty || !mounted) return;
    setState(() {
      _searchQuery = code;
      _searchController.text = code;
    });
  }

  Future<void> _openProductDialog({DbRow? existingProduct}) async {
    final isEditing = existingProduct != null;
    int? chosenCategoryId = existingProduct?['category_id'] as int?;
    if (chosenCategoryId == null && _categories.isNotEmpty) {
      chosenCategoryId = _categories.first['id'] as int;
    }

    final nameController = TextEditingController(
      text: existingProduct?['name']?.toString() ?? '',
    );
    final barcodeController = TextEditingController(
      text: existingProduct?['barcode']?.toString() ?? '',
    );
    final purchaseController = TextEditingController(
      text: (existingProduct?['purchase_price'] ?? 0).toString(),
    );
    final saleController = TextEditingController(
      text: existingProduct != null ? (existingProduct['sale_price'] ?? '').toString() : '',
    );
    final wholesaleController = TextEditingController(
      text: (existingProduct?['wholesale_price'] ?? 0).toString(),
    );
    final specialController = TextEditingController(
      text: (existingProduct?['special_price'] ?? 0).toString(),
    );
    final qtyController = TextEditingController(
      text: (existingProduct?['stock_quantity'] ?? 0).toString(),
    );
    final minStockController = TextEditingController(
      text: (existingProduct?['min_stock'] ?? 2).toString(),
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text(
              isEditing ? 'تعديل الصنف' : 'إضافة صنف جديد',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'اسم الصنف *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_categories.isNotEmpty)
                    DropdownButtonFormField<int?>(
                      value: chosenCategoryId,
                      decoration: const InputDecoration(
                        labelText: 'التصنيف',
                        border: OutlineInputBorder(),
                      ),
                      items: _categories
                          .map(
                            (c) => DropdownMenuItem<int?>(
                              value: c['id'] as int,
                              child: Text((c['name'] ?? '').toString()),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setDialogState(() => chosenCategoryId = v),
                    ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: barcodeController,
                          decoration: const InputDecoration(
                            labelText: 'الباركود',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'مسح الباركود بالكاميرا',
                        onPressed: () async {
                          final scanned = await Navigator.of(ctx).push<String>(
                            MaterialPageRoute(
                              builder: (_) => const BarcodeScannerScreen(title: 'قراءة باركود الصنف'),
                            ),
                          );
                          if (scanned != null && scanned.isNotEmpty) {
                            barcodeController.text = scanned;
                          }
                        },
                        icon: const Icon(Icons.qr_code_scanner, size: 26),
                      ),
                      IconButton(
                        tooltip: 'توليد باركود تلقائي',
                        onPressed: () {
                          barcodeController.text = _generateBarcode();
                        },
                        icon: const Icon(Icons.qr_code_2, size: 26),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: purchaseController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'سعر الشراء',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: saleController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'سعر البيع (تجزئة) *',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: wholesaleController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'سعر الجملة',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: specialController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'سعر خاص',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: qtyController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'الكمية',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: minStockController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'الحد الأدنى',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () async {
                  final name = nameController.text.trim();
                  final salePrice = double.tryParse(saleController.text.trim()) ?? 0.0;
                  if (name.isEmpty || salePrice <= 0) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('يرجى إدخال اسم الصنف وسعر بيع صحيح')),
                    );
                    return;
                  }

                  final barcodeText = barcodeController.text.trim();
                  final row = <String, dynamic>{
                    'name': name,
                    'category_id': chosenCategoryId,
                    'barcode': barcodeText.isEmpty ? null : barcodeText,
                    'purchase_price': double.tryParse(purchaseController.text.trim()) ?? 0.0,
                    'sale_price': salePrice,
                    'wholesale_price': double.tryParse(wholesaleController.text.trim()) ?? 0.0,
                    'special_price': double.tryParse(specialController.text.trim()) ?? 0.0,
                    'stock_quantity': double.tryParse(qtyController.text.trim()) ?? 0.0,
                    'min_stock': double.tryParse(minStockController.text.trim()) ?? 0.0,
                    'is_active': 1,
                  };

                  if (isEditing) {
                    row['id'] = existingProduct['id'];
                    await DatabaseHelper.instance.updateProduct(row);
                  } else {
                    await DatabaseHelper.instance.insertProduct(row);
                  }

                  if (ctx.mounted) {
                    Navigator.of(ctx).pop(true);
                  }
                },
                child: Text(isEditing ? 'تحديث' : 'حفظ'),
              ),
            ],
          ),
        );
      },
    );

    if (saved == true) {
      await _loadProducts();
    }
  }

  Future<void> _confirmDelete(DbRow product) async {
    final id = product['id'] as int;
    final name = (product['name'] ?? '').toString();
    await DatabaseHelper.instance.deleteProduct(id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم إيقاف الصنف "$name"')),
    );
    await _loadProducts();
  }

  @override
  Widget build(BuildContext context) {
    final items = _filteredProducts;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'إدارة الأصناف',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF0D7C66),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: 'إدارة التصنيفات',
            onPressed: _openCategoriesManagerDialog,
            icon: const Icon(Icons.category_outlined),
          ),
          IconButton(
            tooltip: 'تصدير الأصناف CSV',
            onPressed: _allProducts.isEmpty ? null : _exportProductsCsv,
            icon: const Icon(Icons.table_view),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openProductDialog(),
        backgroundColor: const Color(0xFF0D7C66),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('صنف جديد'),
      ),
      body: Column(
        children: [
          if (_categories.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('الكل'),
                    selected: _selectedCategoryId == null,
                    onSelected: (_) => setState(() => _selectedCategoryId = null),
                  ),
                  ..._categories.map((cat) {
                    final int cid = cat['id'] as int;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text((cat['name'] ?? '').toString()),
                        selected: _selectedCategoryId == cid,
                        onSelected: (_) => setState(() => _selectedCategoryId = cid),
                      ),
                    );
                  }),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val),
                    decoration: InputDecoration(
                      hintText: 'ابحث باسم الصنف أو الباركود...',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _scanInProductsSearch,
                  style: IconButton.styleFrom(backgroundColor: const Color(0xFF0D7C66)),
                  tooltip: 'مسح باركود بالكاميرا',
                  icon: const Icon(Icons.qr_code_scanner),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                    ? const Center(
                        child: Text(
                          'لا توجد أصناف مضافة بعد، اضغط "صنف جديد" للبدء',
                          style: TextStyle(fontSize: 15, color: Colors.black54),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 84),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final pRow = items[index];
                          final qty = (pRow['stock_quantity'] as num?)?.toDouble() ?? 0.0;
                          final minStock = (pRow['min_stock'] as num?)?.toDouble() ?? 0.0;
                          final isLow = qty <= minStock;
                          final barcode = pRow['barcode']?.toString();
                          final catName = (pRow['category_name'] ?? 'عام').toString();
                          final wholesale = (pRow['wholesale_price'] as num?)?.toDouble() ?? 0.0;
                          final special = (pRow['special_price'] as num?)?.toDouble() ?? 0.0;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: ListTile(
                              onTap: () => _openProductDialog(existingProduct: pRow),
                              title: Text(
                                (pRow['name'] ?? '').toString(),
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                'تصنيف: $catName • تجزئة: ${pRow['sale_price']}'
                                '${wholesale > 0 ? ' • جملة: $wholesale' : ''}'
                                '${special > 0 ? ' • خاص: $special' : ''}'
                                ' • الكمية: $qty'
                                '${barcode != null && barcode.isNotEmpty ? ' • باركود: $barcode' : ''}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isLow)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.red.withAlpha(25),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text(
                                        'نواقص',
                                        style: TextStyle(
                                          color: Colors.red,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  IconButton(
                                    tooltip: 'توليد وطباعة الباركود',
                                    icon: const Icon(Icons.qr_code, color: Color(0xFF0369A1)),
                                    onPressed: () => ThermalPdfService.printProductBarcodeLabel(
                                      context,
                                      pRow,
                                      onBarcodeSaved: _loadProducts,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                    onPressed: () => _confirmDelete(pRow),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
