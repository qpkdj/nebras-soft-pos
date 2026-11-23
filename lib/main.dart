import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:sqflite/sqflite.dart';

typedef DbRow = Map<String, dynamic>;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NebrasPosApp());
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
      version: 2,
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
        name $textType,
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
      CREATE TABLE settings (
        id $idType,
        key $textType UNIQUE,
        value $textType
      )
    ''');

    await db.insert('settings', {'key': 'shop_name', 'value': 'نبراس SofT لنقاط البيع'});
    await db.insert('settings', {'key': 'shop_phone', 'value': ''});
    await db.insert('settings', {'key': 'shop_address', 'value': ''});
    await db.insert('settings', {'key': 'currency_name', 'value': 'YER'});
    await db.insert('settings', {'key': 'currency_symbol', 'value': 'ر.ي'});
    await db.insert('settings', {'key': 'tax_percentage', 'value': '0'});
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
    };
    for (final r in rows) {
      final k = r['key']?.toString();
      final v = r['value']?.toString() ?? '';
      if (k != null && k.isNotEmpty) {
        map[k] = v;
      }
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
    return await db.query(
      'products',
      where: 'is_active = 1',
      orderBy: 'id DESC',
    );
  }

  Future<int> updateProduct(DbRow row) async {
    final db = await instance.database;
    final int id = row['id'] as int;
    return await db.update('products', row, where: 'id = ?', whereArgs: [id]);
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
      final isSale = inv['type'] == 'sale';
      final method = (inv['payment_method'] ?? '').toString();
      final total = (inv['total_amount'] as num?)?.toDouble() ?? 0.0;
      movements.add({
        'date': (inv['date'] ?? '').toString(),
        'reference': (inv['invoice_number'] ?? '').toString(),
        'description': isSale ? 'فاتورة مبيعات ($method)' : 'فاتورة مشتريات ($method)',
        'amount': total,
        'kind': isSale ? 'sale' : 'purchase',
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

  Future<DbRow> getFinancialSummary() async {
    final db = await instance.database;

    final salesRows = await db.rawQuery(
      "SELECT COALESCE(SUM(total_amount), 0) AS total FROM invoices WHERE type = 'sale'",
    );
    final purchasesRows = await db.rawQuery(
      "SELECT COALESCE(SUM(total_amount), 0) AS total FROM invoices WHERE type = 'purchase'",
    );
    final cogsRows = await db.rawQuery('''
      SELECT COALESCE(SUM(ii.quantity * p.purchase_price), 0) AS cost
      FROM invoice_items ii
      INNER JOIN invoices inv ON inv.id = ii.invoice_id
      LEFT JOIN products p ON p.id = ii.product_id
      WHERE inv.type = 'sale'
    ''');
    final recentInvoices = await db.query(
      'invoices',
      orderBy: 'id DESC',
      limit: 20,
    );
    final lowStockProducts = await db.rawQuery(
      'SELECT * FROM products WHERE is_active = 1 AND stock_quantity <= min_stock ORDER BY stock_quantity ASC',
    );

    final totalSales = (salesRows.first['total'] as num?)?.toDouble() ?? 0.0;
    final totalPurchases = (purchasesRows.first['total'] as num?)?.toDouble() ?? 0.0;
    final totalCogs = (cogsRows.first['cost'] as num?)?.toDouble() ?? 0.0;
    final grossProfit = totalSales - totalCogs;

    return {
      'totalSales': totalSales,
      'totalPurchases': totalPurchases,
      'totalCogs': totalCogs,
      'grossProfit': grossProfit,
      'recentInvoices': recentInvoices,
      'lowStockProducts': lowStockProducts,
    };
  }
}

class ThermalPdfService {
  static Future<Uint8List> buildReceiptPdf({
    required DbRow invoice,
    required List<DbRow> items,
    required Map<String, String> settings,
    bool is80mm = true,
  }) async {
    final fontRegular = await PdfGoogleFonts.cairoRegular();
    final fontBold = await PdfGoogleFonts.cairoBold();

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: fontRegular,
        bold: fontBold,
      ),
    );

    final pageFormat = is80mm ? PdfPageFormat.roll80 : PdfPageFormat.roll57;
    final bool isSale = invoice['type'] == 'sale';
    final String shopName = (settings['shop_name'] ?? 'نبراس SofT لنقاط البيع').trim();
    final String shopPhone = (settings['shop_phone'] ?? '').trim();
    final String shopAddress = (settings['shop_address'] ?? '').trim();
    final String currency = (settings['currency_symbol'] ?? 'ر.ي').trim();

    final String invNum = (invoice['invoice_number'] ?? '').toString();
    final String rawDate = (invoice['date'] ?? '').toString();
    final String formattedDate = rawDate.replaceFirst('T', ' ').split('.').first;
    final String contactName = (invoice['contact_name'] ?? (isSale ? 'عميل نقدي عام' : 'مورد نقدي عام')).toString();
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
                  isSale ? 'فاتورة مبيعات' : 'فاتورة مشتريات',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 4),
                pw.Divider(thickness: 0.8),
                pw.Text('رقم الفاتورة: $invNum', style: const pw.TextStyle(fontSize: 8.5)),
                pw.Text('التاريخ: $formattedDate', style: const pw.TextStyle(fontSize: 8.5)),
                pw.Text(
                  '${isSale ? 'العميل' : 'المورد'}: $contactName',
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
                      'الصافي المستحق:',
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
                  'شكراً لتعاملكم معنا • Nebras SofT Pos',
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
    bool is80mm = true,
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
    bool is80mm = true,
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

  static Future<void> showInvoiceActionSheet(BuildContext context, String invoiceNumber) async {
    bool is80mm = true;

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
                'فاتورة رقم: $invoiceNumber',
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
                      label: const Text('طباعة حرارية / PDF'),
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
  int _productsCount = 0;
  String _shopName = 'نبراس SofT لنقاط البيع';
  String _currencySymbol = 'ر.ي';
  bool _dbReady = false;

  static const List<_ModuleItem> _modules = [
    _ModuleItem('نقطة البيع (POS)', Icons.point_of_sale, Color(0xFF1545B5)),
    _ModuleItem('إدارة الأصناف', Icons.inventory_2, Color(0xFF0D7C66)),
    _ModuleItem('فواتير المشتريات', Icons.shopping_cart, Color(0xFFD97706)),
    _ModuleItem('العملاء والموردين', Icons.people, Color(0xFF7C3AED)),
    _ModuleItem('التقارير والأرباح', Icons.bar_chart, Color(0xFFDC2626)),
    _ModuleItem('النسخ الاحتياطي', Icons.settings_backup_restore, Color(0xFF334155)),
    _ModuleItem('الإعدادات', Icons.settings, Color(0xFF0369A1)),
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
        _dbReady = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _dbReady = true;
      });
    }
  }

  Future<void> _onModuleTap(String moduleName) async {
    Widget? targetScreen;
    if (moduleName == 'إدارة الأصناف') {
      targetScreen = const ProductsScreen();
    } else if (moduleName == 'نقطة البيع (POS)') {
      targetScreen = const PosScreen();
    } else if (moduleName == 'فواتير المشتريات') {
      targetScreen = const PurchasesScreen();
    } else if (moduleName == 'العملاء والموردين') {
      targetScreen = const ContactsScreen();
    } else if (moduleName == 'التقارير والأرباح') {
      targetScreen = const ReportsScreen();
    } else if (moduleName == 'النسخ الاحتياطي') {
      targetScreen = const BackupScreen();
    } else if (moduleName == 'الإعدادات') {
      targetScreen = const SettingsScreen();
    }

    if (targetScreen != null) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => targetScreen!),
      );
      _refreshStats();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Nebras SofT Pos',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF0F2C7E),
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
                              fontSize: 14,
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
  double _totalSales = 0.0;
  double _totalPurchases = 0.0;
  double _grossProfit = 0.0;
  List<DbRow> _recentInvoices = [];
  List<DbRow> _lowStock = [];

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _loadReport() async {
    setState(() => _loading = true);
    final summary = await DatabaseHelper.instance.getFinancialSummary();
    if (!mounted) return;
    setState(() {
      _totalSales = (summary['totalSales'] as num?)?.toDouble() ?? 0.0;
      _totalPurchases = (summary['totalPurchases'] as num?)?.toDouble() ?? 0.0;
      _grossProfit = (summary['grossProfit'] as num?)?.toDouble() ?? 0.0;
      _recentInvoices = (summary['recentInvoices'] as List<DbRow>?) ?? [];
      _lowStock = (summary['lowStockProducts'] as List<DbRow>?) ?? [];
      _loading = false;
    });
  }

  Widget _buildStatCard(String title, double value, Color color) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: Colors.black54, fontSize: 13)),
            const SizedBox(height: 6),
            Text(
              value.toStringAsFixed(2),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 18,
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
      appBar: AppBar(
        title: const Text(
          'التقارير والأرباح',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: const Color(0xFFDC2626),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            onPressed: _loadReport,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadReport,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1.55,
                    children: [
                      _buildStatCard('إجمالي المبيعات', _totalSales, const Color(0xFF1545B5)),
                      _buildStatCard('إجمالي المشتريات', _totalPurchases, const Color(0xFFD97706)),
                      _buildStatCard(
                        'صافي الربح التقديري',
                        _grossProfit,
                        _grossProfit >= 0 ? const Color(0xFF0D7C66) : Colors.red,
                      ),
                      _buildStatCard('أصناف النواقص', _lowStock.length.toDouble(), Colors.redAccent),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'آخر الفواتير المسجلة (اضغط لطباعة أو مشاركة PDF)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  if (_recentInvoices.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('لا توجد فواتير مسجلة حتى الآن'),
                      ),
                    )
                  else
                    ..._recentInvoices.map((inv) {
                      final isSale = inv['type'] == 'sale';
                      final method = inv['payment_method']?.toString() ?? '';
                      final invNum = (inv['invoice_number'] ?? '').toString();
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          onTap: () => ThermalPdfService.showInvoiceActionSheet(context, invNum),
                          leading: CircleAvatar(
                            backgroundColor: (isSale ? Colors.blue : Colors.orange).withAlpha(25),
                            child: Icon(
                              isSale ? Icons.arrow_upward : Icons.arrow_downward,
                              color: isSale ? const Color(0xFF1545B5) : const Color(0xFFD97706),
                            ),
                          ),
                          title: Text(
                            '$invNum (${isSale ? 'بيع' : 'شراء'})',
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
                              const Icon(Icons.print_outlined, size: 20, color: Colors.black54),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
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
  int _dbSizeBytes = 0;
  List<FileSystemEntity> _backups = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadBackupInfo();
  }

  Future<Directory> _getBackupDir() async {
    final dbPath = await DatabaseHelper.instance.getDatabaseFilePath();
    final dir = Directory(p.join(p.dirname(dbPath), 'nebras_backups'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> _loadBackupInfo() async {
    final dbPath = await DatabaseHelper.instance.getDatabaseFilePath();
    final dbFile = File(dbPath);
    final size = await dbFile.exists() ? await dbFile.length() : 0;
    final backupDir = await _getBackupDir();
    final files = await backupDir.list().toList();
    files.sort((a, b) => b.path.compareTo(a.path));

    if (!mounted) return;
    setState(() {
      _dbPath = dbPath;
      _dbSizeBytes = size;
      _backups = files;
    });
  }

  Future<void> _createBackup() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await DatabaseHelper.instance.database;
      final dbPath = await DatabaseHelper.instance.getDatabaseFilePath();
      final dbFile = File(dbPath);
      if (!await dbFile.exists()) return;

      final backupDir = await _getBackupDir();
      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final destPath = p.join(backupDir.path, 'nebras_backup_$stamp.db');
      await dbFile.copy(destPath);
      await _loadBackupInfo();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إنشاء نسخة احتياطية محلية بنجاح')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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

  Future<void> _restoreBackup(File backupFile) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await DatabaseHelper.instance.closeDatabase();
      final dbPath = await DatabaseHelper.instance.getDatabaseFilePath();
      await backupFile.copy(dbPath);
      await DatabaseHelper.instance.database;
      await _loadBackupInfo();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تمت استعادة النسخة الاحتياطية بنجاح')),
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
          'النسخ الاحتياطي',
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'حالة قاعدة البيانات المحلية',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  Text('الحجم الحالي: $sizeKb KB'),
                  const SizedBox(height: 4),
                  Text(
                    'المسار: $_dbPath',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _createBackup,
                      icon: const Icon(Icons.backup),
                      label: Text(_busy ? 'جاري التنفيذ...' : 'إنشاء نسخة احتياطية الآن'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'النسخ الاحتياطية المحفوظة',
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
                        onPressed: _busy ? null : () => _restoreBackup(file),
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

  final TextEditingController _discountController = TextEditingController(text: '0');

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
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
            child: TextField(
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
  List<DbRow> _customers = [];
  List<DbRow> _cart = [];
  int? _selectedCustomerId;
  String _paymentMethod = 'نقدي';
  String _search = '';
  bool _loading = true;
  bool _saving = false;

  final TextEditingController _discountController = TextEditingController(text: '0');

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _discountController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final rows = await DatabaseHelper.instance.queryAllProducts();
    final customers = await DatabaseHelper.instance.queryCustomers();
    if (!mounted) return;
    setState(() {
      _products = rows;
      _customers = customers;
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
    final double price = (product['sale_price'] as num?)?.toDouble() ?? 0.0;
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
                labelText: 'العميل (افتراضي: عميل نقدي)',
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
                  child: Text('عميل نقدي عام'),
                ),
                ..._customers.map(
                  (c) => DropdownMenuItem<int?>(
                    value: c['id'] as int,
                    child: Text('${c['name']} (الرصيد: ${c['balance']})'),
                  ),
                ),
              ],
              onChanged: (val) => setState(() => _selectedCustomerId = val),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
            child: TextField(
              onChanged: (val) => setState(() => _search = val),
              decoration: InputDecoration(
                hintText: 'ابحث بالاسم أو الباركود لإضافة الصنف للفاتورة...',
                prefixIcon: const Icon(Icons.qr_code_scanner),
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
                          final price = (pRow['sale_price'] as num?)?.toDouble() ?? 0.0;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 6),
                            child: ListTile(
                              dense: true,
                              onTap: () => _addToCart(pRow),
                              title: Text(
                                (pRow['name'] ?? '').toString(),
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text('المتوفر: $qty'),
                              trailing: Text(
                                '$price',
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
                              'اضغط على أي صنف بالأعلى لإضافته إلى الفاتورة',
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
                                subtitle: Text('$price × $qty = ${lineTotal.toStringAsFixed(2)}'),
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
  String _searchQuery = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() => _loading = true);
    final rows = await DatabaseHelper.instance.queryAllProducts();
    if (!mounted) return;
    setState(() {
      _allProducts = rows;
      _loading = false;
    });
  }

  List<DbRow> get _filteredProducts {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _allProducts;
    return _allProducts.where((item) {
      final name = (item['name'] ?? '').toString().toLowerCase();
      final barcode = (item['barcode'] ?? '').toString().toLowerCase();
      return name.contains(q) || barcode.contains(q);
    }).toList();
  }

  String _generateBarcode() {
    final millis = DateTime.now().millisecondsSinceEpoch;
    return '200${millis % 1000000000}';
  }

  Future<void> _openProductDialog({DbRow? existingProduct}) async {
    final isEditing = existingProduct != null;
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
    final qtyController = TextEditingController(
      text: (existingProduct?['stock_quantity'] ?? 0).toString(),
    );
    final minStockController = TextEditingController(
      text: (existingProduct?['min_stock'] ?? 2).toString(),
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
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
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: 'توليد باركود تلقائي',
                      onPressed: () {
                        barcodeController.text = _generateBarcode();
                      },
                      icon: const Icon(Icons.qr_code_2, size: 28),
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
                          labelText: 'سعر البيع *',
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
                  'barcode': barcodeText.isEmpty ? null : barcodeText,
                  'purchase_price': double.tryParse(purchaseController.text.trim()) ?? 0.0,
                  'sale_price': salePrice,
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
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
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
                                'البيع: ${pRow['sale_price']} • الشراء: ${pRow['purchase_price']} • الكمية: $qty'
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
