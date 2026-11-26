// =============================================================================
// القسم (1 من 10): الاستيرادات، التعريفات، تشغيل التطبيق، وخدمات الأذونات
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:sqflite/sqflite.dart';
import 'package:url_launcher/url_launcher.dart';

typedef DbRow = Map<String, Object?>;
typedef DbRows = List<DbRow>;
typedef StrMap = Map<String, String>;
typedef NumMap = Map<String, double>;
typedef StrMatrix = List<List<String>>;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const NebrasPosApp());
}

class NebrasPosApp extends StatefulWidget {
  const NebrasPosApp({super.key});

  @override
  State<NebrasPosApp> createState() => _NebrasPosAppState();
}

class _NebrasPosAppState extends State<NebrasPosApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppPermissionsService.requestStartupPermissions();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nebras SofT Pos',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', 'YE'),
      supportedLocales: const [
        Locale('ar', 'YE'),
        Locale('ar', 'SA'),
        Locale('ar'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF1545B5),
        scaffoldBackgroundColor: const Color(0xFFF3F4F6),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF1F2937),
          elevation: 0.5,
        ),
      ),
      home: const AppStartupGateScreen(),
    );
  }
}

class ForceUpdateGuardService {
  static Future<void> exitAppCompletely() async {
    try {
      await SystemNavigator.pop();
    } catch (_) {
      exit(0);
    }
  }
}

class AppPermissionsService {
  static Future<void> requestStartupPermissions() async {
    try {
      final permissions = <Permission>[
        Permission.camera,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
        Permission.storage,
        Permission.photos,
        Permission.videos,
        Permission.audio,
        Permission.phone,
        Permission.locationWhenInUse,
        Permission.contacts,
      ];
      await permissions.request();
    } catch (_) {}
  }

  static Future<bool> ensureCameraPermission({bool openSettingsIfDenied = false}) async {
    try {
      var status = await Permission.camera.status;
      if (status.isGranted) return true;

      status = await Permission.camera.request();
      if (status.isGranted) return true;

      if (status.isPermanentlyDenied && openSettingsIfDenied) {
        await openAppSettings();
      }
      return false;
    } catch (_) {
      return true;
    }
  }

  static Future<bool> ensureMicrophonePermission({bool openSettingsIfDenied = false}) async {
    try {
      var status = await Permission.microphone.status;
      if (status.isGranted) return true;

      status = await Permission.microphone.request();
      if (status.isGranted) return true;

      if (status.isPermanentlyDenied && openSettingsIfDenied) {
        await openAppSettings();
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> ensureStoragePermissions() async {
    try {
      await [
        Permission.storage,
        Permission.photos,
        Permission.videos,
        Permission.audio,
      ].request();
    } catch (_) {}
  }
}

class CsvExportService {
  static Future<File> writeCsvAndShare({
    required String fileNamePrefix,
    required List<String> headers,
    required StrMatrix rows,
    String shareSubject = 'تقرير نظام نبراس SofT',
  }) async {
    await AppPermissionsService.ensureStoragePermissions();
    final dir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/${fileNamePrefix}_$ts.csv');

    final buffer = StringBuffer('\uFEFF');
    buffer.writeln(headers.map(_escapeCell).join(','));
    for (final row in rows) {
      buffer.writeln(row.map(_escapeCell).join(','));
    }

    await file.writeAsString(buffer.toString(), encoding: utf8);
    await Share.shareXFiles([XFile(file.path)], text: shareSubject);
    return file;
  }

  static String _escapeCell(String value) {
    final cleaned = value.replaceAll('"', '""').replaceAll('\n', ' ').trim();
    return '"$cleaned"';
  }
}
// =============================================================================
// القسم (2 من 10): محرك قاعدة البيانات المحلية (DatabaseHelper)
// =============================================================================

class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  static const String _dbName = 'nebras_soft_pos.db';
  static const int _dbVersion = 2;
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<String> getDatabaseFilePath() async {
    final dbDir = await getDatabasesPath();
    return p.join(dbDir, _dbName);
  }

  Future<void> closeAndResetForRestore() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
  }

  Future<Database> _initDatabase() async {
    final path = await getDatabaseFilePath();
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        category_id INTEGER,
        barcode TEXT,
        purchase_price REAL DEFAULT 0,
        sale_price REAL DEFAULT 0,
        wholesale_price REAL DEFAULT 0,
        special_price REAL DEFAULT 0,
        stock_quantity REAL DEFAULT 0,
        min_stock REAL DEFAULT 2,
        description TEXT,
        expiry_date TEXT,
        tax_rate TEXT,
        unit_name TEXT,
        unit_pack REAL DEFAULT 0,
        higher_unit TEXT,
        tile_color TEXT,
        image_path TEXT,
        is_active INTEGER DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE contacts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        address TEXT,
        type TEXT NOT NULL DEFAULT 'customer',
        balance REAL DEFAULT 0,
        notes TEXT,
        created_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE invoices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_number TEXT,
        type TEXT NOT NULL,
        contact_id INTEGER,
        contact_name TEXT,
        subtotal REAL DEFAULT 0,
        discount REAL DEFAULT 0,
        tax REAL DEFAULT 0,
        total REAL DEFAULT 0,
        paid REAL DEFAULT 0,
        remaining REAL DEFAULT 0,
        payment_method TEXT DEFAULT 'cash',
        notes TEXT,
        created_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE invoice_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_id INTEGER NOT NULL,
        product_id INTEGER,
        product_name TEXT NOT NULL,
        quantity REAL NOT NULL,
        unit_price REAL NOT NULL,
        cost_price REAL DEFAULT 0,
        total REAL NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE cash_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        category TEXT,
        description TEXT,
        contact_id INTEGER,
        created_at TEXT
      )
    ''');

    const defaultSettings = <String, String>{
      'store_name': 'نبراس SofT',
      'store_phone': '',
      'store_address': '',
      'currency_symbol': 'ريال',
      'exchange_rate': '1',
      'receipt_footer': 'شكراً لتعاملكم معنا',
      'paper_width': '80',
    };
    for (final entry in defaultSettings.entries) {
      await db.insert('settings', {'key': entry.key, 'value': entry.value});
    }

    await db.insert('categories', {'name': 'عام'});
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    const productColumns = [
      'wholesale_price REAL DEFAULT 0',
      'special_price REAL DEFAULT 0',
      'min_stock REAL DEFAULT 2',
      'description TEXT',
      'expiry_date TEXT',
      'tax_rate TEXT',
      'unit_name TEXT',
      'unit_pack REAL DEFAULT 0',
      'higher_unit TEXT',
      'tile_color TEXT',
      'image_path TEXT',
      'is_active INTEGER DEFAULT 1',
    ];
    for (final col in productColumns) {
      try {
        await db.execute('ALTER TABLE products ADD COLUMN $col');
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------------------
  // الإعدادات
  // ---------------------------------------------------------------------------
  Future<StrMap> getSettingsMap() async {
    final db = await database;
    final rows = await db.query('settings');
    final map = StrMap();
    for (final r in rows) {
      final k = (r['key'] ?? '').toString();
      if (k.isNotEmpty) {
        map[k] = (r['value'] ?? '').toString();
      }
    }
    return map;
  }

  Future<void> saveSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ---------------------------------------------------------------------------
  // التصنيفات والمنتجات
  // ---------------------------------------------------------------------------
  Future<DbRows> queryAllCategories() async {
    final db = await database;
    return db.query('categories', orderBy: 'id ASC');
  }

  Future<DbRows> queryAllProducts() async {
    final db = await database;
    return db.query(
      'products',
      where: 'is_active = 1',
      orderBy: 'id DESC',
    );
  }

  Future<int> insertProduct(DbRow row) async {
    final db = await database;
    return db.insert('products', row);
  }

  Future<DbRow?> findProductByBarcode(String barcode) async {
    final code = barcode.trim();
    if (code.isEmpty) return null;
    final db = await database;
    final rows = await db.query(
      'products',
      where: 'barcode = ? AND is_active = 1',
      whereArgs: [code],
      limit: 1,
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  // ---------------------------------------------------------------------------
  // العملاء والموردون
  // ---------------------------------------------------------------------------
  Future<DbRows> queryContacts({String? type}) async {
    final db = await database;
    if (type != null && type.isNotEmpty) {
      return db.query(
        'contacts',
        where: 'type = ?',
        whereArgs: [type],
        orderBy: 'name ASC',
      );
    }
    return db.query('contacts', orderBy: 'name ASC');
  }

  Future<int> insertContact(DbRow row) async {
    final db = await database;
    final data = DbRow.from(row);
    data['created_at'] ??= DateTime.now().toIso8601String();
    return db.insert('contacts', data);
  }

  Future<void> recordContactPayment({
    required int contactId,
    required String contactType,
    required double amount,
    String notes = '',
  }) async {
    if (amount <= 0) return;
    final db = await database;
    final nowStr = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      final rows = await txn.query(
        'contacts',
        where: 'id = ?',
        whereArgs: [contactId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final contact = rows.first;
      final currentBal = (contact['balance'] as num?)?.toDouble() ?? 0.0;
      final nextBal = currentBal - amount;
      final contactName = (contact['name'] ?? '').toString();

      await txn.update(
        'contacts',
        {'balance': nextBal},
        where: 'id = ?',
        whereArgs: [contactId],
      );

      final isCustomer = contactType == 'customer';
      await txn.insert('cash_transactions', {
        'type': isCustomer ? 'in' : 'out',
        'amount': amount,
        'category': isCustomer ? 'سند قبض عميل' : 'سند صرف مورد',
        'description': notes.isNotEmpty
            ? '$contactName - $notes'
            : (isCustomer ? 'تحصيل دفعة من العميل: $contactName' : 'سداد دفعة للمورد: $contactName'),
        'contact_id': contactId,
        'created_at': nowStr,
      });
    });
  }

  // ---------------------------------------------------------------------------
  // فواتير المبيعات والمشتريات
  // ---------------------------------------------------------------------------
  Future<int> createSaleInvoice({
    int? customerId,
    String? customerName,
    required DbRows items,
    double discount = 0.0,
    double tax = 0.0,
    required double paid,
    String paymentMethod = 'cash',
    String notes = '',
    String? invoiceDate,
  }) async {
    final db = await database;
    final nowStr = invoiceDate ?? DateTime.now().toIso8601String();

    double subtotal = 0.0;
    for (final item in items) {
      subtotal += (item['total'] as num?)?.toDouble() ?? 0.0;
    }
    final total = (subtotal - discount + tax).clamp(0.0, double.infinity);
    final remaining = (total - paid).clamp(0.0, double.infinity);

    return db.transaction((txn) async {
      final invNumber = 'SL-${DateTime.now().millisecondsSinceEpoch % 1000000}';
      final invId = await txn.insert('invoices', {
        'invoice_number': invNumber,
        'type': 'sale',
        'contact_id': customerId,
        'contact_name': customerName ?? 'عميل نقدي',
        'subtotal': subtotal,
        'discount': discount,
        'tax': tax,
        'total': total,
        'paid': paid,
        'remaining': remaining,
        'payment_method': paymentMethod,
        'notes': notes,
        'created_at': nowStr,
      });

      for (final item in items) {
        final prodId = item['product_id'] as int?;
        final qty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
        final price = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
        final cost = (item['cost_price'] as num?)?.toDouble() ?? 0.0;
        final lineTotal = (item['total'] as num?)?.toDouble() ?? (qty * price);

        await txn.insert('invoice_items', {
          'invoice_id': invId,
          'product_id': prodId,
          'product_name': (item['product_name'] ?? '').toString(),
          'quantity': qty,
          'unit_price': price,
          'cost_price': cost,
          'total': lineTotal,
        });

        if (prodId != null && qty > 0) {
          await txn.rawUpdate(
            'UPDATE products SET stock_quantity = MAX(0, stock_quantity - ?) WHERE id = ?',
            [qty, prodId],
          );
        }
      }

      if (customerId != null && remaining > 0) {
        await txn.rawUpdate(
          'UPDATE contacts SET balance = balance + ? WHERE id = ?',
          [remaining, customerId],
        );
      }

      if (paid > 0) {
        await txn.insert('cash_transactions', {
          'type': 'in',
          'amount': paid,
          'category': 'مبيعات',
          'description': 'فاتورة مبيعات رقم $invNumber (${customerName ?? 'عميل نقدي'})',
          'contact_id': customerId,
          'created_at': nowStr,
        });
      }

      return invId;
    });
  }

  Future<int> createPurchaseInvoice({
    int? supplierId,
    String? supplierName,
    required DbRows items,
    double discount = 0.0,
    required double paid,
    String paymentMethod = 'cash',
    String notes = '',
    String? invoiceDate,
  }) async {
    final db = await database;
    final nowStr = invoiceDate ?? DateTime.now().toIso8601String();

    double subtotal = 0.0;
    for (final item in items) {
      subtotal += (item['total'] as num?)?.toDouble() ?? 0.0;
    }
    final total = (subtotal - discount).clamp(0.0, double.infinity);
    final remaining = (total - paid).clamp(0.0, double.infinity);

    return db.transaction((txn) async {
      final invNumber = 'PR-${DateTime.now().millisecondsSinceEpoch % 1000000}';
      final invId = await txn.insert('invoices', {
        'invoice_number': invNumber,
        'type': 'purchase',
        'contact_id': supplierId,
        'contact_name': supplierName ?? 'مورد نقدي',
        'subtotal': subtotal,
        'discount': discount,
        'tax': 0.0,
        'total': total,
        'paid': paid,
        'remaining': remaining,
        'payment_method': paymentMethod,
        'notes': notes,
        'created_at': nowStr,
      });

      for (final item in items) {
        final prodId = item['product_id'] as int?;
        final qty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
        final cost = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
        final lineTotal = (item['total'] as num?)?.toDouble() ?? (qty * cost);

        await txn.insert('invoice_items', {
          'invoice_id': invId,
          'product_id': prodId,
          'product_name': (item['product_name'] ?? '').toString(),
          'quantity': qty,
          'unit_price': cost,
          'cost_price': cost,
          'total': lineTotal,
        });

        if (prodId != null && qty > 0) {
          await txn.rawUpdate(
            'UPDATE products SET stock_quantity = stock_quantity + ?, purchase_price = ? WHERE id = ?',
            [qty, cost, prodId],
          );
        }
      }

      if (supplierId != null && remaining > 0) {
        await txn.rawUpdate(
          'UPDATE contacts SET balance = balance + ? WHERE id = ?',
          [remaining, supplierId],
        );
      }

      if (paid > 0) {
        await txn.insert('cash_transactions', {
          'type': 'out',
          'amount': paid,
          'category': 'مشتريات',
          'description': 'فاتورة مشتريات رقم $invNumber (${supplierName ?? 'مورد نقدي'})',
          'contact_id': supplierId,
          'created_at': nowStr,
        });
      }

      return invId;
    });
  }

  Future<DbRows> queryInvoices({String? type, String? datePrefix}) async {
    final db = await database;
    final whereParts = <String>[];
    final args = <Object?>[];

    if (type != null && type.isNotEmpty) {
      whereParts.add('type = ?');
      args.add(type);
    }
    if (datePrefix != null && datePrefix.isNotEmpty) {
      whereParts.add('created_at LIKE ?');
      args.add('$datePrefix%');
    }

    return db.query(
      'invoices',
      where: whereParts.isEmpty ? null : whereParts.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'id DESC',
    );
  }

  Future<DbRows> queryInvoiceItems(int invoiceId) async {
    final db = await database;
    return db.query(
      'invoice_items',
      where: 'invoice_id = ?',
      whereArgs: [invoiceId],
      orderBy: 'id ASC',
    );
  }

  // ---------------------------------------------------------------------------
  // الصندوق والمصاريف والملخص المالي
  // ---------------------------------------------------------------------------
  Future<DbRows> queryCashTransactions({String? datePrefix}) async {
    final db = await database;
    if (datePrefix != null && datePrefix.isNotEmpty) {
      return db.query(
        'cash_transactions',
        where: 'created_at LIKE ?',
        whereArgs: ['$datePrefix%'],
        orderBy: 'id DESC',
      );
    }
    return db.query('cash_transactions', orderBy: 'id DESC');
  }

  Future<int> insertCashTransaction(DbRow row) async {
    final db = await database;
    final data = DbRow.from(row);
    data['created_at'] ??= DateTime.now().toIso8601String();
    return db.insert('cash_transactions', data);
  }

  Future<NumMap> getFinancialSummary({String? datePrefix}) async {
    final db = await database;
    final dateFilter = (datePrefix != null && datePrefix.isNotEmpty) ? '$datePrefix%' : null;

    Future<double> sumQuery(String sql, [List<Object?>? args]) async {
      final res = await db.rawQuery(sql, args);
      if (res.isEmpty) return 0.0;
      final val = res.first.values.first;
      return (val as num?)?.toDouble() ?? 0.0;
    }

    final salesTotal = dateFilter != null
        ? await sumQuery("SELECT COALESCE(SUM(total),0) FROM invoices WHERE type='sale' AND created_at LIKE ?", [dateFilter])
        : await sumQuery("SELECT COALESCE(SUM(total),0) FROM invoices WHERE type='sale'");

    final purchasesTotal = dateFilter != null
        ? await sumQuery("SELECT COALESCE(SUM(total),0) FROM invoices WHERE type='purchase' AND created_at LIKE ?", [dateFilter])
        : await sumQuery("SELECT COALESCE(SUM(total),0) FROM invoices WHERE type='purchase'");

    final grossProfit = dateFilter != null
        ? await sumQuery('''
            SELECT COALESCE(SUM((ii.unit_price - ii.cost_price) * ii.quantity), 0)
            FROM invoice_items ii
            INNER JOIN invoices inv ON inv.id = ii.invoice_id
            WHERE inv.type = 'sale' AND inv.created_at LIKE ?
          ''', [dateFilter])
        : await sumQuery('''
            SELECT COALESCE(SUM((ii.unit_price - ii.cost_price) * ii.quantity), 0)
            FROM invoice_items ii
            INNER JOIN invoices inv ON inv.id = ii.invoice_id
            WHERE inv.type = 'sale'
          ''');

    final expensesTotal = dateFilter != null
        ? await sumQuery("SELECT COALESCE(SUM(amount),0) FROM cash_transactions WHERE type='expense' AND created_at LIKE ?", [dateFilter])
        : await sumQuery("SELECT COALESCE(SUM(amount),0) FROM cash_transactions WHERE type='expense'");

    final cashIn = await sumQuery("SELECT COALESCE(SUM(amount),0) FROM cash_transactions WHERE type='in'");
    final cashOut = await sumQuery("SELECT COALESCE(SUM(amount),0) FROM cash_transactions WHERE type IN ('out', 'expense')");
    final customersDebt = await sumQuery("SELECT COALESCE(SUM(balance),0) FROM contacts WHERE type='customer' AND balance > 0");
    final suppliersDebt = await sumQuery("SELECT COALESCE(SUM(balance),0) FROM contacts WHERE type='supplier' AND balance > 0");
    final inventoryCostValue = await sumQuery("SELECT COALESCE(SUM(stock_quantity * purchase_price),0) FROM products WHERE is_active=1");
    final inventorySaleValue = await sumQuery("SELECT COALESCE(SUM(stock_quantity * sale_price),0) FROM products WHERE is_active=1");

    return {
      'salesTotal': salesTotal,
      'purchasesTotal': purchasesTotal,
      'grossProfit': grossProfit,
      'expensesTotal': expensesTotal,
      'netProfit': grossProfit - expensesTotal,
      'cashIn': cashIn,
      'cashOut': cashOut,
      'cashBalance': cashIn - cashOut,
      'customersDebt': customersDebt,
      'suppliersDebt': suppliersDebt,
      'inventoryCostValue': inventoryCostValue,
      'inventorySaleValue': inventorySaleValue,
    };
  }
}
// =============================================================================
// القسم (3 من 10): قارئ الباركود بالكاميرا (BarcodeScannerScreen) والطباعة الحرارية
// =============================================================================

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
  bool _checkingPermission = true;
  bool _permissionGranted = false;
  bool _torchOn = false;

  @override
  void initState() {
    super.initState();
    _initCameraWithPermission();
  }

  Future<void> _initCameraWithPermission() async {
    setState(() => _checkingPermission = true);
    final granted = await AppPermissionsService.ensureCameraPermission(
      openSettingsIfDenied: false,
    );
    if (!mounted) return;
    if (granted) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
    }
    setState(() {
      _permissionGranted = granted;
      _checkingPermission = false;
    });
  }

  Future<void> _enterBarcodeManually() async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text(
            'إدخال الباركود يدوياً',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'اكتب أو الصق رقم الباركود',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
              child: const Text('تأكيد'),
            ),
          ],
        ),
      ),
    );
    if (code != null && code.isNotEmpty && mounted && !_handled) {
      _handled = true;
      Navigator.of(context).pop(code);
    }
  }

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

  Future<void> _toggleFlash() async {
    try {
      await _controller.toggleTorch();
      if (mounted) {
        setState(() => _torchOn = !_torchOn);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _checkingPermission
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : !_permissionGranted
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.no_photography, size: 52, color: Colors.orange),
                        const SizedBox(height: 12),
                        const Text(
                          'يلزم السماح بإذن الكاميرا لمسح الباركود.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: _initCameraWithPermission,
                          icon: const Icon(Icons.refresh),
                          label: const Text('طلب إذن الكاميرا الآن'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                          onPressed: () async {
                            await AppPermissionsService.ensureCameraPermission(
                              openSettingsIfDenied: true,
                            );
                          },
                          icon: const Icon(Icons.settings),
                          label: const Text('فتح إعدادات التطبيق'),
                        ),
                      ],
                    ),
                  ),
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    MobileScanner(
                      controller: _controller,
                      onDetect: _onDetect,
                      errorBuilder: (context, error, child) {
                        final errDetail = error.errorDetails?.message ?? error.errorCode.name;
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
                                  style: TextStyle(fontSize: 14, color: Colors.white),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'السبب: $errDetail',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                                ),
                                const SizedBox(height: 14),
                                FilledButton.icon(
                                  onPressed: _initCameraWithPermission,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('إعادة تشغيل الكاميرا'),
                                ),
                                const SizedBox(height: 8),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                                  onPressed: _enterBarcodeManually,
                                  icon: const Icon(Icons.keyboard),
                                  label: const Text('إدخال الباركود يدوياً'),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    IgnorePointer(
                      child: CustomPaint(
                        painter: _NsScannerViewfinderPainter(),
                        size: Size.infinite,
                      ),
                    ),
                    SafeArea(
                      child: Directionality(
                        textDirection: TextDirection.ltr,
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  color: const Color(0xFFFF0000),
                                  child: const Text(
                                    'NS-soft-Pos',
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.w900,
                                      fontStyle: FontStyle.italic,
                                      fontSize: 19,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: 'تبديل الكاميرا',
                                      onPressed: () async {
                                        try {
                                          await _controller.switchCamera();
                                        } catch (_) {}
                                      },
                                      icon: const Icon(
                                        Icons.center_focus_strong,
                                        color: Colors.white,
                                        size: 28,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      tooltip: 'تشغيل / إيقاف الفلاش',
                                      onPressed: _toggleFlash,
                                      icon: Icon(
                                        _torchOn ? Icons.flash_on : Icons.flash_off,
                                        color: _torchOn ? const Color(0xFFFACC15) : Colors.white,
                                        size: 28,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    SafeArea(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 18, left: 16, right: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton(
                                style: IconButton.styleFrom(backgroundColor: Colors.black54),
                                tooltip: 'رجوع',
                                icon: const Icon(Icons.arrow_back, color: Colors.white),
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  backgroundColor: Colors.black54,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: _enterBarcodeManually,
                                icon: const Icon(Icons.keyboard, size: 18),
                                label: const Text('إدخال يدوي'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _NsScannerViewfinderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final overlayPaint = Paint()..color = Colors.black.withAlpha(122);
    final boxWidth = size.width * 0.78;
    final boxHeight = size.height * 0.30;
    final left = (size.width - boxWidth) / 2;
    final top = (size.height - boxHeight) / 2;
    final rect = Rect.fromLTWH(left, top, boxWidth, boxHeight);

    final fullPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final holePath = Path()..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(12)));
    final maskPath = Path.combine(PathOperation.difference, fullPath, holePath);
    canvas.drawPath(maskPath, overlayPaint);

    final cornerPaint = Paint()
      ..color = const Color(0xFFEF4444)
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const cLen = 28.0;
    // أعلى يسار
    canvas.drawLine(Offset(left, top + cLen), Offset(left, top), cornerPaint);
    canvas.drawLine(Offset(left, top), Offset(left + cLen, top), cornerPaint);
    // أعلى يمين
    canvas.drawLine(Offset(left + boxWidth - cLen, top), Offset(left + boxWidth, top), cornerPaint);
    canvas.drawLine(Offset(left + boxWidth, top), Offset(left + boxWidth, top + cLen), cornerPaint);
    // أسفل يسار
    canvas.drawLine(Offset(left, top + boxHeight - cLen), Offset(left, top + boxHeight), cornerPaint);
    canvas.drawLine(Offset(left, top + boxHeight), Offset(left + cLen, top + boxHeight), cornerPaint);
    // أسفل يمين
    canvas.drawLine(
      Offset(left + boxWidth - cLen, top + boxHeight),
      Offset(left + boxWidth, top + boxHeight),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(left + boxWidth, top + boxHeight - cLen),
      Offset(left + boxWidth, top + boxHeight),
      cornerPaint,
    );

    final laserPaint = Paint()
      ..color = const Color(0xFFFF1744)
      ..strokeWidth = 2.2;
    final midY = top + (boxHeight / 2);
    canvas.drawLine(Offset(left + 12, midY), Offset(left + boxWidth - 12, midY), laserPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ThermalPrintService {
  static String _escapeHtml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }

  static Future<void> printInvoiceById(int invoiceId) async {
    final db = await DatabaseHelper.instance.database;
    final invRows = await db.query(
      'invoices',
      where: 'id = ?',
      whereArgs: [invoiceId],
      limit: 1,
    );
    if (invRows.isEmpty) return;
    final items = await DatabaseHelper.instance.queryInvoiceItems(invoiceId);
    await printInvoiceData(invoice: invRows.first, items: items);
  }

  static Future<void> printInvoiceData({
    required DbRow invoice,
    required DbRows items,
  }) async {
    final settings = await DatabaseHelper.instance.getSettingsMap();
    final storeName = _escapeHtml((settings['store_name'] ?? 'نبراس SofT').trim());
    final storePhone = _escapeHtml((settings['store_phone'] ?? '').trim());
    final storeAddress = _escapeHtml((settings['store_address'] ?? '').trim());
    final currency = _escapeHtml((settings['currency_symbol'] ?? 'ريال').trim());
    final footer = _escapeHtml((settings['receipt_footer'] ?? 'شكراً لتعاملكم معنا').trim());
    final paperWidth = (settings['paper_width'] ?? '80').trim();

    final isSale = (invoice['type'] ?? 'sale').toString() == 'sale';
    final invTitle = isSale ? 'فاتورة مبيعات' : 'فاتورة مشتريات';
    final invNumber = _escapeHtml((invoice['invoice_number'] ?? '#${invoice['id'] ?? ''}').toString());
    final contactName = _escapeHtml(
      (invoice['contact_name'] ?? (isSale ? 'عميل نقدي' : 'مورد نقدي')).toString(),
    );
    final rawDate = (invoice['created_at'] ?? DateTime.now().toIso8601String()).toString();
    final formattedDate = rawDate.replaceAll('T', ' ').split('.').first;

    final subtotal = (invoice['subtotal'] as num?)?.toDouble() ?? 0.0;
    final discount = (invoice['discount'] as num?)?.toDouble() ?? 0.0;
    final tax = (invoice['tax'] as num?)?.toDouble() ?? 0.0;
    final total = (invoice['total'] as num?)?.toDouble() ?? 0.0;
    final paid = (invoice['paid'] as num?)?.toDouble() ?? 0.0;
    final remaining = (invoice['remaining'] as num?)?.toDouble() ?? 0.0;
    final notes = _escapeHtml((invoice['notes'] ?? '').toString().trim());

    final itemsHtml = StringBuffer();
    for (final item in items) {
      final pName = _escapeHtml((item['product_name'] ?? '').toString());
      final qty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
      final price = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
      final lineTotal = (item['total'] as num?)?.toDouble() ?? (qty * price);
      final qtyText = qty == qty.roundToDouble() ? qty.toInt().toString() : qty.toStringAsFixed(2);

      itemsHtml.writeln('''
        <tr>
          <td class="pname">$pName</td>
          <td>$qtyText</td>
          <td>${price.toStringAsFixed(2)}</td>
          <td>${lineTotal.toStringAsFixed(2)}</td>
        </tr>
      ''');
    }

    final maxPx = paperWidth == '58' ? '210px' : '290px';
    final html = '''
    <!DOCTYPE html>
    <html dir="rtl" lang="ar">
    <head>
      <meta charset="UTF-8">
      <style>
        body {
          font-family: sans-serif;
          direction: rtl;
          margin: 0 auto;
          padding: 8px;
          max-width: $maxPx;
          color: #000;
          font-size: 12px;
        }
        .center { text-align: center; }
        .store { font-size: 16px; font-weight: bold; margin-bottom: 2px; }
        .sub { font-size: 11px; margin: 1px 0; }
        .badge {
          border-top: 1px dashed #000;
          border-bottom: 1px dashed #000;
          padding: 4px 0;
          margin: 6px 0;
          font-weight: bold;
          font-size: 13px;
          text-align: center;
        }
        .meta { font-size: 11.5px; line-height: 1.5; margin-bottom: 6px; }
        table { width: 100%; border-collapse: collapse; margin-top: 4px; font-size: 11px; }
        th {
          border-top: 1px solid #000;
          border-bottom: 1px solid #000;
          padding: 4px 2px;
          text-align: center;
          font-weight: bold;
        }
        td {
          border-bottom: 1px dotted #888;
          padding: 4px 2px;
          text-align: center;
        }
        td.pname { text-align: right; font-weight: 600; }
        .totals {
          margin-top: 8px;
          border-top: 1px dashed #000;
          padding-top: 6px;
          font-size: 12px;
          line-height: 1.6;
        }
        .grand {
          font-size: 14px;
          font-weight: bold;
          border-top: 1px solid #000;
          border-bottom: 1px solid #000;
          padding: 4px 0;
          margin: 4px 0;
        }
        .footer {
          text-align: center;
          margin-top: 10px;
          border-top: 1px dashed #000;
          padding-top: 6px;
          font-size: 11.5px;
        }
      </style>
    </head>
    <body>
      <div class="center">
        <div class="store">$storeName</div>
        ${storeAddress.isNotEmpty ? '<div class="sub">$storeAddress</div>' : ''}
        ${storePhone.isNotEmpty ? '<div class="sub">هاتف: $storePhone</div>' : ''}
      </div>

      <div class="badge">$invTitle</div>

      <div class="meta">
        <div>رقم الفاتورة: <strong>$invNumber</strong></div>
        <div>التاريخ: $formattedDate</div>
        <div>${isSale ? 'العميل' : 'المورد'}: <strong>$contactName</strong></div>
      </div>

      <table>
        <thead>
          <tr>
            <th style="text-align:right;">الصنف</th>
            <th>الكمية</th>
            <th>السعر</th>
            <th>الإجمالي</th>
          </tr>
        </thead>
        <tbody>
          $itemsHtml
        </tbody>
      </table>

      <div class="totals">
        <div>المجموع الفرعي: <strong>${subtotal.toStringAsFixed(2)} $currency</strong></div>
        ${discount > 0 ? '<div>الخصم: <strong>${discount.toStringAsFixed(2)} $currency</strong></div>' : ''}
        ${tax > 0 ? '<div>الضريبة: <strong>${tax.toStringAsFixed(2)} $currency</strong></div>' : ''}
        <div class="grand">الإجمالي النهائي: ${total.toStringAsFixed(2)} $currency</div>
        <div>المدفوع: <strong>${paid.toStringAsFixed(2)} $currency</strong></div>
        <div>المتبقي (الآجل): <strong>${remaining.toStringAsFixed(2)} $currency</strong></div>
        ${notes.isNotEmpty ? '<div>ملاحظات: $notes</div>' : ''}
      </div>

      <div class="footer">
        <div>$footer</div>
        <div style="font-size:10px;margin-top:3px;">Nebras SofT Pos</div>
      </div>
    </body>
    </html>
    ''';

    final pageFormat = paperWidth == '58' ? PdfPageFormat.roll57 : PdfPageFormat.roll80;
    await Printing.layoutPdf(
      format: pageFormat,
      onLayout: (format) => Printing.convertHtml(format: format, html: html),
    );
  }

  static Future<void> printVoucher({
    required String title,
    required String partyLabel,
    required String partyName,
    required double amount,
    double? remainingBalance,
    String notes = '',
    String? dateStr,
  }) async {
    final settings = await DatabaseHelper.instance.getSettingsMap();
    final storeName = _escapeHtml((settings['store_name'] ?? 'نبراس SofT').trim());
    final storePhone = _escapeHtml((settings['store_phone'] ?? '').trim());
    final currency = _escapeHtml((settings['currency_symbol'] ?? 'ريال').trim());
    final paperWidth = (settings['paper_width'] ?? '80').trim();
    final formattedDate =
        (dateStr ?? DateTime.now().toIso8601String()).replaceAll('T', ' ').split('.').first;

    final maxPx = paperWidth == '58' ? '210px' : '290px';
    final html = '''
    <!DOCTYPE html>
    <html dir="rtl" lang="ar">
    <head>
      <meta charset="UTF-8">
      <style>
        body {
          font-family: sans-serif;
          direction: rtl;
          margin: 0 auto;
          padding: 10px;
          max-width: $maxPx;
          font-size: 12.5px;
          line-height: 1.6;
        }
        .center { text-align: center; }
        .store { font-size: 16px; font-weight: bold; }
        .title {
          border-top: 1px dashed #000;
          border-bottom: 1px dashed #000;
          padding: 5px 0;
          margin: 8px 0;
          font-size: 14px;
          font-weight: bold;
          text-align: center;
        }
        .amount-box {
          border: 1px solid #000;
          padding: 6px;
          margin: 8px 0;
          text-align: center;
          font-size: 15px;
          font-weight: bold;
        }
      </style>
    </head>
    <body>
      <div class="center">
        <div class="store">$storeName</div>
        ${storePhone.isNotEmpty ? '<div>هاتف: $storePhone</div>' : ''}
      </div>
      <div class="title">${_escapeHtml(title)}</div>
      <div>التاريخ: $formattedDate</div>
      <div>${_escapeHtml(partyLabel)}: <strong>${_escapeHtml(partyName)}</strong></div>
      <div class="amount-box">المبلغ: ${amount.toStringAsFixed(2)} $currency</div>
      ${remainingBalance != null ? '<div>الرصيد المتبقي: <strong>${remainingBalance.toStringAsFixed(2)} $currency</strong></div>' : ''}
      ${notes.trim().isNotEmpty ? '<div>البيان: ${_escapeHtml(notes.trim())}</div>' : ''}
      <div class="center" style="margin-top:12px;border-top:1px dashed #000;padding-top:6px;font-size:11px;">
        Nebras SofT Pos
      </div>
    </body>
    </html>
    ''';

    final pageFormat = paperWidth == '58' ? PdfPageFormat.roll57 : PdfPageFormat.roll80;
    await Printing.layoutPdf(
      format: pageFormat,
      onLayout: (format) => Printing.convertHtml(format: format, html: html),
    );
  }
}
// =============================================================================
// القسم (4 من 10): الواجهة الرئيسية للتطبيق (HomeDashboardScreen) مع أيقونة الروبوت
// =============================================================================

class HomeDashboardScreen extends StatefulWidget {
  const HomeDashboardScreen({super.key});

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  String _storeName = 'نبراس SofT';
  String _currencySymbol = 'ريال';
  double _todaySales = 0.0;
  double _cashBalance = 0.0;
  int _lowStockCount = 0;
  int _totalProductsCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    try {
      final settings = await DatabaseHelper.instance.getSettingsMap();
      final todayPrefix = DateTime.now().toIso8601String().split('T').first;
      final summary = await DatabaseHelper.instance.getFinancialSummary(
        datePrefix: todayPrefix,
      );
      final products = await DatabaseHelper.instance.queryAllProducts();

      int lowCount = 0;
      for (final prod in products) {
        final stock = (prod['stock_quantity'] as num?)?.toDouble() ?? 0.0;
        final minStock = (prod['min_stock'] as num?)?.toDouble() ?? 2.0;
        if (stock <= minStock) {
          lowCount++;
        }
      }

      if (!mounted) return;
      setState(() {
        final savedName = (settings['store_name'] ?? '').trim();
        _storeName = savedName.isEmpty ? 'نبراس SofT' : savedName;
        final savedCurr = (settings['currency_symbol'] ?? '').trim();
        _currencySymbol = savedCurr.isEmpty ? 'ريال' : savedCurr;
        _todaySales = summary['salesTotal'] ?? 0.0;
        _cashBalance = summary['cashBalance'] ?? 0.0;
        _totalProductsCount = products.length;
        _lowStockCount = lowCount;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _openScreen(Widget screen) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
    await _loadDashboardData();
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color accentColor,
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0D000000),
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ),
                  Icon(icon, size: 18, color: accentColor),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: accentColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModuleTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    String? badgeText,
    Widget? customIconWidget,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1.2,
      shadowColor: const Color(0x1A000000),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Stack(
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  customIconWidget ??
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: color.withAlpha(28),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, size: 28, color: color),
                      ),
                  const SizedBox(height: 10),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
              if (badgeText != null && badgeText.isNotEmpty)
                Positioned(
                  top: 0,
                  left: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      badgeText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F4F6),
        body: SafeArea(
          child: Column(
            children: [
              // الشريط العلوي للنظام
              Container(
                padding: const EdgeInsets.fromLTRB(12, 14, 16, 14),
                decoration: const BoxDecoration(
                  color: Color(0xFF1545B5),
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(38),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.point_of_sale_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _storeName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Nebras SofT Pos • النظام المحاسبي ونقاط البيع',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFFDBEAFE),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // أيقونة شخصية الروبوت لفتح بوت المساعد الذكي
                    InkWell(
                      onTap: () => _openScreen(const NebrasBotChatScreen()),
                      borderRadius: BorderRadius.circular(22),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Tooltip(
                          message: 'مساعد نبراس الذكي',
                          child: NebrasRobotAvatar(size: 38),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'تحديث البيانات',
                      onPressed: _loadDashboardData,
                      icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                    ),
                    IconButton(
                      tooltip: 'الإعدادات والنسخ الاحتياطي',
                      onPressed: () => _openScreen(const BackupAndSettingsScreen()),
                      icon: const Icon(Icons.settings_outlined, color: Colors.white),
                    ),
                  ],
                ),
              ),

              // شريط الملخص السريع (مبيعات اليوم | الصندوق | النواقص)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                child: _loading
                    ? const LinearProgressIndicator(minHeight: 2)
                    : Row(
                        children: [
                          _buildStatCard(
                            title: 'مبيعات اليوم',
                            value: '${_todaySales.toStringAsFixed(1)} $_currencySymbol',
                            icon: Icons.trending_up_rounded,
                            accentColor: const Color(0xFF16A34A),
                            onTap: () => _openScreen(const ReportsScreen()),
                          ),
                          const SizedBox(width: 8),
                          _buildStatCard(
                            title: 'رصيد الصندوق',
                            value: '${_cashBalance.toStringAsFixed(1)} $_currencySymbol',
                            icon: Icons.account_balance_wallet_outlined,
                            accentColor: const Color(0xFF1545B5),
                            onTap: () => _openScreen(const CashboxScreen()),
                          ),
                          const SizedBox(width: 8),
                          _buildStatCard(
                            title: 'نواقص المخزن',
                            value: '$_lowStockCount / $_totalProductsCount',
                            icon: Icons.warning_amber_rounded,
                            accentColor: _lowStockCount > 0
                                ? const Color(0xFFDC2626)
                                : const Color(0xFF4B5563),
                            onTap: () => _openScreen(const InventoryScreen()),
                          ),
                        ],
                      ),
              ),

              // شبكة الأقسام الرئيسية للتطبيق
              Expanded(
                child: GridView.count(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                  crossAxisCount: 2,
                  mainAxisSpacing: 11,
                  crossAxisSpacing: 11,
                  childAspectRatio: 1.18,
                  children: [
                    _buildModuleTile(
                      title: 'المبيعات',
                      subtitle: 'نقطة البيع والفواتير',
                      icon: Icons.shopping_cart_checkout_rounded,
                      color: const Color(0xFF16A34A),
                      onTap: () => _openScreen(const SalesScreen()),
                    ),
                    _buildModuleTile(
                      title: 'المشتريات',
                      subtitle: 'فواتير الشراء والتوريد',
                      icon: Icons.add_shopping_cart_rounded,
                      color: const Color(0xFF2563EB),
                      onTap: () => _openScreen(const PurchasesScreen()),
                    ),
                    _buildModuleTile(
                      title: 'المخزون',
                      subtitle: 'الأصناف والأسعار والباركود',
                      icon: Icons.inventory_2_rounded,
                      color: const Color(0xFFD97706),
                      badgeText: _lowStockCount > 0 ? '$_lowStockCount' : null,
                      onTap: () => _openScreen(const InventoryScreen()),
                    ),
                    _buildModuleTile(
                      title: 'العملاء والموردين',
                      subtitle: 'الحسابات والديون والسندات',
                      icon: Icons.people_alt_rounded,
                      color: const Color(0xFF7C3AED),
                      onTap: () => _openScreen(const ContactsScreen()),
                    ),
                    _buildModuleTile(
                      title: 'الصندوق والمصاريف',
                      subtitle: 'المقبوضات والمصروفات',
                      icon: Icons.account_balance_wallet_rounded,
                      color: const Color(0xFF0D9488),
                      onTap: () => _openScreen(const CashboxScreen()),
                    ),
                    _buildModuleTile(
                      title: 'التقارير والأرباح',
                      subtitle: 'كشوفات الأرباح والجرد',
                      icon: Icons.bar_chart_rounded,
                      color: const Color(0xFFDC2626),
                      onTap: () => _openScreen(const ReportsScreen()),
                    ),
                    _buildModuleTile(
                      title: 'النسخ الاحتياطي',
                      subtitle: 'الحفظ والاستعادة والإعدادات',
                      icon: Icons.backup_rounded,
                      color: const Color(0xFF4B5563),
                      onTap: () => _openScreen(const BackupAndSettingsScreen()),
                    ),
                    _buildModuleTile(
                      title: 'المساعد الذكي',
                      subtitle: 'شرح النظام والدعم الفني',
                      icon: Icons.smart_toy_rounded,
                      color: const Color(0xFF0284C7),
                      customIconWidget: const NebrasRobotAvatar(size: 52),
                      onTap: () => _openScreen(const NebrasBotChatScreen()),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
// =============================================================================
// القسم (5 من 10): شاشة المبيعات ونقطة البيع (SalesScreen)
// =============================================================================

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  DbRows _allProducts = [];
  DbRows _categories = [];
  DbRows _customers = [];
  final DbRows _cartItems = [];

  String _currencySymbol = 'ريال';
  double _exchangeRate = 1.0;

  int? _selectedCategoryId;
  int? _selectedCustomerId;
  String? _selectedCustomerName;
  String _priceTier = 'sale_price'; // sale_price | wholesale_price | special_price
  String _searchQuery = '';
  double _discount = 0.0;
  bool _loading = true;
  bool _saving = false;

  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _loading = true);
    final settings = await DatabaseHelper.instance.getSettingsMap();
    final products = await DatabaseHelper.instance.queryAllProducts();
    final categories = await DatabaseHelper.instance.queryAllCategories();
    final customers = await DatabaseHelper.instance.queryContacts(type: 'customer');

    if (!mounted) return;
    setState(() {
      _currencySymbol = (settings['currency_symbol'] ?? 'ريال').trim();
      final rate = double.tryParse((settings['exchange_rate'] ?? '1').trim()) ?? 1.0;
      _exchangeRate = rate > 0 ? rate : 1.0;
      _allProducts = products;
      _categories = categories;
      _customers = customers;
      _loading = false;
    });
  }

  double _getProductPriceForTier(DbRow product) {
    final baseSale = (product['sale_price'] as num?)?.toDouble() ?? 0.0;
    if (_priceTier == 'wholesale_price') {
      final w = (product['wholesale_price'] as num?)?.toDouble() ?? 0.0;
      return w > 0 ? w : baseSale;
    }
    if (_priceTier == 'special_price') {
      final s = (product['special_price'] as num?)?.toDouble() ?? 0.0;
      return s > 0 ? s : baseSale;
    }
    return baseSale;
  }

  double get _subtotal {
    double sum = 0.0;
    for (final item in _cartItems) {
      sum += (item['total'] as num?)?.toDouble() ?? 0.0;
    }
    return sum;
  }

  double get _grandTotal {
    final val = _subtotal - _discount;
    return val > 0 ? val : 0.0;
  }

  void _addProductToCart(DbRow product, {double addQty = 1.0}) {
    final int? prodId = product['id'] as int?;
    final String name = (product['name'] ?? '').toString();
    final double availableStock = (product['stock_quantity'] as num?)?.toDouble() ?? 0.0;
    final double unitPrice = _getProductPriceForTier(product);
    final double costPrice = (product['purchase_price'] as num?)?.toDouble() ?? 0.0;

    final existingIdx = _cartItems.indexWhere((item) => item['product_id'] == prodId && prodId != null);
    if (existingIdx != -1) {
      final currentQty = (_cartItems[existingIdx]['quantity'] as num?)?.toDouble() ?? 0.0;
      final nextQty = currentQty + addQty;
      if (availableStock > 0 && nextQty > availableStock) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('الكمية المتوفرة في المخزن من "$name" هي $availableStock فقط')),
        );
      }
      setState(() {
        _cartItems[existingIdx]['quantity'] = nextQty;
        _cartItems[existingIdx]['unit_price'] = unitPrice;
        _cartItems[existingIdx]['total'] = double.parse((nextQty * unitPrice).toStringAsFixed(2));
      });
    } else {
      if (availableStock <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تنبيه: رصيد "$name" في المخزن صفر')),
        );
      }
      setState(() {
        _cartItems.add({
          'product_id': prodId,
          'product_name': name,
          'quantity': addQty,
          'unit_price': unitPrice,
          'cost_price': costPrice,
          'total': double.parse((addQty * unitPrice).toStringAsFixed(2)),
        });
      });
    }
  }

  void _updateCartItemQuantity(int index, double delta) {
    final currentQty = (_cartItems[index]['quantity'] as num?)?.toDouble() ?? 1.0;
    final nextQty = currentQty + delta;
    if (nextQty <= 0) {
      setState(() => _cartItems.removeAt(index));
      return;
    }
    final price = (_cartItems[index]['unit_price'] as num?)?.toDouble() ?? 0.0;
    setState(() {
      _cartItems[index]['quantity'] = nextQty;
      _cartItems[index]['total'] = double.parse((nextQty * price).toStringAsFixed(2));
    });
  }

  Future<void> _editCartItemDialog(int index) async {
    final item = _cartItems[index];
    final qtyCtrl = TextEditingController(
      text: ((item['quantity'] as num?)?.toDouble() ?? 1.0).toString(),
    );
    final priceCtrl = TextEditingController(
      text: ((item['unit_price'] as num?)?.toDouble() ?? 0.0).toString(),
    );

    await showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(
            (item['product_name'] ?? '').toString(),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: qtyCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'الكمية',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: priceCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'سعر الوحدة',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() => _cartItems.removeAt(index));
                Navigator.of(ctx).pop();
              },
              child: const Text('حذف الصنف', style: TextStyle(color: Color(0xFFDC2626))),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                final q = double.tryParse(qtyCtrl.text.trim()) ?? 0.0;
                final p = double.tryParse(priceCtrl.text.trim()) ?? 0.0;
                if (q <= 0) {
                  setState(() => _cartItems.removeAt(index));
                } else {
                  setState(() {
                    _cartItems[index]['quantity'] = q;
                    _cartItems[index]['unit_price'] = p;
                    _cartItems[index]['total'] = double.parse((q * p).toStringAsFixed(2));
                  });
                }
                Navigator.of(ctx).pop();
              },
              child: const Text('تحديث'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _scanBarcodeAndAdd() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const BarcodeScannerScreen(title: 'مسح باركود للبيع'),
      ),
    );
    if (code == null || code.trim().isEmpty || !mounted) return;

    final product = await DatabaseHelper.instance.findProductByBarcode(code.trim());
    if (!mounted) return;
    if (product != null) {
      _addProductToCart(product);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 900),
          content: Text('تمت إضافة: ${product['name']}'),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('لم يتم العثور على منتج بالباركود: ${code.trim()}')),
      );
    }
  }

  Future<void> _openCustomerPickerDialog() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          title: const Text(
            'اختيار أو إضافة عميل',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.5),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.person_outline, color: Color(0xFF16A34A)),
                    title: const Text('عميل نقدي (بدون اسم)', style: TextStyle(fontWeight: FontWeight.bold)),
                    trailing: _selectedCustomerId == null
                        ? const Icon(Icons.check_circle, color: Color(0xFF16A34A))
                        : null,
                    onTap: () {
                      setState(() {
                        _selectedCustomerId = null;
                        _selectedCustomerName = null;
                      });
                      Navigator.of(ctx).pop();
                    },
                  ),
                  const Divider(),
                  if (_customers.isNotEmpty)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 190),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _customers.length,
                        itemBuilder: (_, idx) {
                          final c = _customers[idx];
                          final cid = c['id'] as int;
                          final bal = (c['balance'] as num?)?.toDouble() ?? 0.0;
                          return ListTile(
                            dense: true,
                            title: Text((c['name'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text('الرصيد: ${bal.toStringAsFixed(2)} $_currencySymbol'),
                            trailing: _selectedCustomerId == cid
                                ? const Icon(Icons.check_circle, color: Color(0xFF1545B5))
                                : null,
                            onTap: () {
                              setState(() {
                                _selectedCustomerId = cid;
                                _selectedCustomerName = (c['name'] ?? '').toString();
                              });
                              Navigator.of(ctx).pop();
                            },
                          );
                        },
                      ),
                    ),
                  const Divider(),
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'إضافة عميل جديد سريع:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'اسم العميل *',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: phoneCtrl,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'رقم الهاتف',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () async {
                          final cName = nameCtrl.text.trim();
                          if (cName.isEmpty) return;
                          final newId = await DatabaseHelper.instance.insertContact({
                            'name': cName,
                            'phone': phoneCtrl.text.trim(),
                            'type': 'customer',
                            'balance': 0.0,
                          });
                          final updated = await DatabaseHelper.instance.queryContacts(type: 'customer');
                          if (!mounted) return;
                          setState(() {
                            _customers = updated;
                            _selectedCustomerId = newId;
                            _selectedCustomerName = cName;
                          });
                          if (ctx.mounted) Navigator.of(ctx).pop();
                        },
                        child: const Text('إضافة'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openDiscountDialog() async {
    final discCtrl = TextEditingController(text: _discount > 0 ? _discount.toString() : '');
    await showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('خصم على الفاتورة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          content: TextField(
            controller: discCtrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'قيمة الخصم ($_currencySymbol)',
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() => _discount = 0.0);
                Navigator.of(ctx).pop();
              },
              child: const Text('إلغاء الخصم'),
            ),
            FilledButton(
              onPressed: () {
                final val = double.tryParse(discCtrl.text.trim()) ?? 0.0;
                setState(() => _discount = val < 0 ? 0.0 : val);
                Navigator.of(ctx).pop();
              },
              child: const Text('تطبيق'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openCheckoutDialog() async {
    if (_cartItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('السلة فارغة، أضف صنفاً واحداً على الأقل')),
      );
      return;
    }

    final total = _grandTotal;
    String payMode = 'cash'; // cash | credit | partial
    final paidCtrl = TextEditingController(text: total.toStringAsFixed(2));
    final notesCtrl = TextEditingController();
    bool printReceipt = true;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final paidVal = payMode == 'cash'
              ? total
              : (payMode == 'credit' ? 0.0 : (double.tryParse(paidCtrl.text.trim()) ?? 0.0));
          final remainingVal = (total - paidVal).clamp(0.0, double.infinity);

          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              title: const Text(
                'إتمام وحفظ فاتورة المبيعات',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFBBF7D0)),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'الإجمالي المطلوب: ${total.toStringAsFixed(2)} $_currencySymbol',
                            style: const TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF15803D),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'العميل: ${_selectedCustomerName ?? 'عميل نقدي'}',
                            style: const TextStyle(fontSize: 13, color: Colors.black87),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'cash', label: Text('نقدي')),
                        ButtonSegment(value: 'credit', label: Text('آجل')),
                        ButtonSegment(value: 'partial', label: Text('جزئي')),
                      ],
                      selected: {payMode},
                      onSelectionChanged: (sel) {
                        setDialogState(() {
                          payMode = sel.first;
                          if (payMode == 'cash') {
                            paidCtrl.text = total.toStringAsFixed(2);
                          } else if (payMode == 'credit') {
                            paidCtrl.text = '0';
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    if (payMode == 'partial') ...[
                      TextField(
                        controller: paidCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (_) => setDialogState(() {}),
                        decoration: InputDecoration(
                          labelText: 'المبلغ المدفوع نقداً ($_currencySymbol)',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (remainingVal > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'المتبقي (آجل على العميل): ${remainingVal.toStringAsFixed(2)} $_currencySymbol',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFDC2626),
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    TextField(
                      controller: notesCtrl,
                      decoration: const InputDecoration(
                        labelText: 'ملاحظات على الفاتورة (اختياري)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: printReceipt,
                      onChanged: (v) => setDialogState(() => printReceipt = v ?? true),
                      title: const Text('طباعة الفاتورة حرارياً بعد الحفظ', style: TextStyle(fontSize: 13.5)),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('إلغاء'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
                  onPressed: _saving
                      ? null
                      : () async {
                          if (remainingVal > 0 && _selectedCustomerId == null) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text('يرجى اختيار اسم العميل أولاً لتسجيل المبلغ الآجل في حسابه'),
                              ),
                            );
                            return;
                          }

                          setState(() => _saving = true);
                          try {
                            final invId = await DatabaseHelper.instance.createSaleInvoice(
                              customerId: _selectedCustomerId,
                              customerName: _selectedCustomerName ?? 'عميل نقدي',
                              items: DbRows.from(_cartItems),
                              discount: _discount,
                              paid: paidVal,
                              paymentMethod: payMode,
                              notes: notesCtrl.text.trim(),
                            );

                            if (ctx.mounted) Navigator.of(ctx).pop();
                            setState(() {
                              _cartItems.clear();
                              _discount = 0.0;
                              _selectedCustomerId = null;
                              _selectedCustomerName = null;
                              _saving = false;
                            });
                            await _loadInitialData();

                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('تم حفظ فاتورة المبيعات بنجاح')),
                              );
                            }
                            if (printReceipt) {
                              await ThermalPrintService.printInvoiceById(invId);
                            }
                          } catch (_) {
                            if (mounted) setState(() => _saving = false);
                          }
                        },
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('حفظ الفاتورة'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _openRecentSalesInvoices() async {
    final invoices = await DatabaseHelper.instance.queryInvoices(type: 'sale');
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          maxChildSize: 0.92,
          builder: (_, scrollCtrl) => Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  'سجل فواتير المبيعات السابقة',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: invoices.isEmpty
                    ? const Center(child: Text('لا توجد فواتير مبيعات مسجلة بعد'))
                    : ListView.separated(
                        controller: scrollCtrl,
                        itemCount: invoices.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, idx) {
                          final inv = invoices[idx];
                          final invId = inv['id'] as int;
                          final total = (inv['total'] as num?)?.toDouble() ?? 0.0;
                          final rem = (inv['remaining'] as num?)?.toDouble() ?? 0.0;
                          final dateText = (inv['created_at'] ?? '').toString().replaceAll('T', ' ').split('.').first;

                          return ListTile(
                            title: Text(
                              '${inv['invoice_number']} • ${inv['contact_name'] ?? 'عميل نقدي'}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            subtitle: Text(
                              'الإجمالي: ${total.toStringAsFixed(2)} $_currencySymbol'
                              '${rem > 0 ? ' (متبقي: ${rem.toStringAsFixed(2)})' : ''}\n$dateText',
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: IconButton(
                              tooltip: 'إعادة طباعة الفاتورة',
                              icon: const Icon(Icons.print_outlined, color: Color(0xFF1545B5)),
                              onPressed: () => ThermalPrintService.printInvoiceById(invId),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  DbRows get _filteredProducts {
    final q = _searchQuery.trim().toLowerCase();
    return _allProducts.where((p) {
      if (_selectedCategoryId != null && p['category_id'] != _selectedCategoryId) {
        return false;
      }
      if (q.isEmpty) return true;
      final name = (p['name'] ?? '').toString().toLowerCase();
      final barcode = (p['barcode'] ?? '').toString().toLowerCase();
      return name.contains(q) || barcode.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final products = _filteredProducts;
    final secondaryTotal = _exchangeRate > 0 ? (_grandTotal / _exchangeRate) : 0.0;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F4F6),
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          titleSpacing: 4,
          title: const Text(
            'المبيعات (نقطة البيع)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17.5),
          ),
          actions: [
            IconButton(
              tooltip: 'فواتير المبيعات السابقة',
              icon: const Icon(Icons.receipt_long_outlined),
              onPressed: _openRecentSalesInvoices,
            ),
            IconButton(
              tooltip: 'اختيار العميل',
              icon: Icon(
                _selectedCustomerId != null ? Icons.person : Icons.person_add_alt_1_outlined,
                color: _selectedCustomerId != null ? const Color(0xFF1545B5) : null,
              ),
              onPressed: _openCustomerPickerDialog,
            ),
          ],
        ),
        body: Column(
          children: [
            // شريط البحث + الباركود + مستوى التسعير
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: (v) => setState(() => _searchQuery = v),
                          decoration: InputDecoration(
                            hintText: _selectedCustomerName != null
                                ? 'العميل: $_selectedCustomerName'
                                : 'ابحث عن صنف أو امسح الباركود...',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.close, size: 18),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  )
                                : null,
                            isDense: true,
                            filled: true,
                            fillColor: const Color(0xFFF3F4F6),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton.filled(
                        style: IconButton.styleFrom(backgroundColor: const Color(0xFF1545B5)),
                        tooltip: 'مسح باركود بالكاميرا',
                        icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
                        onPressed: _scanBarcodeAndAdd,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Text('التسعيرة: ', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                      ChoiceChip(
                        label: const Text('قطاعي 1', style: TextStyle(fontSize: 11.5)),
                        selected: _priceTier == 'sale_price',
                        onSelected: (_) => setState(() => _priceTier = 'sale_price'),
                      ),
                      const SizedBox(width: 4),
                      ChoiceChip(
                        label: const Text('جملة 2', style: TextStyle(fontSize: 11.5)),
                        selected: _priceTier == 'wholesale_price',
                        onSelected: (_) => setState(() => _priceTier = 'wholesale_price'),
                      ),
                      const SizedBox(width: 4),
                      ChoiceChip(
                        label: const Text('خاص 3', style: TextStyle(fontSize: 11.5)),
                        selected: _priceTier == 'special_price',
                        onSelected: (_) => setState(() => _priceTier = 'special_price'),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // شريط الأصناف السريعة للاختيار بلمسة واحدة
            SizedBox(
              height: 82,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : products.isEmpty
                      ? const Center(
                          child: Text(
                            'لا توجد أصناف في المخزن، أضف منتجاتك من قسم المخزون أولاً',
                            style: TextStyle(fontSize: 12.5, color: Colors.black54),
                          ),
                        )
                      : ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          itemCount: products.length,
                          itemBuilder: (_, idx) {
                            final prod = products[idx];
                            final price = _getProductPriceForTier(prod);
                            final qty = (prod['stock_quantity'] as num?)?.toDouble() ?? 0.0;
                            return Container(
                              width: 132,
                              margin: const EdgeInsets.only(left: 7),
                              child: Material(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                elevation: 1,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () => _addProductToCart(prod),
                                  child: Padding(
                                    padding: const EdgeInsets.all(7),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          (prod['name'] ?? '').toString(),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                                        ),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              price.toStringAsFixed(1),
                                              style: const TextStyle(
                                                color: Color(0xFF16A34A),
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12.5,
                                              ),
                                            ),
                                            Text(
                                              'مخزن: ${qty.toInt()}',
                                              style: const TextStyle(fontSize: 10.5, color: Colors.black54),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),

            // ترويسة جدول السلة
            Container(
              color: const Color(0xFFE5E7EB),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: const Row(
                children: [
                  Expanded(flex: 4, child: Text('الصنف', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                  Expanded(flex: 2, child: Text('السعر', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                  Expanded(flex: 3, child: Text('الكمية', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                  Expanded(flex: 2, child: Text('الإجمالي', textAlign: TextAlign.left, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                ],
              ),
            ),

            // قائمة أصناف الفاتورة الحالية
            Expanded(
              child: _cartItems.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.shopping_basket_outlined, size: 52, color: Colors.grey.shade400),
                          const SizedBox(height: 8),
                          const Text(
                            'اضغط على أي صنف أعلاه أو امسح الباركود لإضافته للفاتورة',
                            style: TextStyle(color: Colors.black54, fontSize: 13),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: _cartItems.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, idx) {
                        final item = _cartItems[idx];
                        final qty = (item['quantity'] as num?)?.toDouble() ?? 1.0;
                        final price = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
                        final lineTotal = (item['total'] as num?)?.toDouble() ?? 0.0;

                        return InkWell(
                          onTap: () => _editCartItemDialog(idx),
                          child: Container(
                            color: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 4,
                                  child: Text(
                                    (item['product_name'] ?? '').toString(),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    price.toStringAsFixed(1),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      InkWell(
                                        onTap: () => _updateCartItemQuantity(idx, 1),
                                        child: const Icon(Icons.add_circle, color: Color(0xFF16A34A), size: 22),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 6),
                                        child: Text(
                                          qty == qty.roundToDouble() ? '${qty.toInt()}' : qty.toStringAsFixed(1),
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                        ),
                                      ),
                                      InkWell(
                                        onTap: () => _updateCartItemQuantity(idx, -1),
                                        child: const Icon(Icons.remove_circle, color: Color(0xFFDC2626), size: 22),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    lineTotal.toStringAsFixed(1),
                                    textAlign: TextAlign.left,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13.5,
                                      color: Color(0xFF1545B5),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // الشريط السفلي للإجمالي والحفظ والخصم
            Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 6,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Text(
                        'الإجمالي:',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE6EE9C),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.black38),
                          ),
                          child: Text(
                            '${_grandTotal.toStringAsFixed(2)} $_currencySymbol',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFD32F2F),
                            ),
                          ),
                        ),
                      ),
                      if (_exchangeRate != 1.0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.black26),
                          ),
                          child: Text(
                            secondaryTotal.toStringAsFixed(2),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFD32F2F),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _openDiscountDialog,
                        icon: const Icon(Icons.percent, size: 17),
                        label: Text(_discount > 0 ? 'خصم: $_discount' : 'خصم'),
                      ),
                      const SizedBox(width: 6),
                      if (_cartItems.isNotEmpty)
                        IconButton(
                          tooltip: 'تفريغ السلة',
                          icon: const Icon(Icons.delete_sweep_outlined, color: Color(0xFFDC2626)),
                          onPressed: () => setState(() {
                            _cartItems.clear();
                            _discount = 0.0;
                          }),
                        ),
                      const Spacer(),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF16A34A),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                        ),
                        onPressed: _openCheckoutDialog,
                        icon: const Icon(Icons.save_outlined),
                        label: const Text(
                          'حفظ وطباعة الفاتورة',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
// =============================================================================
// القسم (6 من 10): شاشة المشتريات (PurchasesScreen) مع البحث الصوتي والصلاحيات
// =============================================================================

class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({super.key});

  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  DbRows _allProducts = [];
  DbRows _suppliers = [];
  final DbRows _purchaseItems = [];

  String _currencySymbol = 'ريال';
  double _exchangeRate = 1.0;

  DateTime _invoiceDate = DateTime.now();
  int? _selectedSupplierId;
  String? _selectedSupplierName;
  String _search = '';
  bool _saving = false;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _speech.stop();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  String get _formattedInvoiceDate {
    final y = _invoiceDate.year.toString().padLeft(4, '0');
    final m = _invoiceDate.month.toString().padLeft(2, '0');
    final d = _invoiceDate.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<void> _loadInitialData() async {
    final settings = await DatabaseHelper.instance.getSettingsMap();
    final products = await DatabaseHelper.instance.queryAllProducts();
    final suppliers = await DatabaseHelper.instance.queryContacts(type: 'supplier');

    if (!mounted) return;
    setState(() {
      _currencySymbol = (settings['currency_symbol'] ?? 'ريال').trim();
      final rate = double.tryParse((settings['exchange_rate'] ?? '1').trim()) ?? 1.0;
      _exchangeRate = rate > 0 ? rate : 1.0;
      _allProducts = products;
      _suppliers = suppliers;
    });
  }

  double get _grandTotal {
    double sum = 0.0;
    for (final item in _purchaseItems) {
      sum += (item['total'] as num?)?.toDouble() ?? 0.0;
    }
    return sum;
  }

  Future<void> _pickInvoiceDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _invoiceDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
    );
    if (picked != null && mounted) {
      setState(() => _invoiceDate = picked);
    }
  }

  void _addProductToPurchase(DbRow product, {double addQty = 1.0, double? customCost}) {
    final int? prodId = product['id'] as int?;
    final String name = (product['name'] ?? '').toString();
    final double cost = customCost ?? ((product['purchase_price'] as num?)?.toDouble() ?? 0.0);

    final idx = _purchaseItems.indexWhere((e) => e['product_id'] == prodId && prodId != null);
    setState(() {
      if (idx != -1) {
        final curQty = (_purchaseItems[idx]['quantity'] as num?)?.toDouble() ?? 0.0;
        final nextQty = curQty + addQty;
        final unitCost = customCost ?? ((_purchaseItems[idx]['unit_price'] as num?)?.toDouble() ?? cost);
        _purchaseItems[idx]['quantity'] = nextQty;
        _purchaseItems[idx]['unit_price'] = unitCost;
        _purchaseItems[idx]['cost_price'] = unitCost;
        _purchaseItems[idx]['total'] = double.parse((nextQty * unitCost).toStringAsFixed(2));
      } else {
        _purchaseItems.add({
          'product_id': prodId,
          'product_name': name,
          'quantity': addQty,
          'unit_price': cost,
          'cost_price': cost,
          'total': double.parse((addQty * cost).toStringAsFixed(2)),
        });
      }
      _search = '';
      _searchController.clear();
    });
  }

  Future<void> _editPurchaseItemDialog(int index) async {
    final item = _purchaseItems[index];
    final costCtrl = TextEditingController(
      text: ((item['unit_price'] as num?)?.toDouble() ?? 0.0).toString(),
    );
    final qtyCtrl = TextEditingController(
      text: ((item['quantity'] as num?)?.toDouble() ?? 1.0).toString(),
    );

    await showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          title: Text(
            (item['product_name'] ?? '').toString(),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: costCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'سعر التكلفة ($_currencySymbol)',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: qtyCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'الكمية المشتراة',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() => _purchaseItems.removeAt(index));
                Navigator.of(ctx).pop();
              },
              child: const Text('حذف الصنف', style: TextStyle(color: Color(0xFFDC2626))),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                final c = double.tryParse(costCtrl.text.trim()) ?? 0.0;
                final q = double.tryParse(qtyCtrl.text.trim()) ?? 0.0;
                if (q <= 0) {
                  setState(() => _purchaseItems.removeAt(index));
                } else {
                  setState(() {
                    _purchaseItems[index]['unit_price'] = c;
                    _purchaseItems[index]['cost_price'] = c;
                    _purchaseItems[index]['quantity'] = q;
                    _purchaseItems[index]['total'] = double.parse((c * q).toStringAsFixed(2));
                  });
                }
                Navigator.of(ctx).pop();
              },
              child: const Text('تحديث'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onSearchSubmitted(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;

    final byBarcode = await DatabaseHelper.instance.findProductByBarcode(q);
    if (byBarcode != null) {
      _addProductToPurchase(byBarcode);
      return;
    }

    final matches = _allProducts.where((p) {
      final name = (p['name'] ?? '').toString().toLowerCase();
      final code = (p['barcode'] ?? '').toString().toLowerCase();
      return name.contains(q.toLowerCase()) || code.contains(q.toLowerCase());
    }).toList();

    if (matches.length == 1) {
      _addProductToPurchase(matches.first);
    } else if (matches.isEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('لم يتم العثور على "$q" في المخزن'),
          action: SnackBarAction(
            label: 'إضافة كمنتج جديد',
            onPressed: () => _quickCreateProductDialog(initialName: q),
          ),
        ),
      );
    }
  }

  Future<void> _scanBarcodeForPurchase() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const BarcodeScannerScreen(title: 'مسح باركود للمشتريات'),
      ),
    );
    if (code == null || code.trim().isEmpty || !mounted) return;

    final cleanCode = code.trim();
    final found = await DatabaseHelper.instance.findProductByBarcode(cleanCode);
    if (!mounted) return;
    if (found != null) {
      _addProductToPurchase(found);
    } else {
      await _quickCreateProductDialog(initialBarcode: cleanCode);
    }
  }

  Future<void> _quickCreateProductDialog({
    String initialName = '',
    String initialBarcode = '',
  }) async {
    final nameCtrl = TextEditingController(text: initialName);
    final barcodeCtrl = TextEditingController(text: initialBarcode);
    final costCtrl = TextEditingController(text: '0');
    final saleCtrl = TextEditingController(text: '0');
    final qtyCtrl = TextEditingController(text: '1');

    await showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          title: const Text(
            'تعريف منتج جديد وإضافته للفاتورة',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: initialName.isEmpty,
                  decoration: const InputDecoration(
                    labelText: 'اسم المنتج *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: barcodeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'الباركود',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: costCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'سعر التكلفة *',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: saleCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'سعر البيع',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: qtyCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'الكمية المشتراة',
                    border: OutlineInputBorder(),
                  ),
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
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1545B5)),
              onPressed: () async {
                final pName = nameCtrl.text.trim();
                if (pName.isEmpty) return;
                final cost = double.tryParse(costCtrl.text.trim()) ?? 0.0;
                final sale = double.tryParse(saleCtrl.text.trim()) ?? 0.0;
                final qty = double.tryParse(qtyCtrl.text.trim()) ?? 1.0;
                final bCode = barcodeCtrl.text.trim();

                final newId = await DatabaseHelper.instance.insertProduct({
                  'name': pName,
                  'barcode': bCode.isEmpty ? null : bCode,
                  'purchase_price': cost,
                  'sale_price': sale > 0 ? sale : cost,
                  'stock_quantity': 0.0,
                  'min_stock': 2.0,
                  'is_active': 1,
                });

                await _loadInitialData();
                _addProductToPurchase(
                  {
                    'id': newId,
                    'name': pName,
                    'purchase_price': cost,
                  },
                  addQty: qty > 0 ? qty : 1.0,
                  customCost: cost,
                );
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child: const Text('حفظ وإضافة'),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // أوامر البحث الصوتي ونوافذ الصلاحيات
  // ---------------------------------------------------------------------------
  Future<void> _openGoogleAppForOfflineVoice() async {
    final uris = <Uri>[
      Uri.parse('android-app://com.google.android.googlequicksearchbox'),
      Uri.parse('googleapp://'),
      Uri.parse('https://play.google.com/store/apps/details?id=com.google.android.googlequicksearchbox'),
    ];
    for (final uri in uris) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          return;
        }
      } catch (_) {}
    }
  }

  Future<void> _showMicPermissionDeniedDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          title: const Text(
            'صلاحية المايكروفون',
            style: TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 19,
              color: Colors.black87,
            ),
          ),
          content: const Text(
            'صلاحية المايكروفون مرفوضة للتطبيق.\n\n'
            'الإعدادات ← الأذونات ← الميكروفون ← سماح.',
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              color: Colors.black87,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await openAppSettings();
              },
              child: const Text(
                'فتح الإعدادات',
                style: TextStyle(
                  color: Color(0xFFE57373),
                  fontWeight: FontWeight.w600,
                  fontSize: 14.5,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text(
                'إلغاء',
                style: TextStyle(
                  color: Color(0xFFE57373),
                  fontWeight: FontWeight.w600,
                  fontSize: 14.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showOfflineVoiceGuideDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          title: const Text(
            'البحث الصوتي بدون إنترنت',
            style: TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 19,
              color: Colors.black87,
            ),
          ),
          content: const Text(
            'لاستخدام الصوت بدون إنترنت حمّل حزمة العربي مرة واحدة (والإنترنت شغّال):\n\n'
            'تطبيق Google ← صورة الحساب ← الإعدادات ← الصوت ← التعرف على الكلام بلا اتصال بالإنترنت ← الكل ← العربية',
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              color: Colors.black87,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await _openGoogleAppForOfflineVoice();
              },
              child: const Text(
                'فتح تطبيق GOOGLE',
                style: TextStyle(
                  color: Color(0xFFE57373),
                  fontWeight: FontWeight.w600,
                  fontSize: 14.5,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text(
                'إغلاق',
                style: TextStyle(
                  color: Color(0xFFE57373),
                  fontWeight: FontWeight.w600,
                  fontSize: 14.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onMicButtonPressed() async {
    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }

    final granted = await AppPermissionsService.ensureMicrophonePermission(
      openSettingsIfDenied: false,
    );
    if (!mounted) return;

    if (!granted) {
      await _showMicPermissionDeniedDialog();
      return;
    }

    bool hadRecognitionError = false;
    final available = await _speech.initialize(
      onStatus: (status) {
        if (!mounted) return;
        if (status == 'done' || status == 'notListening') {
          setState(() => _isListening = false);
        }
      },
      onError: (error) {
        if (!mounted) return;
        setState(() => _isListening = false);
        final msg = error.errorMsg.toLowerCase();
        if (!hadRecognitionError &&
            (msg.contains('network') ||
                msg.contains('language') ||
                msg.contains('no_match') ||
                msg.contains('client') ||
                msg.contains('server') ||
                msg.contains('recognizer'))) {
          hadRecognitionError = true;
          _showOfflineVoiceGuideDialog();
        }
      },
    );

    if (!mounted) return;

    if (!available) {
      await _showOfflineVoiceGuideDialog();
      return;
    }

    setState(() {
      _isListening = true;
      _search = '';
      _searchController.clear();
    });

    await _speech.listen(
      localeId: 'ar-SA',
      listenMode: stt.ListenMode.search,
      partialResults: true,
      onResult: (result) {
        if (!mounted) return;
        final spoken = result.recognizedWords.trim();
        setState(() {
          _search = spoken;
          _searchController.text = spoken;
          _searchController.selection = TextSelection.fromPosition(
            TextPosition(offset: _searchController.text.length),
          );
        });
        if (result.finalResult) {
          setState(() => _isListening = false);
          if (spoken.isNotEmpty) {
            _onSearchSubmitted(spoken);
          }
        }
      },
    );
  }

  // ---------------------------------------------------------------------------
  // اختيار المورد، القائمة السريعة للأصناف، وحفظ فاتورة المشتريات
  // ---------------------------------------------------------------------------
  Future<void> _openSupplierPickerDialog() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          title: const Text(
            'اختيار أو إضافة مورد',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.5),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.storefront_outlined, color: Color(0xFF1545B5)),
                    title: const Text('مورد نقدي (عام)', style: TextStyle(fontWeight: FontWeight.bold)),
                    trailing: _selectedSupplierId == null
                        ? const Icon(Icons.check_circle, color: Color(0xFF1545B5))
                        : null,
                    onTap: () {
                      setState(() {
                        _selectedSupplierId = null;
                        _selectedSupplierName = null;
                      });
                      Navigator.of(ctx).pop();
                    },
                  ),
                  const Divider(),
                  if (_suppliers.isNotEmpty)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 180),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _suppliers.length,
                        itemBuilder: (_, idx) {
                          final s = _suppliers[idx];
                          final sid = s['id'] as int;
                          final bal = (s['balance'] as num?)?.toDouble() ?? 0.0;
                          return ListTile(
                            dense: true,
                            title: Text((s['name'] ?? '').toString(), style: const TextWeightW600()),
                            subtitle: Text('المستحق له: ${bal.toStringAsFixed(2)} $_currencySymbol'),
                            trailing: _selectedSupplierId == sid
                                ? const Icon(Icons.check_circle, color: Color(0xFF1545B5))
                                : null,
                            onTap: () {
                              setState(() {
                                _selectedSupplierId = sid;
                                _selectedSupplierName = (s['name'] ?? '').toString();
                              });
                              Navigator.of(ctx).pop();
                            },
                          );
                        },
                      ),
                    ),
                  const Divider(),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'إضافة مورد جديد *',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: phoneCtrl,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'هاتف المورد',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () async {
                          final sName = nameCtrl.text.trim();
                          if (sName.isEmpty) return;
                          final newId = await DatabaseHelper.instance.insertContact({
                            'name': sName,
                            'phone': phoneCtrl.text.trim(),
                            'type': 'supplier',
                            'balance': 0.0,
                          });
                          final updated = await DatabaseHelper.instance.queryContacts(type: 'supplier');
                          if (!mounted) return;
                          setState(() {
                            _suppliers = updated;
                            _selectedSupplierId = newId;
                            _selectedSupplierName = sName;
                          });
                          if (ctx.mounted) Navigator.of(ctx).pop();
                        },
                        child: const Text('إضافة'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openQuickProductGridSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.65,
          maxChildSize: 0.9,
          builder: (_, scrollCtrl) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'اختيار سريع من أصناف المخزن',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _quickCreateProductDialog();
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('منتج جديد'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _allProducts.isEmpty
                    ? const Center(child: Text('لا توجد أصناف مسجلة في المخزن بعد'))
                    : GridView.builder(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.all(10),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 2.3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: _allProducts.length,
                        itemBuilder: (_, idx) {
                          final prod = _allProducts[idx];
                          final cost = (prod['purchase_price'] as num?)?.toDouble() ?? 0.0;
                          final stock = (prod['stock_quantity'] as num?)?.toDouble() ?? 0.0;
                          return InkWell(
                            onTap: () {
                              _addProductToPurchase(prod);
                              Navigator.of(ctx).pop();
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF9FAFB),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFD1D5DB)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    (prod['name'] ?? '').toString(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'التكلفة: ${cost.toStringAsFixed(1)} | المتوفر: ${stock.toInt()}',
                                    style: const TextStyle(fontSize: 11.5, color: Colors.black54),
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
      ),
    );
  }

  Future<void> _onSavePurchasePressed() async {
    if (_purchaseItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أضف صنفاً واحداً على الأقل لحفظ فاتورة المشتريات')),
      );
      return;
    }

    final total = _grandTotal;
    String payMode = 'cash';
    final paidCtrl = TextEditingController(text: total.toStringAsFixed(2));
    final notesCtrl = TextEditingController();
    bool printReceipt = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final paidVal = payMode == 'cash'
              ? total
              : (payMode == 'credit' ? 0.0 : (double.tryParse(paidCtrl.text.trim()) ?? 0.0));
          final remainingVal = (total - paidVal).clamp(0.0, double.infinity);

          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              title: const Text(
                'حفظ فاتورة المشتريات',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'إجمالي الفاتورة: ${total.toStringAsFixed(2)} $_currencySymbol',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1545B5),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('المورد: ${_selectedSupplierName ?? 'مورد نقدي'}'),
                    const SizedBox(height: 10),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'cash', label: Text('نقدي')),
                        ButtonSegment(value: 'credit', label: Text('آجل')),
                        ButtonSegment(value: 'partial', label: Text('جزئي')),
                      ],
                      selected: {payMode},
                      onSelectionChanged: (sel) {
                        setDialogState(() {
                          payMode = sel.first;
                          if (payMode == 'cash') {
                            paidCtrl.text = total.toStringAsFixed(2);
                          } else if (payMode == 'credit') {
                            paidCtrl.text = '0';
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    if (payMode == 'partial') ...[
                      TextField(
                        controller: paidCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (_) => setDialogState(() {}),
                        decoration: InputDecoration(
                          labelText: 'المبلغ المدفوع للمورد ($_currencySymbol)',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (remainingVal > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'المتبقي (آجل للمورد): ${remainingVal.toStringAsFixed(2)} $_currencySymbol',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFDC2626),
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    TextField(
                      controller: notesCtrl,
                      decoration: const InputDecoration(
                        labelText: 'ملاحظات (اختياري)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: printReceipt,
                      onChanged: (v) => setDialogState(() => printReceipt = v ?? false),
                      title: const Text('طباعة الفاتورة بعد الحفظ', style: TextStyle(fontSize: 13.5)),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('إلغاء'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1545B5)),
                  onPressed: _saving
                      ? null
                      : () async {
                          if (remainingVal > 0 && _selectedSupplierId == null) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text('اختر اسم المورد أولاً لتسجيل المبلغ الآجل في حسابه'),
                              ),
                            );
                            return;
                          }

                          setState(() => _saving = true);
                          try {
                            final invDateIso = DateTime(
                              _invoiceDate.year,
                              _invoiceDate.month,
                              _invoiceDate.day,
                              DateTime.now().hour,
                              DateTime.now().minute,
                            ).toIso8601String();

                            final invId = await DatabaseHelper.instance.createPurchaseInvoice(
                              supplierId: _selectedSupplierId,
                              supplierName: _selectedSupplierName ?? 'مورد نقدي',
                              items: DbRows.from(_purchaseItems),
                              paid: paidVal,
                              paymentMethod: payMode,
                              notes: notesCtrl.text.trim(),
                              invoiceDate: invDateIso,
                            );

                            if (ctx.mounted) Navigator.of(ctx).pop();
                            setState(() {
                              _purchaseItems.clear();
                              _selectedSupplierId = null;
                              _selectedSupplierName = null;
                              _saving = false;
                            });
                            await _loadInitialData();

                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('تم حفظ فاتورة المشتريات وتحديث المخزون')),
                              );
                            }
                            if (printReceipt) {
                              await ThermalPrintService.printInvoiceById(invId);
                            }
                          } catch (_) {
                            if (mounted) setState(() => _saving = false);
                          }
                        },
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('حفظ الفاتورة'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _openPurchaseMenuSheet() async {
    final invoices = await DatabaseHelper.instance.queryInvoices(type: 'purchase');
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.person_search_outlined, color: Color(0xFF1545B5)),
                title: const Text('تحديد أو إضافة مورد للفاتورة', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(_selectedSupplierName ?? 'مورد نقدي'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _openSupplierPickerDialog();
                },
              ),
              ListTile(
                leading: const Icon(Icons.add_box_outlined, color: Color(0xFF16A34A)),
                title: const Text('إضافة منتج جديد غير مسجل بالمخزن', style: TextStyle(fontWeight: FontWeight.bold)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _quickCreateProductDialog();
                },
              ),
              const Divider(height: 1),
              const Padding(
                padding: EdgeInsets.all(10),
                child: Text('آخر فواتير المشتريات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: invoices.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('لا توجد فواتير مشتريات سابقة'),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: invoices.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, idx) {
                          final inv = invoices[idx];
                          final invId = inv['id'] as int;
                          final total = (inv['total'] as num?)?.toDouble() ?? 0.0;
                          return ListTile(
                            dense: true,
                            title: Text('${inv['invoice_number']} • ${inv['contact_name'] ?? 'مورد نقدي'}'),
                            subtitle: Text('الإجمالي: ${total.toStringAsFixed(2)} $_currencySymbol'),
                            trailing: IconButton(
                              icon: const Icon(Icons.print_outlined, size: 20),
                              onPressed: () => ThermalPrintService.printInvoiceById(invId),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final supName = _selectedSupplierName;
    final secondaryTotal = _exchangeRate > 0 ? (_grandTotal / _exchangeRate) : 0.0;
    final DbRows matchingSuggestions = _search.trim().isEmpty
        ? DbRows.empty()
        : _allProducts
            .where((p) {
              final q = _search.trim().toLowerCase();
              final name = (p['name'] ?? '').toString().toLowerCase();
              final code = (p['barcode'] ?? '').toString().toLowerCase();
              return name.contains(q) || code.contains(q);
            })
            .take(5)
            .toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F4F6),
        body: SafeArea(
          child: Column(
            children: [
              // 1. الشريط العلوي: قائمة | المشتريات | رجوع
              Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      tooltip: 'خيارات المشتريات والفواتير السابقة',
                      icon: const Icon(Icons.menu, color: Colors.black87, size: 28),
                      onPressed: _openPurchaseMenuSheet,
                    ),
                    const Text(
                      'المشتريات',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    IconButton(
                      tooltip: 'رجوع',
                      icon: const Icon(Icons.arrow_forward_ios, color: Colors.black54, size: 21),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // 2. صف تاريخ الفاتورة
              Container(
                margin: const EdgeInsets.fromLTRB(6, 4, 6, 4),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      flex: 4,
                      child: Center(
                        child: Text(
                          'تاريخ الفاتورة',
                          style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 6,
                      child: InkWell(
                        onTap: _pickInvoiceDate,
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          height: 38,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE0E0E0),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _formattedInvoiceDate,
                            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 3. شريط الأدوات: باركود | حقل البحث | ميكروفون | زر حفظ
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    // 1. زر قراءة الباركود بالكاميرا
                    InkWell(
                      onTap: _scanBarcodeForPurchase,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 48,
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.black54, width: 1.4),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            Container(width: 2.5, color: Colors.black87),
                            Container(width: 1.5, color: Colors.black87),
                            Container(width: 3, color: Colors.black87),
                            Container(width: 1.5, color: Colors.black87),
                            Container(width: 2.5, color: Colors.black87),
                            Container(width: 1.5, color: Colors.black87),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // 2. حقل البحث النصي أو الصوتي
                    Expanded(
                      child: SizedBox(
                        height: 38,
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocus,
                          onChanged: (v) => setState(() => _search = v),
                          onSubmitted: _onSearchSubmitted,
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 14.5),
                          decoration: InputDecoration(
                            hintText: _isListening
                                ? 'بحث'
                                : (supName != null
                                    ? 'المورد: $supName'
                                    : 'ابحث عن منتج أو استخدم الكاميرا'),
                            hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13.5),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                            enabledBorder: const UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.black54, width: 1.1),
                            ),
                            focusedBorder: const UnderlineInputBorder(
                              borderSide: BorderSide(color: Color(0xFF1545B5), width: 1.8),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),

                    // 3. أيقونة الميكروفون (البحث الصوتي)
                    InkWell(
                      onTap: _onMicButtonPressed,
                      onLongPress: _openSupplierPickerDialog,
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          _isListening ? Icons.mic : Icons.mic_none_rounded,
                          color: _isListening ? const Color(0xFFDC2626) : Colors.black87,
                          size: 28,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),

                    // 4. زر القرص المرن (حفظ الفاتورة)
                    InkWell(
                      onTap: _onSavePurchasePressed,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        width: 44,
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(0xFF4B89DC),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF2C5AA0), width: 1.2),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: const Text(
                                'حفظ',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10.5,
                                  height: 1.1,
                                ),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Container(
                              width: 22,
                              height: 10,
                              decoration: BoxDecoration(
                                color: const Color(0xFFD6E4F0),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // اقتراحات البحث الفوري أسفل شريط البحث
              if (matchingSuggestions.isNotEmpty)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: const Color(0xFF93C5FD)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: matchingSuggestions.map((prod) {
                      final cost = (prod['purchase_price'] as num?)?.toDouble() ?? 0.0;
                      return ListTile(
                        dense: true,
                        title: Text((prod['name'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
                        trailing: Text('التكلفة: ${cost.toStringAsFixed(1)}'),
                        onTap: () => _addProductToPurchase(prod),
                      );
                    }).toList(),
                  ),
                ),

              // 4. رأس الجدول: المنتج | التكلفه | الكمية | الإجمالي
              Container(
                margin: const EdgeInsets.only(top: 4),
                color: const Color(0xFFE5E7EB),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                child: const Row(
                  children: [
                    Expanded(flex: 4, child: Text('المنتج', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500))),
                    Expanded(flex: 2, child: Text('التكلفه', textAlign: TextAlign.center, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500))),
                    Expanded(flex: 2, child: Text('الكمية', textAlign: TextAlign.center, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500))),
                    Expanded(flex: 2, child: Text('الإجمالي', textAlign: TextAlign.left, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500))),
                  ],
                ),
              ),

              // 5. جدول أصناف فاتورة المشتريات + الزر العائم للشبكة السريعة
              Expanded(
                child: Stack(
                  children: [
                    _purchaseItems.isEmpty
                        ? const SizedBox.expand()
                        : ListView.separated(
                            itemCount: _purchaseItems.length,
                            separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade300),
                            itemBuilder: (_, idx) {
                              final item = _purchaseItems[idx];
                              final cost = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
                              final qty = (item['quantity'] as num?)?.toDouble() ?? 1.0;
                              final lineTotal = (item['total'] as num?)?.toDouble() ?? 0.0;

                              return InkWell(
                                onTap: () => _editPurchaseItemDialog(idx),
                                child: Container(
                                  color: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 4,
                                        child: Text(
                                          (item['product_name'] ?? '').toString(),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          cost.toStringAsFixed(2),
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(fontSize: 13.5),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          qty.toString(),
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          lineTotal.toStringAsFixed(2),
                                          textAlign: TextAlign.left,
                                          style: const TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF1545B5),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                    Positioned(
                      left: 14,
                      bottom: 14,
                      child: FloatingActionButton.small(
                        heroTag: 'purchase_grid_fab',
                        backgroundColor: const Color(0xFFD1D5DB),
                        foregroundColor: Colors.black87,
                        elevation: 2,
                        tooltip: 'اختيار سريع من الأصناف',
                        onPressed: _openQuickProductGridSheet,
                        child: const Icon(Icons.apps_rounded, size: 22),
                      ),
                    ),
                  ],
                ),
              ),

              // 6. الشريط السفلي للإجمالي والعملة الثانية
              Container(
                color: const Color(0xFFE5E7EB),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    const Text(
                      'الإجمالي',
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 5,
                      child: Container(
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE6EE9C),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.black38),
                        ),
                        child: Text(
                          _grandTotal.toStringAsFixed(2),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFD32F2F),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'ع.ق',
                      style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: Container(
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.black38),
                        ),
                        child: Text(
                          secondaryTotal.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFD32F2F),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TextWeightW600 extends TextStyle {
  const TextWeightW600() : super(fontWeight: FontWeight.w600);
}
// =============================================================================
// القسم (7 من 10): واجهة المخزون (InventoryScreen) + إضافة منتج + إضافة تصنيف
// =============================================================================

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  String _currencySymbol = 'ريال';

  @override
  void initState() {
    super.initState();
    _loadCurrency();
  }

  Future<void> _loadCurrency() async {
    final settings = await DatabaseHelper.instance.getSettingsMap();
    if (!mounted) return;
    setState(() {
      _currencySymbol = (settings['currency_symbol'] ?? 'ريال').trim();
    });
  }

  // 1. اضافة منتج جديد
  Future<void> _openAddNewProductScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const _AddNewProductScreen(),
      ),
    );
  }

  // 2. عرض المنتجات
  Future<void> _openProductsListScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _InventoryProductsViewScreen(currencySymbol: _currencySymbol),
      ),
    );
  }

  // 3. اضافة تصنيف جديد
  Future<void> _openAddNewCategoryScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const _AddNewCategoryScreen(),
      ),
    );
  }

  // 4. تعديل اسعار المنتجات
  Future<void> _openBulkPriceEditorScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _BulkPriceEditScreen(currencySymbol: _currencySymbol),
      ),
    );
  }

  Widget _buildInventoryMenuCard({
    required Widget iconWidget,
    required String title,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
            child: Row(
              children: [
                SizedBox(
                  width: 34,
                  height: 34,
                  child: Center(child: iconWidget),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Text(
                    title,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF262626),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F4F6),
        body: SafeArea(
          child: Column(
            children: [
              // الترويسة العلوية: أيقونة الصندوق الذهبي وعنوان "المخزون"
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 16, 20, 18),
                child: Row(
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      decoration: const BoxDecoration(
                        color: Color(0xFFE5E7EB),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: CustomPaint(
                          size: const Size(38, 38),
                          painter: _IsometricBoxPainter(),
                        ),
                      ),
                    ),
                    const Expanded(
                      child: Center(
                        child: Text(
                          'المخزون',
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'رجوع',
                      icon: const Icon(Icons.arrow_forward_ios, color: Colors.black38, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // البطاقات الأربع في شاشة المخزون
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  children: [
                    _buildInventoryMenuCard(
                      iconWidget: const Icon(Icons.add, color: Color(0xFF7CB342), size: 32),
                      title: 'اضافة منتج جديد',
                      onTap: _openAddNewProductScreen,
                    ),
                    _buildInventoryMenuCard(
                      iconWidget: const Icon(Icons.search, color: Color(0xFF8E8E93), size: 30),
                      title: 'عرض المنتجات',
                      onTap: _openProductsListScreen,
                    ),
                    _buildInventoryMenuCard(
                      iconWidget: const Icon(Icons.add, color: Color(0xFF7CB342), size: 32),
                      title: 'اضافة تصنيف جديد',
                      onTap: _openAddNewCategoryScreen,
                    ),
                    _buildInventoryMenuCard(
                      iconWidget: const Icon(Icons.swap_horiz_rounded, color: Color(0xFF424242), size: 32),
                      title: 'تعديل اسعار المنتجات',
                      onTap: _openBulkPriceEditorScreen,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// شاشة إضافة منتج جديد الكاملة
// -----------------------------------------------------------------------------
class _AddNewProductScreen extends StatefulWidget {
  const _AddNewProductScreen();

  @override
  State<_AddNewProductScreen> createState() => _AddNewProductScreenState();
}

class _AddNewProductScreenState extends State<_AddNewProductScreen> {
  final TextEditingController _barcodeCtrl = TextEditingController();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();
  final TextEditingController _sale1Ctrl = TextEditingController(text: '0.0');
  final TextEditingController _sale2Ctrl = TextEditingController(text: '0.0');
  final TextEditingController _sale3Ctrl = TextEditingController(text: '0.0');
  final TextEditingController _costCtrl = TextEditingController(text: '0.0');
  final TextEditingController _qtyCtrl = TextEditingController(text: '0');
  final TextEditingController _minStockCtrl = TextEditingController(text: '0');
  final TextEditingController _unitPackCtrl = TextEditingController(text: '0');

  DateTime _expiryDate = DateTime.now();
  String _selectedTax = '---';
  int? _selectedCategoryId;
  String _selectedUnit = '---';
  String _selectedHigherUnit = '---';
  String _selectedTileColor = 'اصفر';
  String? _imagePath;
  bool _saving = false;

  DbRows _categories = [];
  final List<String> _units = ['---', 'حبة', 'كرتون', 'درزن', 'علبة', 'طقم'];
  final List<String> _higherUnits = ['---', 'كرتون', 'شدة', 'صندوق'];
  final List<String> _taxOptions = ['---', '5%', '15%'];
  final List<String> _tileColors = [
    'اصفر',
    'اخضر',
    'ازرق',
    'احمر',
    'برتقالي',
    'بنفسجي',
    'رمادي',
  ];

  @override
  void initState() {
    super.initState();
    _barcodeCtrl.text = _generateDefaultBarcode();
    _loadCategories();
  }

  @override
  void dispose() {
    _barcodeCtrl.dispose();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _sale1Ctrl.dispose();
    _sale2Ctrl.dispose();
    _sale3Ctrl.dispose();
    _costCtrl.dispose();
    _qtyCtrl.dispose();
    _minStockCtrl.dispose();
    _unitPackCtrl.dispose();
    super.dispose();
  }

  String _generateDefaultBarcode() {
    final now = DateTime.now();
    final yy = (now.year % 100).toString().padLeft(2, '0');
    final mm = now.month.toString().padLeft(2, '0');
    final dd = now.day.toString().padLeft(2, '0');
    final suffix = (now.millisecondsSinceEpoch % 1000000).toString().padLeft(6, '0');
    return '$yy$mm$dd$suffix';
  }

  String get _formattedExpiryDate {
    final y = _expiryDate.year.toString().padLeft(4, '0');
    final m = _expiryDate.month.toString().padLeft(2, '0');
    final d = _expiryDate.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<void> _loadCategories() async {
    final cats = await DatabaseHelper.instance.queryAllCategories();
    if (!mounted) return;
    setState(() => _categories = cats);
  }

  Future<void> _scanBarcode() async {
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const BarcodeScannerScreen(title: 'قراءة رقم المنتج (Barcode)'),
      ),
    );
    if (scanned != null && scanned.isNotEmpty && mounted) {
      setState(() => _barcodeCtrl.text = scanned.trim());
    }
  }

  Future<void> _pickExpiryDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
    );
    if (picked != null && mounted) {
      setState(() => _expiryDate = picked);
    }
  }

  Future<void> _addNewUnitDialog() async {
    final unitNameCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('إضافة وحدة جديدة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          content: TextField(
            controller: unitNameCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'اسم الوحدة (مثلاً: باكت، متر، كيس)',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF7CB342)),
              onPressed: () {
                final u = unitNameCtrl.text.trim();
                if (u.isNotEmpty) {
                  setState(() {
                    if (!_units.contains(u)) _units.add(u);
                    _selectedUnit = u;
                  });
                }
                Navigator.of(ctx).pop();
              },
              child: const Text('إضافة'),
            ),
          ],
        ),
      ),
    );
  }

  void _showUnitHelpDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('شرح نظام الوحدات والعبوة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          content: const Text(
            '• الوحدة: الوحدة الأساسية للبيع (مثل: حبة).\n'
            '• عبوة الوحدة: عدد الحبات داخل العبوة الأعلى (مثل: 12).\n'
            '• العبوة الأعلى: وحدة الجملة الكبرى (مثل: كرتون أو درزن).',
            style: TextStyle(height: 1.5, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('حسناً'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickProductImage({required bool fromCamera}) async {
    if (fromCamera) {
      await AppPermissionsService.ensureCameraPermission(openSettingsIfDenied: true);
    } else {
      await AppPermissionsService.ensureStoragePermissions();
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
    );
    if (result == null || result.files.single.path == null) return;

    try {
      final srcFile = File(result.files.single.path!);
      final appDir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory('${appDir.path}/product_images');
      if (!await imagesDir.exists()) {
        await imagesDir.create(recursive: true);
      }
      final ext = srcFile.path.split('.').last;
      final destPath = '${imagesDir.path}/prod_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await srcFile.copy(destPath);
      if (!mounted) return;
      setState(() => _imagePath = destPath);
    } catch (_) {
      if (!mounted) return;
      setState(() => _imagePath = result.files.single.path);
    }
  }

  Future<void> _saveProduct() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال اسم المنتج أولاً')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final barcode = _barcodeCtrl.text.trim();
      final s1 = double.tryParse(_sale1Ctrl.text.trim()) ?? 0.0;
      final s2 = double.tryParse(_sale2Ctrl.text.trim()) ?? 0.0;
      final s3 = double.tryParse(_sale3Ctrl.text.trim()) ?? 0.0;
      final cost = double.tryParse(_costCtrl.text.trim()) ?? 0.0;
      final qty = double.tryParse(_qtyCtrl.text.trim()) ?? 0.0;
      final minStock = double.tryParse(_minStockCtrl.text.trim()) ?? 0.0;

      final newId = await DatabaseHelper.instance.insertProduct({
        'name': name,
        'category_id': _selectedCategoryId,
        'barcode': barcode.isEmpty ? null : barcode,
        'purchase_price': cost,
        'sale_price': s1,
        'wholesale_price': s2,
        'special_price': s3,
        'stock_quantity': qty,
        'min_stock': minStock,
        'is_active': 1,
      });

      final db = await DatabaseHelper.instance.database;
      const extraColumns = [
        'description TEXT',
        'expiry_date TEXT',
        'tax_rate TEXT',
        'unit_name TEXT',
        'unit_pack REAL',
        'higher_unit TEXT',
        'tile_color TEXT',
        'image_path TEXT',
      ];
      for (final colDef in extraColumns) {
        try {
          await db.execute('ALTER TABLE products ADD COLUMN $colDef');
        } catch (_) {}
      }

      await db.update(
        'products',
        {
          'description': _descCtrl.text.trim(),
          'expiry_date': _formattedExpiryDate,
          'tax_rate': _selectedTax,
          'unit_name': _selectedUnit,
          'unit_pack': double.tryParse(_unitPackCtrl.text.trim()) ?? 0.0,
          'higher_unit': _selectedHigherUnit,
          'tile_color': _selectedTileColor,
          'image_path': _imagePath,
        },
        where: 'id = ?',
        whereArgs: [newId],
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم حفظ المنتج "$name" بنجاح')),
      );
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حدث خطأ أثناء حفظ بيانات المنتج')),
      );
    }
  }

  InputDecoration _roundedInputDecoration() {
    return InputDecoration(
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFA7B8C8), width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF1545B5), width: 1.8),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5, top: 8),
      child: Align(
        alignment: Alignment.centerRight,
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: Color(0xFF262626),
          ),
        ),
      ),
    );
  }

  Color _getColorPreview(String colorName) {
    switch (colorName) {
      case 'اصفر':
        return const Color(0xFFFACC15);
      case 'اخضر':
        return const Color(0xFF22C55E);
      case 'ازرق':
        return const Color(0xFF3B82F6);
      case 'احمر':
        return const Color(0xFFEF4444);
      case 'برتقالي':
        return const Color(0xFFF97316);
      case 'بنفسجي':
        return const Color(0xFFA855F7);
      default:
        return const Color(0xFF9CA3AF);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F7F7),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF7F7F7),
          elevation: 0.5,
          surfaceTintColor: const Color(0xFFF7F7F7),
          automaticallyImplyLeading: false,
          titleSpacing: 12,
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_forward_ios, color: Colors.black54, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Text(
                    'اضافة منتج جديد',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                ],
              ),
              // زر القرص المرن (حفظ)
              InkWell(
                onTap: _saving ? null : _saveProduct,
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  width: 44,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4B89DC),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF2C5AA0), width: 1.2),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: const Text(
                          'حفظ',
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 10.5,
                            height: 1.1,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Container(
                        width: 22,
                        height: 11,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD6E4F0),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. رقم المنتج (Barcode) + زر قراءة
              _sectionLabel('رقم المنتج(Barcode)'),
              Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: SizedBox(
                      height: 44,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE0E0E0),
                          foregroundColor: Colors.black87,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        ),
                        onPressed: _scanBarcode,
                        child: const Text(
                          'قراءة',
                          style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 6,
                    child: TextField(
                      controller: _barcodeCtrl,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFD81B60),
                        backgroundColor: Color(0xFFFCE4EC),
                      ),
                      decoration: _roundedInputDecoration(),
                    ),
                  ),
                ],
              ),

              // 2. اسم المنتج
              _sectionLabel('اسم المنتج'),
              TextField(
                controller: _nameCtrl,
                decoration: _roundedInputDecoration(),
              ),

              // 3. الوصف
              _sectionLabel('الوصف'),
              TextField(
                controller: _descCtrl,
                maxLines: 3,
                decoration: _roundedInputDecoration(),
              ),

              // 4. أسعار البيع الثلاثة
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        const Text('سعر البيع', style: TextStyle(fontSize: 14.5)),
                        const SizedBox(height: 5),
                        TextField(
                          controller: _sale1Ctrl,
                          textAlign: TextAlign.center,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(fontSize: 16, color: Colors.black54),
                          decoration: _roundedInputDecoration(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      children: [
                        const Text('سعر البيع2', style: TextStyle(fontSize: 14.5)),
                        const SizedBox(height: 5),
                        TextField(
                          controller: _sale2Ctrl,
                          textAlign: TextAlign.center,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(fontSize: 16, color: Colors.black54),
                          decoration: _roundedInputDecoration(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      children: [
                        const Text('سعر البيع3', style: TextStyle(fontSize: 14.5)),
                        const SizedBox(height: 5),
                        TextField(
                          controller: _sale3Ctrl,
                          textAlign: TextAlign.center,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(fontSize: 16, color: Colors.black54),
                          decoration: _roundedInputDecoration(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // 5. سعر الشراء-التكلفة
              _sectionLabel('سعر الشراء-التكلفة'),
              TextField(
                controller: _costCtrl,
                textAlign: TextAlign.center,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 16, color: Colors.black54),
                decoration: _roundedInputDecoration(),
              ),

              // 6. الكمية
              _sectionLabel('الكمية'),
              TextField(
                controller: _qtyCtrl,
                textAlign: TextAlign.center,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 16, color: Colors.black54),
                decoration: _roundedInputDecoration(),
              ),

              // 7. حد الطلب
              _sectionLabel('حد الطلب(التنبية عند وصول المنتج للكمية)'),
              TextField(
                controller: _minStockCtrl,
                textAlign: TextAlign.center,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 16, color: Colors.black54),
                decoration: _roundedInputDecoration(),
              ),

              // 8. تاريخ الانتهاء
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFA7B8C8), width: 1.5),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Center(
                        child: Text(
                          'تاريخ الانتهاء',
                          style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: _pickExpiryDate,
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE0E0E0),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _formattedExpiryDate,
                            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 9. الضريبة TAX
              _sectionLabel('الضريبة TAX'),
              Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 110,
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedTax,
                      isExpanded: true,
                      items: _taxOptions
                          .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedTax = v ?? '---'),
                    ),
                  ),
                ),
              ),

              // 10. التصنيف
              _sectionLabel('التصنيف'),
              Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 160,
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int?>(
                      value: _selectedCategoryId,
                      isExpanded: true,
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('---')),
                        ..._categories.map(
                          (c) => DropdownMenuItem<int?>(
                            value: c['id'] as int,
                            child: Text((c['name'] ?? '').toString()),
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() => _selectedCategoryId = v),
                    ),
                  ),
                ),
              ),

              // 11. بطاقة الوحدات
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFA7B8C8), width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('الوحده', style: TextStyle(fontSize: 15)),
                            SizedBox(
                              width: 120,
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _selectedUnit,
                                  isExpanded: true,
                                  items: _units
                                      .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                                      .toList(),
                                  onChanged: (v) => setState(() => _selectedUnit = v ?? '---'),
                                ),
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          tooltip: 'إضافة وحدة جديدة',
                          icon: const Icon(Icons.add, color: Color(0xFF7CB342), size: 30),
                          onPressed: _addNewUnitDialog,
                        ),
                      ],
                    ),
                    const Align(
                      alignment: Alignment.centerRight,
                      child: Text('عبوه الوحده', style: TextStyle(fontSize: 15)),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _unitPackCtrl,
                      textAlign: TextAlign.center,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(fontSize: 16, color: Colors.black54),
                      decoration: _roundedInputDecoration(),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('العبوة الاعلى', style: TextStyle(fontSize: 15)),
                            SizedBox(
                              width: 120,
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _selectedHigherUnit,
                                  isExpanded: true,
                                  items: _higherUnits
                                      .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                                      .toList(),
                                  onChanged: (v) => setState(() => _selectedHigherUnit = v ?? '---'),
                                ),
                              ),
                            ),
                          ],
                        ),
                        InkWell(
                          onTap: _showUnitHelpDialog,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            width: 42,
                            height: 30,
                            decoration: BoxDecoration(
                              color: const Color(0xFFD32F2F),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.play_arrow, color: Colors.white, size: 22),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // 12. لون المربع في قائمه العرض
              _sectionLabel('لون المربع في قائمه العرض'),
              Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 150,
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedTileColor,
                      isExpanded: true,
                      items: _tileColors
                          .map(
                            (c) => DropdownMenuItem(
                              value: c,
                              child: Row(
                                children: [
                                  Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: _getColorPreview(c),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(c, style: const TextStyle(fontSize: 18)),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _selectedTileColor = v ?? 'اصفر'),
                    ),
                  ),
                ),
              ),

              // 13. صوره المنتج اختياري
              _sectionLabel('صوره المنتج اختياري'),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  SizedBox(
                    height: 44,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE0E0E0),
                        foregroundColor: Colors.black87,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                      onPressed: () => _pickProductImage(fromCamera: false),
                      child: const Text('من الاستديو', style: TextStyle(fontSize: 14.5)),
                    ),
                  ),
                  Container(
                    width: 145,
                    height: 155,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.grey.shade400),
                    ),
                    child: _imagePath != null && File(_imagePath!).existsSync()
                        ? Image.file(File(_imagePath!), fit: BoxFit.cover)
                        : Center(
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Icon(Icons.insert_drive_file, size: 118, color: Colors.grey.shade600),
                                Positioned(
                                  bottom: 24,
                                  child: Container(
                                    width: 58,
                                    height: 44,
                                    color: Colors.white,
                                    child: Icon(Icons.landscape, size: 40, color: Colors.grey.shade600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                  SizedBox(
                    height: 44,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE0E0E0),
                        foregroundColor: Colors.black87,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                      onPressed: () => _pickProductImage(fromCamera: true),
                      child: const Text('من الكامرا', style: TextStyle(fontSize: 14.5)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Center(
                child: SizedBox(
                  width: 135,
                  height: 44,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE0E0E0),
                      foregroundColor: Colors.black87,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                    onPressed: () => setState(() => _imagePath = null),
                    child: const Text('إلغاء الصورة', style: TextStyle(fontSize: 15)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// شاشة إضافة تصنيف جديد
// -----------------------------------------------------------------------------
class _AddNewCategoryScreen extends StatefulWidget {
  const _AddNewCategoryScreen();

  @override
  State<_AddNewCategoryScreen> createState() => _AddNewCategoryScreenState();
}

class _AddNewCategoryScreenState extends State<_AddNewCategoryScreen> {
  final TextEditingController _nameCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveCategory() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال اسم التصنيف أولاً')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final db = await DatabaseHelper.instance.database;
      final existing = await db.query(
        'categories',
        where: 'LOWER(TRIM(name)) = ?',
        whereArgs: [name.toLowerCase()],
      );

      if (existing.isNotEmpty) {
        if (!mounted) return;
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('هذا التصنيف مسجل مسبقاً')),
        );
        return;
      }

      await db.insert('categories', {'name': name});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم حفظ التصنيف "$name" بنجاح')),
      );
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر حفظ التصنيف')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // الشريط العلوي الأسود مع زر القرص المرن (حفظ)
              Container(
                height: 54,
                color: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    InkWell(
                      onTap: _saving ? null : _saveCategory,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        width: 46,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xFF4B89DC),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: const Color(0xFF2C5AA0), width: 1.2),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: const Text(
                                'حفظ',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                  height: 1.1,
                                ),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Container(
                              width: 24,
                              height: 12,
                              decoration: BoxDecoration(
                                color: const Color(0xFFD6E4F0),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'رجوع',
                      icon: const Icon(Icons.arrow_back, color: Colors.white70, size: 22),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // حقل إدخال اسم التصنيف
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'اسم التصنيف',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF424242),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nameCtrl,
                      autofocus: true,
                      textAlign: TextAlign.right,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _saveCategory(),
                      style: const TextStyle(fontSize: 17, color: Colors.black87),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(2),
                          borderSide: const BorderSide(color: Color(0xFFBDBDBD), width: 1.2),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(2),
                          borderSide: const BorderSide(color: Color(0xFF4B89DC), width: 1.6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// رسم أيقونة الصندوق الذهبي ثلاثي الأبعاد في ترويسة المخزون
// -----------------------------------------------------------------------------
class _IsometricBoxPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final topPaint = Paint()..color = const Color(0xFFF3CE6B);
    final leftPaint = Paint()..color = const Color(0xFFD9A944);
    final rightPaint = Paint()..color = const Color(0xFFE7BC57);
    final tapePaint = Paint()..color = const Color(0xFFC49232);

    final topPath = Path()
      ..moveTo(w * 0.50, h * 0.14)
      ..lineTo(w * 0.86, h * 0.32)
      ..lineTo(w * 0.50, h * 0.50)
      ..lineTo(w * 0.14, h * 0.32)
      ..close();

    final leftPath = Path()
      ..moveTo(w * 0.14, h * 0.32)
      ..lineTo(w * 0.50, h * 0.50)
      ..lineTo(w * 0.50, h * 0.88)
      ..lineTo(w * 0.14, h * 0.70)
      ..close();

    final rightPath = Path()
      ..moveTo(w * 0.86, h * 0.32)
      ..lineTo(w * 0.50, h * 0.50)
      ..lineTo(w * 0.50, h * 0.88)
      ..lineTo(w * 0.86, h * 0.70)
      ..close();

    final tapePath = Path()
      ..moveTo(w * 0.32, h * 0.23)
      ..lineTo(w * 0.68, h * 0.41)
      ..lineTo(w * 0.62, h * 0.44)
      ..lineTo(w * 0.26, h * 0.26)
      ..close();

    canvas.drawPath(topPath, topPaint);
    canvas.drawPath(leftPath, leftPaint);
    canvas.drawPath(rightPath, rightPaint);
    canvas.drawPath(tapePath, tapePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
// =============================================================================
// القسم (8 من 10): شاشة عرض المنتجات (التقرير وصناعة الباركود) + تعديل الأسعار
// =============================================================================

class _InventoryProductsViewScreen extends StatefulWidget {
  final String currencySymbol;

  const _InventoryProductsViewScreen({required this.currencySymbol});

  @override
  State<_InventoryProductsViewScreen> createState() => _InventoryProductsViewScreenState();
}

class _InventoryProductsViewScreenState extends State<_InventoryProductsViewScreen> {
  DbRows _products = [];
  DbRows _categories = [];
  final Set<int> _selectedIds = <int>{};
  int? _selectedCategoryId;
  String _search = '';
  bool _onlyLowStock = false;
  bool _loading = true;

  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final prods = await DatabaseHelper.instance.queryAllProducts();
    final cats = await DatabaseHelper.instance.queryAllCategories();
    if (!mounted) return;
    setState(() {
      _products = prods;
      _categories = cats;
      _selectedIds.removeWhere((id) => !prods.any((p) => p['id'] == id));
      _loading = false;
    });
  }

  DbRows get _filteredProducts {
    final q = _search.trim().toLowerCase();
    return _products.where((p) {
      if (_selectedCategoryId != null && p['category_id'] != _selectedCategoryId) {
        return false;
      }
      final stock = (p['stock_quantity'] as num?)?.toDouble() ?? 0.0;
      final minStock = (p['min_stock'] as num?)?.toDouble() ?? 2.0;
      if (_onlyLowStock && stock > minStock) {
        return false;
      }
      if (q.isEmpty) return true;
      final name = (p['name'] ?? '').toString().toLowerCase();
      final barcode = (p['barcode'] ?? '').toString().toLowerCase();
      return name.contains(q) || barcode.contains(q);
    }).toList();
  }

  Future<void> _scanBarcodeToSearch() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const BarcodeScannerScreen(title: 'بحث عن منتج بالباركود'),
      ),
    );
    if (code != null && code.isNotEmpty && mounted) {
      _searchCtrl.text = code.trim();
      setState(() => _search = code.trim());
    }
  }

  // 1. زر (تقرير) - تقرير جرد المخزون وطباعته PDF أو تصديره Excel
  Future<void> _openInventoryReportDialog() async {
    final list = _filteredProducts;
    double totalQty = 0.0;
    double totalCost = 0.0;
    double totalSale = 0.0;
    int lowCount = 0;

    for (final p in list) {
      final qty = (p['stock_quantity'] as num?)?.toDouble() ?? 0.0;
      final minStock = (p['min_stock'] as num?)?.toDouble() ?? 2.0;
      final cost = (p['purchase_price'] as num?)?.toDouble() ?? 0.0;
      final sale = (p['sale_price'] as num?)?.toDouble() ?? 0.0;
      totalQty += qty;
      totalCost += qty * cost;
      totalSale += qty * sale;
      if (qty <= minStock) lowCount++;
    }
    final expectedProfit = totalSale - totalCost;

    await showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          title: const Text(
            'تقرير جرد المخزون',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _reportStatRow('عدد الأصناف:', '${list.length} صنف'),
                _reportStatRow('إجمالي الكميات بالمخزن:', totalQty.toStringAsFixed(1)),
                _reportStatRow(
                  'قيمة المخزون بالتكلفة:',
                  '${totalCost.toStringAsFixed(2)} ${widget.currencySymbol}',
                ),
                _reportStatRow(
                  'القيمة البيعية المتوقعة:',
                  '${totalSale.toStringAsFixed(2)} ${widget.currencySymbol}',
                ),
                _reportStatRow(
                  'الأرباح المتوقعة:',
                  '${expectedProfit.toStringAsFixed(2)} ${widget.currencySymbol}',
                  valueColor: const Color(0xFF16A34A),
                ),
                _reportStatRow(
                  'الأصناف الناقصة:',
                  '$lowCount صنف',
                  valueColor: lowCount > 0 ? const Color(0xFFDC2626) : Colors.black87,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('إغلاق'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await _exportProductsCsv(list);
              },
              icon: const Icon(Icons.table_view, size: 18),
              label: const Text('تصدير Excel'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1545B5)),
              onPressed: () async {
                Navigator.of(ctx).pop();
                await _printInventoryReportPdf(list, totalCost, totalSale, expectedProfit);
              },
              icon: const Icon(Icons.print, size: 18),
              label: const Text('طباعة PDF'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reportStatRow(String label, String value, {Color valueColor = Colors.black87}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13.5, color: Colors.black54)),
          Text(
            value,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: valueColor),
          ),
        ],
      ),
    );
  }

  Future<void> _exportProductsCsv(DbRows list) async {
    await AppPermissionsService.ensureStoragePermissions();
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/inventory_report_${DateTime.now().millisecondsSinceEpoch}.csv');
    final buf = StringBuffer('\uFEFFالمنتج,الباركود,سعر التكلفة,سعر البيع,الكمية,إجمالي التكلفة\n');
    for (final p in list) {
      final name = (p['name'] ?? '').toString().replaceAll(',', ' ');
      final barcode = (p['barcode'] ?? '').toString();
      final cost = (p['purchase_price'] as num?)?.toDouble() ?? 0.0;
      final sale = (p['sale_price'] as num?)?.toDouble() ?? 0.0;
      final qty = (p['stock_quantity'] as num?)?.toDouble() ?? 0.0;
      buf.writeln('$name,$barcode,$cost,$sale,$qty,${(cost * qty).toStringAsFixed(2)}');
    }
    await file.writeAsString(buf.toString(), encoding: utf8);
    await Share.shareXFiles([XFile(file.path)], text: 'تقرير جرد المخزون');
  }

  Future<void> _printInventoryReportPdf(
    DbRows list,
    double totalCost,
    double totalSale,
    double expectedProfit,
  ) async {
    final settings = await DatabaseHelper.instance.getSettingsMap();
    final shopName = (settings['store_name'] ?? 'نبراس SofT').toString();
    final dateStr = DateTime.now().toString().split('.').first;

    final rowsHtml = StringBuffer();
    for (int i = 0; i < list.length; i++) {
      final p = list[i];
      final cost = (p['purchase_price'] as num?)?.toDouble() ?? 0.0;
      final sale = (p['sale_price'] as num?)?.toDouble() ?? 0.0;
      final qty = (p['stock_quantity'] as num?)?.toDouble() ?? 0.0;
      rowsHtml.writeln('''
        <tr>
          <td>${i + 1}</td>
          <td>${p['name'] ?? ''}</td>
          <td>${p['barcode'] ?? '-'}</td>
          <td>${cost.toStringAsFixed(2)}</td>
          <td>${sale.toStringAsFixed(2)}</td>
          <td>$qty</td>
        </tr>
      ''');
    }

    final html = '''
    <!DOCTYPE html>
    <html dir="rtl" lang="ar">
    <head>
      <meta charset="UTF-8">
      <style>
        body { font-family: sans-serif; direction: rtl; padding: 16px; }
        h2, p { text-align: center; margin: 4px 0; }
        table { width: 100%; border-collapse: collapse; margin-top: 12px; font-size: 12px; }
        th, td { border: 1px solid #999; padding: 6px; text-align: center; }
        th { background-color: #e5e7eb; }
        .summary { margin-top: 14px; font-size: 13px; font-weight: bold; }
      </style>
    </head>
    <body>
      <h2>$shopName - تقرير المنتجات المتوفرة في المخزن</h2>
      <p>التاريخ: $dateStr</p>
      <table>
        <thead>
          <tr>
            <th>#</th>
            <th>المنتج</th>
            <th>الباركود</th>
            <th>التكلفة</th>
            <th>السعر</th>
            <th>الكمية</th>
          </tr>
        </thead>
        <tbody>
          $rowsHtml
        </tbody>
      </table>
      <div class="summary">
        <p>عدد الأصناف: ${list.length} | إجمالي التكلفة: ${totalCost.toStringAsFixed(2)} ${widget.currencySymbol} | القيمة البيعية: ${totalSale.toStringAsFixed(2)} ${widget.currencySymbol} | الأرباح المتوقعة: ${expectedProfit.toStringAsFixed(2)} ${widget.currencySymbol}</p>
      </div>
    </body>
    </html>
    ''';

    await Printing.layoutPdf(
      onLayout: (format) => Printing.convertHtml(format: format, html: html),
    );
  }

  // 2. زر (صناعه الباركود) - توليد وطباعة ملصقات الباركود
  Future<void> _openBarcodeMakerDialog() async {
    final visible = _filteredProducts;
    if (visible.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد منتجات في القائمة لصناعة الباركود')),
      );
      return;
    }

    DbRows targetProducts = visible.where((p) => _selectedIds.contains(p['id'])).toList();
    int? singleSelectedId = targetProducts.isNotEmpty
        ? targetProducts.first['id'] as int
        : visible.first['id'] as int;
    final copiesCtrl = TextEditingController(text: '4');
    bool showPriceOnLabel = true;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            title: const Text(
              'صناعه الباركود وطباعة الملصقات',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.5),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_selectedIds.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE6F7D4),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'تم تحديد ${_selectedIds.length} منتج من الجدول لطباعة ملصقاتها.',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    )
                  else
                    DropdownButtonFormField<int>(
                      value: singleSelectedId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'اختر المنتج',
                        border: OutlineInputBorder(),
                      ),
                      items: visible
                          .map(
                            (p) => DropdownMenuItem<int>(
                              value: p['id'] as int,
                              child: Text(
                                (p['name'] ?? '').toString(),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setDialogState(() => singleSelectedId = v),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: copiesCtrl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      labelText: 'عدد الملصقات لكل منتج',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 6),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: showPriceOnLabel,
                    onChanged: (v) => setDialogState(() => showPriceOnLabel = v ?? true),
                    title: const Text('إظهار السعر على ملصق الباركود', style: TextStyle(fontSize: 13.5)),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('إلغاء'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1545B5)),
                onPressed: () async {
                  final copies = (int.tryParse(copiesCtrl.text.trim()) ?? 1).clamp(1, 200);
                  if (_selectedIds.isEmpty && singleSelectedId != null) {
                    targetProducts = visible.where((p) => p['id'] == singleSelectedId).toList();
                  }
                  Navigator.of(ctx).pop();
                  await _generateAndPrintBarcodeLabels(
                    products: targetProducts,
                    copiesPerProduct: copies,
                    showPrice: showPriceOnLabel,
                  );
                },
                icon: const Icon(Icons.qr_code_2),
                label: const Text('توليد وطباعة'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _buildBarcodeSvgBars(String code) {
    final seed = code.codeUnits.fold<int>(0, (a, b) => a + b);
    final widths = [2, 4, 1, 3, 2, 1, 4, 2, 3, 1, 2, 4, 1, 3, 2, 2, 3, 1, 4, 2];
    final buf = StringBuffer();
    for (int i = 0; i < 28; i++) {
      final w = widths[(i + seed) % widths.length];
      buf.write('<span style="display:inline-block;height:36px;width:${w}px;background:#000;margin-left:2px;"></span>');
    }
    return buf.toString();
  }

  Future<void> _generateAndPrintBarcodeLabels({
    required DbRows products,
    required int copiesPerProduct,
    required bool showPrice,
  }) async {
    final settings = await DatabaseHelper.instance.getSettingsMap();
    final storeName = (settings['store_name'] ?? 'نبراس SofT').toString();
    final db = await DatabaseHelper.instance.database;

    final labelsHtml = StringBuffer();
    for (final prod in products) {
      String code = (prod['barcode'] ?? '').toString().trim();
      if (code.isEmpty) {
        code = '200${prod['id'].toString().padLeft(6, '0')}';
        await db.update(
          'products',
          {'barcode': code},
          where: 'id = ?',
          whereArgs: [prod['id']],
        );
      }
      final name = (prod['name'] ?? '').toString();
      final price = ((prod['sale_price'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2);
      final bars = _buildBarcodeSvgBars(code);

      for (int c = 0; c < copiesPerProduct; c++) {
        labelsHtml.writeln('''
          <div class="label">
            <div class="store">$storeName</div>
            <div class="pname">$name</div>
            <div class="bars" dir="ltr">$bars</div>
            <div class="code">$code</div>
            ${showPrice ? '<div class="price">السعر: $price ${widget.currencySymbol}</div>' : ''}
          </div>
        ''');
      }
    }

    await _loadData();

    final html = '''
    <!DOCTYPE html>
    <html dir="rtl" lang="ar">
    <head>
      <meta charset="UTF-8">
      <style>
        body { font-family: sans-serif; direction: rtl; margin: 10px; }
        .grid { display: flex; flex-wrap: wrap; gap: 10px; justify-content: center; }
        .label {
          width: 185px;
          border: 1px dashed #666;
          border-radius: 6px;
          padding: 8px 6px;
          text-align: center;
          page-break-inside: avoid;
        }
        .store { font-size: 10px; color: #444; font-weight: bold; }
        .pname { font-size: 12px; font-weight: bold; margin: 3px 0 5px 0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
        .bars { height: 38px; overflow: hidden; display: flex; justify-content: center; align-items: center; }
        .code { font-size: 11px; letter-spacing: 1.5px; margin-top: 2px; font-family: monospace; }
        .price { font-size: 12px; font-weight: bold; margin-top: 3px; }
      </style>
    </head>
    <body>
      <div class="grid">$labelsHtml</div>
    </body>
    </html>
    ''';

    await Printing.layoutPdf(
      onLayout: (format) => Printing.convertHtml(format: format, html: html),
    );
  }

  // 3. زر (المزيد) - قائمة التصفية والخيارات الإضافية
  Future<void> _openMoreOptionsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706)),
                  title: const Text('عرض النواقص فقط', style: TextStyle(fontWeight: FontWeight.w600)),
                  value: _onlyLowStock,
                  onChanged: (v) {
                    setState(() => _onlyLowStock = v);
                    Navigator.of(ctx).pop();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.category_outlined, color: Color(0xFF1545B5)),
                  title: const Text('تصفية حسب التصنيف', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    _selectedCategoryId == null
                        ? 'الكل'
                        : (_categories.firstWhere(
                                  (c) => c['id'] == _selectedCategoryId,
                                  orElse: () => {'name': 'الكل'},
                                )['name'] ??
                                'الكل')
                            .toString(),
                  ),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await _pickCategoryFilterDialog();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.select_all, color: Color(0xFF16A34A)),
                  title: Text(
                    _selectedIds.length == _filteredProducts.length && _filteredProducts.isNotEmpty
                        ? 'إلغاء تحديد الكل'
                        : 'تحديد جميع المنتجات المعروضة',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  onTap: () {
                    final visible = _filteredProducts;
                    setState(() {
                      if (_selectedIds.length == visible.length && visible.isNotEmpty) {
                        _selectedIds.clear();
                      } else {
                        _selectedIds
                          ..clear()
                          ..addAll(visible.map((p) => p['id'] as int));
                      }
                    });
                    Navigator.of(ctx).pop();
                  },
                ),
                if (_selectedIds.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.delete_outline, color: Color(0xFFDC2626)),
                    title: Text(
                      'حذف المنتجات المحددة (${_selectedIds.length})',
                      style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFDC2626)),
                    ),
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      await _deleteSelectedProducts();
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.refresh, color: Colors.black54),
                  title: const Text('تحديث القائمة', style: TextStyle(fontWeight: FontWeight.w600)),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await _loadData();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickCategoryFilterDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('اختر التصنيف', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  title: const Text('جميع التصنيفات'),
                  trailing: _selectedCategoryId == null ? const Icon(Icons.check, color: Color(0xFF16A34A)) : null,
                  onTap: () {
                    setState(() => _selectedCategoryId = null);
                    Navigator.of(ctx).pop();
                  },
                ),
                ..._categories.map((c) {
                  final cid = c['id'] as int;
                  return ListTile(
                    title: Text((c['name'] ?? '').toString()),
                    trailing: _selectedCategoryId == cid ? const Icon(Icons.check, color: Color(0xFF16A34A)) : null,
                    onTap: () {
                      setState(() => _selectedCategoryId = cid);
                      Navigator.of(ctx).pop();
                    },
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _deleteSelectedProducts() async {
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد الحذف'),
          content: Text('هل تريد حذف $count منتج محدد من المخزون؟'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('إلغاء')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    final db = await DatabaseHelper.instance.database;
    for (final id in _selectedIds.toList()) {
      await db.update('products', {'is_active': 0}, where: 'id = ?', whereArgs: [id]);
    }
    _selectedIds.clear();
    await _loadData();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم حذف $count منتج بنجاح')),
    );
  }

  Future<void> _editProductDialog(DbRow prod) async {
    final nameCtrl = TextEditingController(text: (prod['name'] ?? '').toString());
    final barcodeCtrl = TextEditingController(text: (prod['barcode'] ?? '').toString());
    final costCtrl = TextEditingController(text: ((prod['purchase_price'] as num?)?.toDouble() ?? 0.0).toString());
    final sale1Ctrl = TextEditingController(text: ((prod['sale_price'] as num?)?.toDouble() ?? 0.0).toString());
    final sale2Ctrl = TextEditingController(text: ((prod['wholesale_price'] as num?)?.toDouble() ?? 0.0).toString());
    final sale3Ctrl = TextEditingController(text: ((prod['special_price'] as num?)?.toDouble() ?? 0.0).toString());
    final stockCtrl = TextEditingController(text: ((prod['stock_quantity'] as num?)?.toDouble() ?? 0.0).toString());
    int? catId = prod['category_id'] as int?;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            title: const Text('تعديل بيانات المنتج', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'اسم المنتج *', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int?>(
                    value: catId,
                    decoration: const InputDecoration(labelText: 'التصنيف', border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('بدون تصنيف')),
                      ..._categories.map(
                        (c) => DropdownMenuItem<int?>(
                          value: c['id'] as int,
                          child: Text((c['name'] ?? '').toString()),
                        ),
                      ),
                    ],
                    onChanged: (v) => setDialogState(() => catId = v),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: barcodeCtrl,
                    decoration: const InputDecoration(labelText: 'الباركود', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: costCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'التكلفة', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: sale1Ctrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'سعر البيع', border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: sale2Ctrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'سعر البيع 2', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: sale3Ctrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'سعر البيع 3', border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: stockCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'الكمية بالمخزون', border: OutlineInputBorder()),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  final db = await DatabaseHelper.instance.database;
                  await db.update('products', {'is_active': 0}, where: 'id = ?', whereArgs: [prod['id']]);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  await _loadData();
                },
                child: const Text('حذف', style: TextStyle(color: Color(0xFFDC2626))),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () async {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) return;
                  final db = await DatabaseHelper.instance.database;
                  await db.update(
                    'products',
                    {
                      'name': name,
                      'category_id': catId,
                      'barcode': barcodeCtrl.text.trim().isEmpty ? null : barcodeCtrl.text.trim(),
                      'purchase_price': double.tryParse(costCtrl.text.trim()) ?? 0.0,
                      'sale_price': double.tryParse(sale1Ctrl.text.trim()) ?? 0.0,
                      'wholesale_price': double.tryParse(sale2Ctrl.text.trim()) ?? 0.0,
                      'special_price': double.tryParse(sale3Ctrl.text.trim()) ?? 0.0,
                      'stock_quantity': double.tryParse(stockCtrl.text.trim()) ?? 0.0,
                    },
                    where: 'id = ?',
                    whereArgs: [prod['id']],
                  );
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  await _loadData();
                },
                child: const Text('حفظ التعديل'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGrayActionButton(String label, VoidCallback onTap) {
    return Expanded(
      child: SizedBox(
        height: 42,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFDCDCDC),
            foregroundColor: const Color(0xFF262626),
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
          onPressed: onTap,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _filteredProducts;
    final allSelected = list.isNotEmpty && _selectedIds.length == list.length;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              // 1. العنوان العلوي: المنتجات المتوفرة في المخزن
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'رجوع',
                      icon: const Icon(Icons.arrow_forward_ios, color: Colors.black54, size: 19),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const Expanded(
                      child: Text(
                        'المنتجات المتوفرة في المخزن',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF262626),
                        ),
                      ),
                    ),
                    const SizedBox(width: 40),
                  ],
                ),
              ),

              // 2. شريط البحث + زر قارئ الباركود
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.grey.shade300, width: 1),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 38,
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: (v) => setState(() => _search = v),
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 15),
                          decoration: InputDecoration(
                            hintText: 'بحث',
                            hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 16),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            suffixIcon: _search.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.close, size: 17),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      setState(() => _search = '');
                                    },
                                  )
                                : null,
                            enabledBorder: const UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.black45, width: 1.1),
                            ),
                            focusedBorder: const UnderlineInputBorder(
                              borderSide: BorderSide(color: Color(0xFF1545B5), width: 1.8),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    InkWell(
                      onTap: _scanBarcodeToSearch,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 52,
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.black54, width: 1.4),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            Container(width: 2.5, color: Colors.black87),
                            Container(width: 1.5, color: Colors.black87),
                            Container(width: 3, color: Colors.black87),
                            Container(width: 1.5, color: Colors.black87),
                            Container(width: 2.5, color: Colors.black87),
                            Container(width: 1.5, color: Colors.black87),
                            Container(width: 2.5, color: Colors.black87),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 3. الأزرار الثلاثة: تقرير | صناعه الباركود | المزيد
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
                child: Row(
                  children: [
                    _buildGrayActionButton('تقرير', _openInventoryReportDialog),
                    const SizedBox(width: 6),
                    _buildGrayActionButton('صناعه الباركود', _openBarcodeMakerDialog),
                    const SizedBox(width: 6),
                    _buildGrayActionButton('المزيد', _openMoreOptionsSheet),
                  ],
                ),
              ),

              // 4. رأس الجدول: [ ] المنتج | السعر | الكمية
              Container(
                color: const Color(0xFFE5E7EB),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 30,
                            height: 30,
                            child: Checkbox(
                              value: allSelected,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              onChanged: (val) {
                                setState(() {
                                  if (val == true) {
                                    _selectedIds
                                      ..clear()
                                      ..addAll(list.map((p) => p['id'] as int));
                                  } else {
                                    _selectedIds.clear();
                                  }
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'المنتج',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF262626),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Expanded(
                      flex: 2,
                      child: Text(
                        'السعر',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF262626),
                        ),
                      ),
                    ),
                    const Expanded(
                      flex: 2,
                      child: Text(
                        'الكمية',
                        textAlign: TextAlign.left,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF262626),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 5. قائمة المنتجات المتوفرة في المخزن
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : list.isEmpty
                        ? const SizedBox.expand()
                        : ListView.separated(
                            itemCount: list.length,
                            separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade300),
                            itemBuilder: (ctx, idx) {
                              final prod = list[idx];
                              final int pid = prod['id'] as int;
                              final bool checked = _selectedIds.contains(pid);
                              final double salePrice = (prod['sale_price'] as num?)?.toDouble() ?? 0.0;
                              final double qty = (prod['stock_quantity'] as num?)?.toDouble() ?? 0.0;
                              final double minStock = (prod['min_stock'] as num?)?.toDouble() ?? 2.0;
                              final bool isLow = qty <= minStock;

                              return InkWell(
                                onTap: () => _editProductDialog(prod),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 5,
                                        child: Row(
                                          children: [
                                            SizedBox(
                                              width: 30,
                                              height: 30,
                                              child: Checkbox(
                                                value: checked,
                                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                onChanged: (v) {
                                                  setState(() {
                                                    if (v == true) {
                                                      _selectedIds.add(pid);
                                                    } else {
                                                      _selectedIds.remove(pid);
                                                    }
                                                  });
                                                },
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                (prod['name'] ?? '').toString(),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 14.5,
                                                  fontWeight: FontWeight.w500,
                                                  color: Colors.black87,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          salePrice.toStringAsFixed(2),
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(fontSize: 14, color: Colors.black87),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          qty.toString(),
                                          textAlign: TextAlign.left,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: isLow ? const Color(0xFFDC2626) : Colors.black87,
                                          ),
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
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// شاشة تعديل اسعار المنتجات
// -----------------------------------------------------------------------------
class _BulkPriceEditScreen extends StatefulWidget {
  final String currencySymbol;

  const _BulkPriceEditScreen({required this.currencySymbol});

  @override
  State<_BulkPriceEditScreen> createState() => _BulkPriceEditScreenState();
}

class _BulkPriceEditScreenState extends State<_BulkPriceEditScreen> {
  DbRows _products = [];
  DbRows _categories = [];

  String _effectType = 'increase';
  String _priceTarget = 'sale';
  bool _editSale1 = true;
  bool _editSale2 = true;
  bool _editSale3 = true;
  int? _selectedCategoryId;
  String _methodType = 'amount';

  final TextEditingController _amountCtrl = TextEditingController();
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final prods = await DatabaseHelper.instance.queryAllProducts();
    final cats = await DatabaseHelper.instance.queryAllCategories();
    if (!mounted) return;
    setState(() {
      _products = prods;
      _categories = cats;
    });
  }

  String get _inputLabel {
    switch (_methodType) {
      case 'percent':
        return 'النسبة %';
      case 'exchange':
        return 'سعر الصرف';
      default:
        return 'المبلغ';
    }
  }

  double _calculateNewPrice(double current, double val) {
    double result = current;
    if (_methodType == 'amount') {
      result = _effectType == 'increase' ? (current + val) : (current - val);
    } else if (_methodType == 'percent') {
      final factor = val / 100.0;
      result = _effectType == 'increase'
          ? (current * (1.0 + factor))
          : (current * (1.0 - factor));
    } else if (_methodType == 'exchange') {
      if (_effectType == 'increase') {
        result = current * val;
      } else {
        result = val > 0 ? (current / val) : current;
      }
    }
    if (result < 0) result = 0.0;
    return double.parse(result.toStringAsFixed(2));
  }

  Future<void> _onApplyPressed() async {
    final rawVal = _amountCtrl.text.trim();
    final val = double.tryParse(rawVal) ?? 0.0;
    if (val <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('يرجى إدخال $_inputLabel أكبر من الصفر')),
      );
      return;
    }

    if (_priceTarget == 'sale' && !_editSale1 && !_editSale2 && !_editSale3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى تحديد سعر بيع واحد على الأقل (سعر بيع 1 أو 2 أو 3)')),
      );
      return;
    }

    final targetProducts = _products.where((p) {
      if (_selectedCategoryId == null) return true;
      return p['category_id'] == _selectedCategoryId;
    }).toList();

    if (targetProducts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد منتجات ضمن التصنيف المحدد')),
      );
      return;
    }

    final effectLabel = _effectType == 'increase' ? 'بالزيادة' : 'بالنقصان';
    final methodLabel = _methodType == 'amount'
        ? 'مبلغ $val ${widget.currencySymbol}'
        : (_methodType == 'percent' ? 'نسبة $val%' : 'سعر صرف $val');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          title: const Text(
            'تأكيد تعديل الاسعار',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          content: Text(
            'سيتم تعديل أسعار ${targetProducts.length} منتج ($effectLabel) باستخدام ($methodLabel).\n\nهل تريد المتابعة؟',
            style: const TextStyle(fontSize: 15, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF7CB342)),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('تأكيد التعديل'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    setState(() => _applying = true);
    try {
      final db = await DatabaseHelper.instance.database;
      await db.transaction((txn) async {
        for (final prod in targetProducts) {
          final DbRow updates = {};
          if (_priceTarget == 'purchase') {
            final curCost = (prod['purchase_price'] as num?)?.toDouble() ?? 0.0;
            updates['purchase_price'] = _calculateNewPrice(curCost, val);
          } else {
            if (_editSale1) {
              final curS1 = (prod['sale_price'] as num?)?.toDouble() ?? 0.0;
              updates['sale_price'] = _calculateNewPrice(curS1, val);
            }
            if (_editSale2) {
              final curS2 = (prod['wholesale_price'] as num?)?.toDouble() ?? 0.0;
              updates['wholesale_price'] = _calculateNewPrice(curS2, val);
            }
            if (_editSale3) {
              final curS3 = (prod['special_price'] as num?)?.toDouble() ?? 0.0;
              updates['special_price'] = _calculateNewPrice(curS3, val);
            }
          }

          if (updates.isNotEmpty) {
            await txn.update(
              'products',
              updates,
              where: 'id = ?',
              whereArgs: [prod['id']],
            );
          }
        }
      });

      _amountCtrl.clear();
      await _loadData();
      if (!mounted) return;
      setState(() => _applying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم تعديل أسعار ${targetProducts.length} منتج بنجاح')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _applying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حدث خطأ أثناء تحديث الأسعار')),
      );
    }
  }

  Widget _buildCustomRadioOption({
    required String label,
    required bool selected,
    required Color labelColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: const Color(0xFF8E8E93), width: 1.6),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: Center(
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? const Color(0xFF8BC34A) : const Color(0xFFD1D5DB),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.w500,
                color: labelColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSalePriceCheckbox({
    required String label,
    required bool value,
    required bool enabled,
    required ValueChanged<bool> onChanged,
  }) {
    return InkWell(
      onTap: enabled ? () => onChanged(!value) : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: !enabled
                  ? const Color(0xFFE0E0E0)
                  : (value ? const Color(0xFFEC407A) : Colors.white),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: !enabled
                    ? const Color(0xFFBDBDBD)
                    : (value ? const Color(0xFFEC407A) : Colors.black54),
                width: 1.4,
              ),
            ),
            child: value
                ? const Icon(Icons.check, size: 15, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w500,
              color: enabled ? Colors.black87 : Colors.black38,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeading(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4, right: 4),
      child: Align(
        alignment: Alignment.centerRight,
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 16.5,
            fontWeight: FontWeight.w500,
            color: Color(0xFF262626),
          ),
        ),
      ),
    );
  }

  Widget _grayOptionStrip({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: const BoxDecoration(
        color: Color(0xFFEBEBEB),
        border: Border(
          bottom: BorderSide(color: Color(0xFF9E9E9E), width: 1.1),
        ),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isSaleSelected = _priceTarget == 'sale';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        body: SafeArea(
          child: Column(
            children: [
              // 1. الترويسة العلوية: أيقونة التبديل + عنوان "تعديل اسعار المنتجات"
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 14, 10),
                child: Row(
                  children: [
                    const Icon(
                      Icons.swap_horiz_rounded,
                      size: 30,
                      color: Color(0xFF424242),
                    ),
                    const Expanded(
                      child: Text(
                        'تعديل اسعار المنتجات',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'رجوع',
                      icon: const Icon(Icons.arrow_forward_ios, color: Colors.black45, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 2. تاثير على الاسعار (بالزيادة | بالنقصان)
                      _sectionHeading('تاثير على الاسعار'),
                      _grayOptionStrip(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildCustomRadioOption(
                              label: 'بالزيادة',
                              selected: _effectType == 'increase',
                              labelColor: const Color(0xFF7CB342),
                              onTap: () => setState(() => _effectType = 'increase'),
                            ),
                            _buildCustomRadioOption(
                              label: 'بالنقصان',
                              selected: _effectType == 'decrease',
                              labelColor: const Color(0xFFD32F2F),
                              onTap: () => setState(() => _effectType = 'decrease'),
                            ),
                          ],
                        ),
                      ),

                      // 3. تعديل سعر (البيع | الشراء)
                      _sectionHeading('تعديل سعر'),
                      _grayOptionStrip(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildCustomRadioOption(
                              label: 'البيع',
                              selected: _priceTarget == 'sale',
                              labelColor: const Color(0xFF7CB342),
                              onTap: () => setState(() => _priceTarget = 'sale'),
                            ),
                            _buildCustomRadioOption(
                              label: 'الشراء',
                              selected: _priceTarget == 'purchase',
                              labelColor: const Color(0xFFD32F2F),
                              onTap: () => setState(() => _priceTarget = 'purchase'),
                            ),
                          ],
                        ),
                      ),

                      // بطاقة تحديد أسعار البيع (سعر بيع 1 | سعر بيع 2 | سعر بيع 3)
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE0E0E0)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildSalePriceCheckbox(
                              label: 'سعر بيع 1',
                              value: _editSale1,
                              enabled: isSaleSelected,
                              onChanged: (v) => setState(() => _editSale1 = v),
                            ),
                            _buildSalePriceCheckbox(
                              label: 'سعر بيع 2',
                              value: _editSale2,
                              enabled: isSaleSelected,
                              onChanged: (v) => setState(() => _editSale2 = v),
                            ),
                            _buildSalePriceCheckbox(
                              label: 'سعر بيع 3',
                              value: _editSale3,
                              enabled: isSaleSelected,
                              onChanged: (v) => setState(() => _editSale3 = v),
                            ),
                          ],
                        ),
                      ),

                      // 4. تعديل حسب التصنيف
                      _sectionHeading('تعديل حسب التصنيف'),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 4, right: 6),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'التصنيف',
                            style: TextStyle(fontSize: 13.5, color: Color(0xFF424242)),
                          ),
                        ),
                      ),
                      _grayOptionStrip(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int?>(
                            value: _selectedCategoryId,
                            isExpanded: true,
                            isDense: true,
                            icon: const Icon(Icons.arrow_drop_down, color: Colors.black54),
                            items: [
                              const DropdownMenuItem<int?>(
                                value: null,
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    'الكل',
                                    style: TextStyle(fontSize: 18, color: Colors.black87),
                                  ),
                                ),
                              ),
                              ..._categories.map(
                                (c) => DropdownMenuItem<int?>(
                                  value: c['id'] as int,
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: Text(
                                      (c['name'] ?? '').toString(),
                                      style: const TextStyle(fontSize: 17, color: Colors.black87),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            onChanged: (v) => setState(() => _selectedCategoryId = v),
                          ),
                        ),
                      ),

                      // 5. الطريقه (مبلغ | نسبه% | سعر صرف)
                      _sectionHeading('الطريقه'),
                      _grayOptionStrip(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildCustomRadioOption(
                              label: 'مبلغ',
                              selected: _methodType == 'amount',
                              labelColor: Colors.black87,
                              onTap: () => setState(() => _methodType = 'amount'),
                            ),
                            _buildCustomRadioOption(
                              label: 'نسبه%',
                              selected: _methodType == 'percent',
                              labelColor: Colors.black87,
                              onTap: () => setState(() => _methodType = 'percent'),
                            ),
                            _buildCustomRadioOption(
                              label: 'سعر صرف',
                              selected: _methodType == 'exchange',
                              labelColor: Colors.black87,
                              onTap: () => setState(() => _methodType = 'exchange'),
                            ),
                          ],
                        ),
                      ),

                      // 6. حقل إدخال المبلغ / النسبة / سعر الصرف
                      const SizedBox(height: 18),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 90,
                              child: Text(
                                _inputLabel,
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1F2937),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _amountCtrl,
                                textAlign: TextAlign.center,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFD32F2F),
                                ),
                                decoration: InputDecoration(
                                  hintText: '0',
                                  hintStyle: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFD32F2F),
                                  ),
                                  filled: true,
                                  fillColor: const Color(0xFFE6EE9C),
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(color: Color(0xFF9E9E9E), width: 1.1),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(color: Color(0xFF7CB342), width: 1.8),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 7. زر (تعديل الاسعار) في أسفل الشاشة
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 8, 32, 18),
                child: SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD6D6D6),
                      foregroundColor: const Color(0xFF262626),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                    onPressed: _applying ? null : _onApplyPressed,
                    child: Text(
                      _applying ? 'جاري التعديل...' : 'تعديل الاسعار',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
// =============================================================================
// القسم (9 من 10): شاشة العملاء والموردين (ContactsScreen) + الصندوق (CashboxScreen)
// =============================================================================

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  DbRows _allContacts = [];
  String _currencySymbol = 'ريال';
  String _search = '';
  bool _onlyWithBalance = false;
  bool _loading = true;

  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && mounted) {
        setState(() {});
      }
    });
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  String get _currentType => _tabController.index == 0 ? 'customer' : 'supplier';

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final settings = await DatabaseHelper.instance.getSettingsMap();
    final contacts = await DatabaseHelper.instance.queryContacts();
    if (!mounted) return;
    setState(() {
      _currencySymbol = (settings['currency_symbol'] ?? 'ريال').trim();
      _allContacts = contacts;
      _loading = false;
    });
  }

  DbRows get _filteredContacts {
    final q = _search.trim().toLowerCase();
    final targetType = _currentType;
    return _allContacts.where((c) {
      if ((c['type'] ?? 'customer').toString() != targetType) return false;
      final bal = (c['balance'] as num?)?.toDouble() ?? 0.0;
      if (_onlyWithBalance && bal <= 0) return false;
      if (q.isEmpty) return true;
      final name = (c['name'] ?? '').toString().toLowerCase();
      final phone = (c['phone'] ?? '').toString().toLowerCase();
      final address = (c['address'] ?? '').toString().toLowerCase();
      return name.contains(q) || phone.contains(q) || address.contains(q);
    }).toList();
  }

  double _totalDebtForType(String type) {
    double sum = 0.0;
    for (final c in _allContacts) {
      if ((c['type'] ?? '').toString() == type) {
        final bal = (c['balance'] as num?)?.toDouble() ?? 0.0;
        if (bal > 0) sum += bal;
      }
    }
    return sum;
  }

  Future<void> _showAddOrEditContactDialog({DbRow? existing}) async {
    final isEdit = existing != null;
    final isCustomer = _currentType == 'customer';
    final nameCtrl = TextEditingController(
      text: isEdit ? (existing['name'] ?? '').toString() : '',
    );
    final phoneCtrl = TextEditingController(
      text: isEdit ? (existing['phone'] ?? '').toString() : '',
    );
    final addressCtrl = TextEditingController(
      text: isEdit ? (existing['address'] ?? '').toString() : '',
    );
    final balanceCtrl = TextEditingController(
      text: isEdit
          ? ((existing['balance'] as num?)?.toDouble() ?? 0.0).toString()
          : '0',
    );
    final notesCtrl = TextEditingController(
      text: isEdit ? (existing['notes'] ?? '').toString() : '',
    );

    await showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          title: Text(
            isEdit
                ? (isCustomer ? 'تعديل بيانات العميل' : 'تعديل بيانات المورد')
                : (isCustomer ? 'إضافة عميل جديد' : 'إضافة مورد جديد'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16.5),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: !isEdit,
                  decoration: InputDecoration(
                    labelText: isCustomer ? 'اسم العميل *' : 'اسم المورد *',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'رقم الهاتف',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: addressCtrl,
                  decoration: const InputDecoration(
                    labelText: 'العنوان',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: balanceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: InputDecoration(
                    labelText: isCustomer
                        ? 'الرصيد الافتتاحي / الدين عليه ($_currencySymbol)'
                        : 'الرصيد الافتتاحي / المستحق له ($_currencySymbol)',
                    border: const OutlineInputBorder(),
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
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1545B5)),
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('يرجى إدخال الاسم أولاً')),
                  );
                  return;
                }
                final bal = double.tryParse(balanceCtrl.text.trim()) ?? 0.0;
                if (isEdit) {
                  final db = await DatabaseHelper.instance.database;
                  await db.update(
                    'contacts',
                    {
                      'name': name,
                      'phone': phoneCtrl.text.trim(),
                      'address': addressCtrl.text.trim(),
                      'balance': bal,
                      'notes': notesCtrl.text.trim(),
                    },
                    where: 'id = ?',
                    whereArgs: [existing['id']],
                  );
                } else {
                  await DatabaseHelper.instance.insertContact({
                    'name': name,
                    'phone': phoneCtrl.text.trim(),
                    'address': addressCtrl.text.trim(),
                    'type': _currentType,
                    'balance': bal,
                    'notes': notesCtrl.text.trim(),
                  });
                }
                if (ctx.mounted) Navigator.of(ctx).pop();
                await _loadData();
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPaymentVoucherDialog(DbRow contact) async {
    final int cid = contact['id'] as int;
    final String cName = (contact['name'] ?? '').toString();
    final String cType = (contact['type'] ?? 'customer').toString();
    final bool isCustomer = cType == 'customer';
    final double currentBal = (contact['balance'] as num?)?.toDouble() ?? 0.0;

    final amountCtrl = TextEditingController(
      text: currentBal > 0 ? currentBal.toStringAsFixed(2) : '',
    );
    final notesCtrl = TextEditingController();
    bool printVoucherAfter = true;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            title: Text(
              isCustomer ? 'سند قبض من عميل' : 'سند صرف لمورد',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'الاسم: $cName',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'الرصيد الحالي: ${currentBal.toStringAsFixed(2)} $_currencySymbol',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                            color: currentBal > 0 ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountCtrl,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'المبلغ المدفوع ($_currencySymbol) *',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notesCtrl,
                    decoration: const InputDecoration(
                      labelText: 'البيان / ملاحظات السند (اختياري)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: printVoucherAfter,
                    onChanged: (v) => setDialogState(() => printVoucherAfter = v ?? true),
                    title: const Text('طباعة إيصال السند حرارياً', style: TextStyle(fontSize: 13.5)),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('إلغاء'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: isCustomer ? const Color(0xFF16A34A) : const Color(0xFF1545B5),
                ),
                onPressed: () async {
                  final amt = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                  if (amt <= 0) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('يرجى إدخال مبلغ صحيح أكبر من الصفر')),
                    );
                    return;
                  }
                  final notes = notesCtrl.text.trim();
                  await DatabaseHelper.instance.recordContactPayment(
                    contactId: cid,
                    contactType: cType,
                    amount: amt,
                    notes: notes,
                  );

                  final updatedBalance = currentBal - amt;
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  await _loadData();

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تم تسجيل السند وتحديث الرصيد والصندوق بنجاح')),
                    );
                  }
                  if (printVoucherAfter) {
                    await ThermalPrintService.printVoucher(
                      title: isCustomer ? 'سند قبض نقدي' : 'سند صرف نقدي',
                      partyLabel: isCustomer ? 'استلمنا من العميل' : 'صرفنا إلى المورد',
                      partyName: cName,
                      amount: amt,
                      remainingBalance: updatedBalance,
                      notes: notes,
                    );
                  }
                },
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('حفظ السند'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showContactStatementSheet(DbRow contact) async {
    final int cid = contact['id'] as int;
    final String cName = (contact['name'] ?? '').toString();
    final String cType = (contact['type'] ?? 'customer').toString();
    final bool isCustomer = cType == 'customer';
    final double balance = (contact['balance'] as num?)?.toDouble() ?? 0.0;

    final db = await DatabaseHelper.instance.database;
    final invoices = await db.query(
      'invoices',
      where: 'contact_id = ?',
      whereArgs: [cid],
      orderBy: 'id DESC',
    );
    final payments = await db.query(
      'cash_transactions',
      where: 'contact_id = ? AND category IN (?, ?)',
      whereArgs: [cid, 'سند قبض عميل', 'سند صرف مورد'],
      orderBy: 'id DESC',
    );

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          maxChildSize: 0.92,
          builder: (_, scrollCtrl) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'كشف حساب: $cName',
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'الرصيد المتبقي: ${balance.toStringAsFixed(2)} $_currencySymbol',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                              color: balance > 0 ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                            ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _showPaymentVoucherDialog(contact);
                      },
                      icon: const Icon(Icons.payments_outlined, size: 18),
                      label: Text(isCustomer ? 'سند قبض' : 'سند صرف'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.all(12),
                  children: [
                    const Text(
                      'الفواتير المسجلة:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: Color(0xFF1545B5)),
                    ),
                    const SizedBox(height: 6),
                    if (invoices.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('لا توجد فواتير مسجلة لهذا الحساب', style: TextStyle(color: Colors.black54)),
                      )
                    else
                      ...invoices.map((inv) {
                        final total = (inv['total'] as num?)?.toDouble() ?? 0.0;
                        final rem = (inv['remaining'] as num?)?.toDouble() ?? 0.0;
                        final dt = (inv['created_at'] ?? '').toString().replaceAll('T', ' ').split('.').first;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          child: ListTile(
                            dense: true,
                            title: Text('فاتورة ${inv['invoice_number']} • الإجمالي: ${total.toStringAsFixed(2)}'),
                            subtitle: Text('المتبقي الآجل: ${rem.toStringAsFixed(2)} $_currencySymbol • $dt'),
                            trailing: IconButton(
                              icon: const Icon(Icons.print_outlined, size: 20),
                              onPressed: () => ThermalPrintService.printInvoiceById(inv['id'] as int),
                            ),
                          ),
                        );
                      }),
                    const SizedBox(height: 12),
                    const Text(
                      'السندات والدفعات النقدية:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: Color(0xFF16A34A)),
                    ),
                    const SizedBox(height: 6),
                    if (payments.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('لا توجد سندات قبض أو صرف مسجلة', style: TextStyle(color: Colors.black54)),
                      )
                    else
                      ...payments.map((pay) {
                        final amt = (pay['amount'] as num?)?.toDouble() ?? 0.0;
                        final dt = (pay['created_at'] ?? '').toString().replaceAll('T', ' ').split('.').first;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          child: ListTile(
                            dense: true,
                            leading: const Icon(Icons.receipt_outlined, color: Color(0xFF16A34A)),
                            title: Text('${pay['category']}: ${amt.toStringAsFixed(2)} $_currencySymbol'),
                            subtitle: Text('${pay['description'] ?? ''}\n$dt'),
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _callPhone(String phone) async {
    final clean = phone.trim();
    if (clean.isEmpty) return;
    final uri = Uri.parse('tel:$clean');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _filteredContacts;
    final isCustomerTab = _tabController.index == 0;
    final totalDebt = _totalDebtForType(_currentType);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F4F6),
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          title: const Text(
            'العملاء والموردين',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          actions: [
            IconButton(
              tooltip: 'تصدير كشف الحسابات Excel',
              icon: const Icon(Icons.file_download_outlined),
              onPressed: () async {
                final StrMatrix rows = [];
                for (final c in list) {
                  rows.add([
                    (c['name'] ?? '').toString(),
                    (c['phone'] ?? '').toString(),
                    (c['address'] ?? '').toString(),
                    ((c['balance'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2),
                  ]);
                }
                await CsvExportService.writeCsvAndShare(
                  fileNamePrefix: isCustomerTab ? 'customers_balances' : 'suppliers_balances',
                  headers: ['الاسم', 'الهاتف', 'العنوان', 'الرصيد المتبقي'],
                  rows: rows,
                  shareSubject: isCustomerTab ? 'كشف أرصدة العملاء' : 'كشف أرصدة الموردين',
                );
              },
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            labelColor: const Color(0xFF1545B5),
            indicatorColor: const Color(0xFF1545B5),
            tabs: const [
              Tab(icon: Icon(Icons.people_outline), text: 'العملاء'),
              Tab(icon: Icon(Icons.local_shipping_outlined), text: 'الموردون'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: const Color(0xFF1545B5),
          foregroundColor: Colors.white,
          onPressed: () => _showAddOrEditContactDialog(),
          icon: const Icon(Icons.person_add_alt_1),
          label: Text(isCustomerTab ? 'إضافة عميل' : 'إضافة مورد'),
        ),
        body: Column(
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(
                children: [
                  TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _search = v),
                    decoration: InputDecoration(
                      hintText: isCustomerTab
                          ? 'ابحث باسم العميل أو رقم الهاتف...'
                          : 'ابحث باسم المورد أو رقم الهاتف...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _search.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _search = '');
                              },
                            )
                          : null,
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFFF3F4F6),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      FilterChip(
                        label: Text(
                          isCustomerTab ? 'المدينون فقط' : 'المستحق لهم فقط',
                          style: const TextStyle(fontSize: 12),
                        ),
                        selected: _onlyWithBalance,
                        onSelected: (v) => setState(() => _onlyWithBalance = v),
                      ),
                      Text(
                        '${isCustomerTab ? 'إجمالي ديون العملاء' : 'إجمالي مستحقات الموردين'}: '
                        '${totalDebt.toStringAsFixed(2)} $_currencySymbol',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : list.isEmpty
                      ? Center(
                          child: Text(
                            isCustomerTab ? 'لا يوجد عملاء مسجلون' : 'لا يوجد موردون مسجلون',
                            style: const TextStyle(color: Colors.black54),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(10, 10, 10, 80),
                          itemCount: list.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, idx) {
                            final c = list[idx];
                            final bal = (c['balance'] as num?)?.toDouble() ?? 0.0;
                            final phone = (c['phone'] ?? '').toString();
                            final address = (c['address'] ?? '').toString();

                            return Card(
                              color: Colors.white,
                              surfaceTintColor: Colors.white,
                              margin: EdgeInsets.zero,
                              child: ListTile(
                                onTap: () => _showContactStatementSheet(c),
                                leading: CircleAvatar(
                                  backgroundColor: isCustomerTab
                                      ? const Color(0xFFDBEAFE)
                                      : const Color(0xFFEDE9FE),
                                  child: Icon(
                                    isCustomerTab ? Icons.person : Icons.storefront,
                                    color: isCustomerTab
                                        ? const Color(0xFF1545B5)
                                        : const Color(0xFF7C3AED),
                                  ),
                                ),
                                title: Text(
                                  (c['name'] ?? '').toString(),
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (phone.isNotEmpty || address.isNotEmpty)
                                      Text(
                                        [if (phone.isNotEmpty) phone, if (address.isNotEmpty) address]
                                            .join(' • '),
                                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                                      ),
                                    const SizedBox(height: 3),
                                    Text(
                                      'الرصيد: ${bal.toStringAsFixed(2)} $_currencySymbol',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: bal > 0
                                            ? const Color(0xFFDC2626)
                                            : const Color(0xFF16A34A),
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (phone.isNotEmpty)
                                      IconButton(
                                        tooltip: 'اتصال',
                                        icon: const Icon(Icons.call_outlined, color: Color(0xFF16A34A), size: 20),
                                        onPressed: () => _callPhone(phone),
                                      ),
                                    IconButton(
                                      tooltip: isCustomerTab ? 'سند قبض' : 'سند صرف',
                                      icon: const Icon(Icons.payments_outlined, color: Color(0xFF1545B5)),
                                      onPressed: () => _showPaymentVoucherDialog(c),
                                    ),
                                    IconButton(
                                      tooltip: 'تعديل',
                                      icon: const Icon(Icons.edit_outlined, color: Colors.black54, size: 20),
                                      onPressed: () => _showAddOrEditContactDialog(existing: c),
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

// =============================================================================
// شاشة الصندوق والمصاريف (CashboxScreen)
// =============================================================================

class CashboxScreen extends StatefulWidget {
  const CashboxScreen({super.key});

  @override
  State<CashboxScreen> createState() => _CashboxScreenState();
}

class _CashboxScreenState extends State<CashboxScreen> {
  DbRows _transactions = [];
  String _currencySymbol = 'ريال';
  double _cashIn = 0.0;
  double _cashOut = 0.0;
  double _cashBalance = 0.0;
  String _filterType = 'all'; // all | in | out | expense
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final settings = await DatabaseHelper.instance.getSettingsMap();
    final txs = await DatabaseHelper.instance.queryCashTransactions();
    final summary = await DatabaseHelper.instance.getFinancialSummary();

    if (!mounted) return;
    setState(() {
      _currencySymbol = (settings['currency_symbol'] ?? 'ريال').trim();
      _transactions = txs;
      _cashIn = summary['cashIn'] ?? 0.0;
      _cashOut = summary['cashOut'] ?? 0.0;
      _cashBalance = summary['cashBalance'] ?? 0.0;
      _loading = false;
    });
  }

  DbRows get _filteredTransactions {
    if (_filterType == 'all') return _transactions;
    return _transactions.where((t) => (t['type'] ?? '').toString() == _filterType).toList();
  }

  Future<void> _showNewCashTransactionDialog({required String initialType}) async {
    String txType = initialType; // in | expense | out
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String selectedCategory = txType == 'in'
        ? 'إيداع رأس مال / إيراد'
        : (txType == 'expense' ? 'إيجار / كهرباء / إنترنت' : 'مسحوبات شخصية');

    final expenseCategories = [
      'إيجار / كهرباء / إنترنت',
      'رواتب وأجور',
      'نقل ومواصلات',
      'قرطاسية ومستلزمات',
      'صيانة وتشغيل',
      'مصروفات نثرية أخرى',
    ];
    final inCategories = [
      'إيداع رأس مال / إيراد',
      'إيرادات خدمات إضافية',
      'استرداد مبلغ',
    ];
    final outCategories = [
      'مسحوبات شخصية',
      'سداد التزامات',
      'صرف نقدي عام',
    ];

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final cats = txType == 'in'
              ? inCategories
              : (txType == 'expense' ? expenseCategories : outCategories);
          if (!cats.contains(selectedCategory)) {
            selectedCategory = cats.first;
          }

          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              title: const Text(
                'تسجيل حركة مالية في الصندوق',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.5),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'in', label: Text('قبض / إيداع')),
                        ButtonSegment(value: 'expense', label: Text('مصروف')),
                        ButtonSegment(value: 'out', label: Text('صرف')),
                      ],
                      selected: {txType},
                      onSelectionChanged: (sel) {
                        setDialogState(() {
                          txType = sel.first;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedCategory,
                      decoration: const InputDecoration(
                        labelText: 'البند / التصنيف',
                        border: OutlineInputBorder(),
                      ),
                      items: cats
                          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) => setDialogState(() => selectedCategory = v ?? cats.first),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: amountCtrl,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'المبلغ ($_currencySymbol) *',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: descCtrl,
                      decoration: const InputDecoration(
                        labelText: 'البيان / التفاصيل (اختياري)',
                        border: OutlineInputBorder(),
                      ),
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
                  style: FilledButton.styleFrom(
                    backgroundColor: txType == 'in'
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFDC2626),
                  ),
                  onPressed: () async {
                    final amt = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                    if (amt <= 0) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('أدخل مبلغاً صحيحاً أكبر من الصفر')),
                      );
                      return;
                    }
                    await DatabaseHelper.instance.insertCashTransaction({
                      'type': txType,
                      'amount': amt,
                      'category': selectedCategory,
                      'description': descCtrl.text.trim().isEmpty
                          ? selectedCategory
                          : descCtrl.text.trim(),
                    });
                    if (ctx.mounted) Navigator.of(ctx).pop();
                    await _loadData();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم تسجيل الحركة المالية بنجاح')),
                      );
                    }
                  },
                  child: const Text('حفظ الحركة'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _filteredTransactions;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F4F6),
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          title: const Text(
            'الصندوق والمصاريف',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          actions: [
            IconButton(
              tooltip: 'تصدير حركات الصندوق Excel',
              icon: const Icon(Icons.file_download_outlined),
              onPressed: () async {
                final StrMatrix rows = [];
                for (final t in list) {
                  final typeStr = (t['type'] ?? '').toString();
                  final label = typeStr == 'in'
                      ? 'وارد'
                      : (typeStr == 'expense' ? 'مصروف' : 'صادر');
                  rows.add([
                    label,
                    (t['category'] ?? '').toString(),
                    (t['description'] ?? '').toString(),
                    ((t['amount'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2),
                    (t['created_at'] ?? '').toString().replaceAll('T', ' ').split('.').first,
                  ]);
                }
                await CsvExportService.writeCsvAndShare(
                  fileNamePrefix: 'cashbox_statement',
                  headers: ['النوع', 'البند', 'البيان', 'المبلغ', 'التاريخ'],
                  rows: rows,
                  shareSubject: 'كشف حركة الصندوق والمصاريف',
                );
              },
            ),
          ],
        ),
        body: Column(
          children: [
            // بطاقة ملخص رصيد الصندوق
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1545B5),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'الرصيد النقدي المتوفر في الصندوق',
                          style: TextStyle(color: Color(0xFFDBEAFE), fontSize: 13),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${_cashBalance.toStringAsFixed(2)} $_currencySymbol',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Text(
                              'إجمالي الوارد: ${_cashIn.toStringAsFixed(1)}',
                              style: const TextStyle(color: Color(0xFF86EFAC), fontWeight: FontWeight.bold, fontSize: 12.5),
                            ),
                            Text(
                              'إجمالي الصادر: ${_cashOut.toStringAsFixed(1)}',
                              style: const TextStyle(color: Color(0xFFFCA5A5), fontWeight: FontWeight.bold, fontSize: 12.5),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
                          onPressed: () => _showNewCashTransactionDialog(initialType: 'in'),
                          icon: const Icon(Icons.add_circle_outline, size: 19),
                          label: const Text('سند قبض / إيداع'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
                          onPressed: () => _showNewCashTransactionDialog(initialType: 'expense'),
                          icon: const Icon(Icons.remove_circle_outline, size: 19),
                          label: const Text('تسجيل مصروف'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ChoiceChip(
                          label: const Text('الكل'),
                          selected: _filterType == 'all',
                          onSelected: (_) => setState(() => _filterType = 'all'),
                        ),
                        const SizedBox(width: 6),
                        ChoiceChip(
                          label: const Text('الوارد فقط'),
                          selected: _filterType == 'in',
                          onSelected: (_) => setState(() => _filterType = 'in'),
                        ),
                        const SizedBox(width: 6),
                        ChoiceChip(
                          label: const Text('المصروفات'),
                          selected: _filterType == 'expense',
                          onSelected: (_) => setState(() => _filterType = 'expense'),
                        ),
                        const SizedBox(width: 6),
                        ChoiceChip(
                          label: const Text('الصادر والمشتريات'),
                          selected: _filterType == 'out',
                          onSelected: (_) => setState(() => _filterType = 'out'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // قائمة الحركات المالية
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : list.isEmpty
                      ? const Center(
                          child: Text(
                            'لا توجد حركات مالية مسجلة في الصندوق',
                            style: TextStyle(color: Colors.black54),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(10),
                          itemCount: list.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 6),
                          itemBuilder: (_, idx) {
                            final tx = list[idx];
                            final typeStr = (tx['type'] ?? '').toString();
                            final isIn = typeStr == 'in';
                            final amt = (tx['amount'] as num?)?.toDouble() ?? 0.0;
                            final dt = (tx['created_at'] ?? '').toString().replaceAll('T', ' ').split('.').first;

                            return Card(
                              color: Colors.white,
                              surfaceTintColor: Colors.white,
                              margin: EdgeInsets.zero,
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: isIn
                                      ? const Color(0xFFDCFCE7)
                                      : const Color(0xFFFEE2E2),
                                  child: Icon(
                                    isIn ? Icons.arrow_downward : Icons.arrow_upward,
                                    color: isIn ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                                  ),
                                ),
                                title: Text(
                                  (tx['category'] ?? '').toString(),
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                                ),
                                subtitle: Text(
                                  '${tx['description'] ?? ''}\n$dt',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                trailing: Text(
                                  '${isIn ? '+' : '-'}${amt.toStringAsFixed(2)} $_currencySymbol',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: isIn ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                                  ),
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
// =============================================================================
// القسم (10 من 10): التقارير والأرباح + النسخ الاحتياطي + المساعد الذكي (الروبوت)
// =============================================================================

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String _currencySymbol = 'ريال';
  String _period = 'today'; // today | month | all | custom
  DateTime _customDate = DateTime.now();

  NumMap _summary = {};
  DbRows _topProducts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  String? get _activeDatePrefix {
    final now = DateTime.now();
    if (_period == 'today') {
      return now.toIso8601String().split('T').first;
    }
    if (_period == 'month') {
      final y = now.year.toString().padLeft(4, '0');
      final m = now.month.toString().padLeft(2, '0');
      return '$y-$m';
    }
    if (_period == 'custom') {
      final y = _customDate.year.toString().padLeft(4, '0');
      final m = _customDate.month.toString().padLeft(2, '0');
      final d = _customDate.day.toString().padLeft(2, '0');
      return '$y-$m-$d';
    }
    return null;
  }

  String get _periodTitle {
    switch (_period) {
      case 'today':
        return 'تقرير اليوم (${_activeDatePrefix ?? ''})';
      case 'month':
        return 'تقرير الشهر الحالي (${_activeDatePrefix ?? ''})';
      case 'custom':
        return 'تقرير تاريخ (${_activeDatePrefix ?? ''})';
      default:
        return 'التقرير العام الشامل';
    }
  }

  Future<void> _loadReport() async {
    setState(() => _loading = true);
    final settings = await DatabaseHelper.instance.getSettingsMap();
    final prefix = _activeDatePrefix;
    final summary = await DatabaseHelper.instance.getFinancialSummary(
      datePrefix: prefix,
    );

    final db = await DatabaseHelper.instance.database;
    final topRows = prefix != null
        ? await db.rawQuery('''
            SELECT ii.product_name,
                   COALESCE(SUM(ii.quantity), 0) AS total_qty,
                   COALESCE(SUM(ii.total), 0) AS total_sales,
                   COALESCE(SUM((ii.unit_price - ii.cost_price) * ii.quantity), 0) AS total_profit
            FROM invoice_items ii
            INNER JOIN invoices inv ON inv.id = ii.invoice_id
            WHERE inv.type = 'sale' AND inv.created_at LIKE ?
            GROUP BY ii.product_name
            ORDER BY total_qty DESC
            LIMIT 15
          ''', ['$prefix%'])
        : await db.rawQuery('''
            SELECT ii.product_name,
                   COALESCE(SUM(ii.quantity), 0) AS total_qty,
                   COALESCE(SUM(ii.total), 0) AS total_sales,
                   COALESCE(SUM((ii.unit_price - ii.cost_price) * ii.quantity), 0) AS total_profit
            FROM invoice_items ii
            INNER JOIN invoices inv ON inv.id = ii.invoice_id
            WHERE inv.type = 'sale'
            GROUP BY ii.product_name
            ORDER BY total_qty DESC
            LIMIT 15
          ''');

    if (!mounted) return;
    setState(() {
      _currencySymbol = (settings['currency_symbol'] ?? 'ريال').trim();
      _summary = summary;
      _topProducts = topRows;
      _loading = false;
    });
  }

  Future<void> _pickCustomReportDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _customDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
    );
    if (picked != null && mounted) {
      setState(() {
        _customDate = picked;
        _period = 'custom';
      });
      await _loadReport();
    }
  }

  Future<void> _printFinancialReportPdf() async {
    final settings = await DatabaseHelper.instance.getSettingsMap();
    final storeName = (settings['store_name'] ?? 'نبراس SofT').toString();
    final sales = _summary['salesTotal'] ?? 0.0;
    final purchases = _summary['purchasesTotal'] ?? 0.0;
    final grossProfit = _summary['grossProfit'] ?? 0.0;
    final expenses = _summary['expensesTotal'] ?? 0.0;
    final netProfit = _summary['netProfit'] ?? 0.0;
    final cashBal = _summary['cashBalance'] ?? 0.0;
    final invCost = _summary['inventoryCostValue'] ?? 0.0;
    final custDebt = _summary['customersDebt'] ?? 0.0;
    final suppDebt = _summary['suppliersDebt'] ?? 0.0;

    final topHtml = StringBuffer();
    for (int i = 0; i < _topProducts.length; i++) {
      final p = _topProducts[i];
      final qty = (p['total_qty'] as num?)?.toDouble() ?? 0.0;
      final tSales = (p['total_sales'] as num?)?.toDouble() ?? 0.0;
      final tProfit = (p['total_profit'] as num?)?.toDouble() ?? 0.0;
      topHtml.writeln('''
        <tr>
          <td>${i + 1}</td>
          <td>${p['product_name'] ?? ''}</td>
          <td>$qty</td>
          <td>${tSales.toStringAsFixed(2)}</td>
          <td>${tProfit.toStringAsFixed(2)}</td>
        </tr>
      ''');
    }

    final html = '''
    <!DOCTYPE html>
    <html dir="rtl" lang="ar">
    <head>
      <meta charset="UTF-8">
      <style>
        body { font-family: sans-serif; direction: rtl; padding: 16px; }
        h2, h3, p { text-align: center; margin: 4px 0; }
        table { width: 100%; border-collapse: collapse; margin-top: 12px; font-size: 12.5px; }
        th, td { border: 1px solid #888; padding: 7px; text-align: center; }
        th { background-color: #e5e7eb; }
        .right { text-align: right; font-weight: bold; }
      </style>
    </head>
    <body>
      <h2>$storeName</h2>
      <h3>$_periodTitle</h3>
      <table>
        <tbody>
          <tr><td class="right">إجمالي المبيعات</td><td>${sales.toStringAsFixed(2)} $_currencySymbol</td></tr>
          <tr><td class="right">إجمالي المشتريات</td><td>${purchases.toStringAsFixed(2)} $_currencySymbol</td></tr>
          <tr><td class="right">مجمل ربح المبيعات</td><td>${grossProfit.toStringAsFixed(2)} $_currencySymbol</td></tr>
          <tr><td class="right">إجمالي المصروفات</td><td>${expenses.toStringAsFixed(2)} $_currencySymbol</td></tr>
          <tr><td class="right">صافي الربح</td><td><strong>${netProfit.toStringAsFixed(2)} $_currencySymbol</strong></td></tr>
          <tr><td class="right">الرصيد النقدي في الصندوق</td><td>${cashBal.toStringAsFixed(2)} $_currencySymbol</td></tr>
          <tr><td class="right">قيمة البضاعة بالمخزن (بالتكلفة)</td><td>${invCost.toStringAsFixed(2)} $_currencySymbol</td></tr>
          <tr><td class="right">إجمالي الديون التي على العملاء</td><td>${custDebt.toStringAsFixed(2)} $_currencySymbol</td></tr>
          <tr><td class="right">إجمالي المستحقات للموردين</td><td>${suppDebt.toStringAsFixed(2)} $_currencySymbol</td></tr>
        </tbody>
      </table>

      ${_topProducts.isNotEmpty ? '''
      <h3 style="margin-top:18px;">الأصناف الأكثر مبيعاً</h3>
      <table>
        <thead>
          <tr>
            <th>#</th>
            <th>الصنف</th>
            <th>الكمية المباعة</th>
            <th>إجمالي المبيعات</th>
            <th>الربح</th>
          </tr>
        </thead>
        <tbody>$topHtml</tbody>
      </table>
      ''' : ''}
    </body>
    </html>
    ''';

    await Printing.layoutPdf(
      onLayout: (format) => Printing.convertHtml(format: format, html: html),
    );
  }

  Future<void> _exportReportCsv() async {
    final rows = StrMatrix.from([
      ['الفترة', _periodTitle],
      ['إجمالي المبيعات', (_summary['salesTotal'] ?? 0.0).toStringAsFixed(2)],
      ['إجمالي المشتريات', (_summary['purchasesTotal'] ?? 0.0).toStringAsFixed(2)],
      ['مجمل ربح المبيعات', (_summary['grossProfit'] ?? 0.0).toStringAsFixed(2)],
      ['إجمالي المصروفات', (_summary['expensesTotal'] ?? 0.0).toStringAsFixed(2)],
      ['صافي الربح', (_summary['netProfit'] ?? 0.0).toStringAsFixed(2)],
      ['رصيد الصندوق الحالي', (_summary['cashBalance'] ?? 0.0).toStringAsFixed(2)],
      ['قيمة المخزون بالتكلفة', (_summary['inventoryCostValue'] ?? 0.0).toStringAsFixed(2)],
      ['ديون العملاء', (_summary['customersDebt'] ?? 0.0).toStringAsFixed(2)],
      ['مستحقات الموردين', (_summary['suppliersDebt'] ?? 0.0).toStringAsFixed(2)],
    ]);

    await CsvExportService.writeCsvAndShare(
      fileNamePrefix: 'financial_report',
      headers: ['البند', 'القيمة ($_currencySymbol)'],
      rows: rows,
      shareSubject: _periodTitle,
    );
  }

  Widget _buildKpiTile({
    required String label,
    required double amount,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF4B5563),
                  ),
                ),
              ),
              Icon(icon, size: 19, color: color),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${amount.toStringAsFixed(2)} $_currencySymbol',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final salesTotal = _summary['salesTotal'] ?? 0.0;
    final purchasesTotal = _summary['purchasesTotal'] ?? 0.0;
    final grossProfit = _summary['grossProfit'] ?? 0.0;
    final expensesTotal = _summary['expensesTotal'] ?? 0.0;
    final netProfit = _summary['netProfit'] ?? 0.0;
    final cashBalance = _summary['cashBalance'] ?? 0.0;
    final invCost = _summary['inventoryCostValue'] ?? 0.0;
    final invSale = _summary['inventorySaleValue'] ?? 0.0;
    final customersDebt = _summary['customersDebt'] ?? 0.0;
    final suppliersDebt = _summary['suppliersDebt'] ?? 0.0;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F4F6),
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          title: const Text(
            'التقارير والأرباح',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          actions: [
            IconButton(
              tooltip: 'تصدير Excel',
              icon: const Icon(Icons.table_view_outlined),
              onPressed: _exportReportCsv,
            ),
            IconButton(
              tooltip: 'طباعة التقرير PDF',
              icon: const Icon(Icons.print_outlined, color: Color(0xFF1545B5)),
              onPressed: _printFinancialReportPdf,
            ),
          ],
        ),
        body: Column(
          children: [
            // شريط تحديد الفترة الزمنية
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChoiceChip(
                      label: const Text('اليوم'),
                      selected: _period == 'today',
                      onSelected: (_) {
                        setState(() => _period = 'today');
                        _loadReport();
                      },
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: const Text('هذا الشهر'),
                      selected: _period == 'month',
                      onSelected: (_) {
                        setState(() => _period = 'month');
                        _loadReport();
                      },
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: const Text('الكل'),
                      selected: _period == 'all',
                      onSelected: (_) {
                        setState(() => _period = 'all');
                        _loadReport();
                      },
                    ),
                    const SizedBox(width: 6),
                    ActionChip(
                      avatar: const Icon(Icons.calendar_today, size: 15),
                      label: Text(
                        _period == 'custom' ? (_activeDatePrefix ?? 'تاريخ') : 'تاريخ محدد',
                      ),
                      onPressed: _pickCustomReportDate,
                    ),
                  ],
                ),
              ),
            ),

            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        // بطاقة صافي الربح البارزة
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: netProfit >= 0
                                ? const Color(0xFF15803D)
                                : const Color(0xFFB91C1C),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            children: [
                              Text(
                                'صافي الربح ($_periodTitle)',
                                style: const TextStyle(color: Colors.white70, fontSize: 13),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${netProfit.toStringAsFixed(2)} $_currencySymbol',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // شبكة المؤشرات المالية
                        GridView.count(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: 2,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 2.05,
                          children: [
                            _buildKpiTile(
                              label: 'إجمالي المبيعات',
                              amount: salesTotal,
                              color: const Color(0xFF16A34A),
                              icon: Icons.point_of_sale,
                            ),
                            _buildKpiTile(
                              label: 'إجمالي المشتريات',
                              amount: purchasesTotal,
                              color: const Color(0xFF2563EB),
                              icon: Icons.shopping_bag_outlined,
                            ),
                            _buildKpiTile(
                              label: 'مجمل ربح المبيعات',
                              amount: grossProfit,
                              color: const Color(0xFF0D9488),
                              icon: Icons.trending_up,
                            ),
                            _buildKpiTile(
                              label: 'المصروفات',
                              amount: expensesTotal,
                              color: const Color(0xFFDC2626),
                              icon: Icons.money_off,
                            ),
                            _buildKpiTile(
                              label: 'رصيد الصندوق',
                              amount: cashBalance,
                              color: const Color(0xFF1545B5),
                              icon: Icons.account_balance_wallet_outlined,
                            ),
                            _buildKpiTile(
                              label: 'قيمة المخزن (تكلفة)',
                              amount: invCost,
                              color: const Color(0xFFD97706),
                              icon: Icons.inventory_2_outlined,
                            ),
                            _buildKpiTile(
                              label: 'ديون العملاء',
                              amount: customersDebt,
                              color: const Color(0xFF7C3AED),
                              icon: Icons.person_outline,
                            ),
                            _buildKpiTile(
                              label: 'مستحقات الموردين',
                              amount: suppliersDebt,
                              color: const Color(0xFF4B5563),
                              icon: Icons.local_shipping_outlined,
                            ),
                          ],
                        ),

                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'القيمة البيعية للبضاعة المتوفرة:',
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                              ),
                              Text(
                                '${invSale.toStringAsFixed(2)} $_currencySymbol',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Color(0xFF16A34A),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // جدول الأصناف الأكثر مبيعاً
                        const SizedBox(height: 16),
                        const Text(
                          'الأصناف الأكثر مبيعاً خلال الفترة',
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_topProducts.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Center(
                              child: Text(
                                'لا توجد مبيعات مسجلة في هذه الفترة',
                                style: TextStyle(color: Colors.black54),
                              ),
                            ),
                          )
                        else
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE5E7EB)),
                            ),
                            child: ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _topProducts.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (_, idx) {
                                final item = _topProducts[idx];
                                final qty = (item['total_qty'] as num?)?.toDouble() ?? 0.0;
                                final tSales = (item['total_sales'] as num?)?.toDouble() ?? 0.0;
                                final tProfit = (item['total_profit'] as num?)?.toDouble() ?? 0.0;

                                return ListTile(
                                  dense: true,
                                  leading: CircleAvatar(
                                    radius: 14,
                                    backgroundColor: const Color(0xFFDBEAFE),
                                    child: Text(
                                      '${idx + 1}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF1545B5),
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    (item['product_name'] ?? '').toString(),
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                  ),
                                  subtitle: Text(
                                    'الكمية المباعة: $qty  •  المبيعات: ${tSales.toStringAsFixed(1)}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  trailing: Text(
                                    'ربح: ${tProfit.toStringAsFixed(1)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12.5,
                                      color: Color(0xFF16A34A),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// شاشة النسخ الاحتياطي والإعدادات (BackupAndSettingsScreen)
// =============================================================================

class BackupAndSettingsScreen extends StatefulWidget {
  const BackupAndSettingsScreen({super.key});

  @override
  State<BackupAndSettingsScreen> createState() => _BackupAndSettingsScreenState();
}

class _BackupAndSettingsScreenState extends State<BackupAndSettingsScreen> {
  final TextEditingController _storeNameCtrl = TextEditingController();
  final TextEditingController _storePhoneCtrl = TextEditingController();
  final TextEditingController _storeAddressCtrl = TextEditingController();
  final TextEditingController _currencyCtrl = TextEditingController();
  final TextEditingController _exchangeRateCtrl = TextEditingController();
  final TextEditingController _footerCtrl = TextEditingController();

  String _paperWidth = '80';
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _storeNameCtrl.dispose();
    _storePhoneCtrl.dispose();
    _storeAddressCtrl.dispose();
    _currencyCtrl.dispose();
    _exchangeRateCtrl.dispose();
    _footerCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _loading = true);
    final map = await DatabaseHelper.instance.getSettingsMap();
    if (!mounted) return;
    setState(() {
      _storeNameCtrl.text = map['store_name'] ?? 'نبراس SofT';
      _storePhoneCtrl.text = map['store_phone'] ?? '';
      _storeAddressCtrl.text = map['store_address'] ?? '';
      _currencyCtrl.text = map['currency_symbol'] ?? 'ريال';
      _exchangeRateCtrl.text = map['exchange_rate'] ?? '1';
      _footerCtrl.text = map['receipt_footer'] ?? 'شكراً لتعاملكم معنا';
      _paperWidth = (map['paper_width'] ?? '80') == '58' ? '58' : '80';
      _loading = false;
    });
  }

  Future<void> _saveAllSettings() async {
    setState(() => _busy = true);
    try {
      await DatabaseHelper.instance.saveSetting(
        'store_name',
        _storeNameCtrl.text.trim().isEmpty ? 'نبراس SofT' : _storeNameCtrl.text.trim(),
      );
      await DatabaseHelper.instance.saveSetting('store_phone', _storePhoneCtrl.text.trim());
      await DatabaseHelper.instance.saveSetting('store_address', _storeAddressCtrl.text.trim());
      await DatabaseHelper.instance.saveSetting(
        'currency_symbol',
        _currencyCtrl.text.trim().isEmpty ? 'ريال' : _currencyCtrl.text.trim(),
      );
      final rateVal = double.tryParse(_exchangeRateCtrl.text.trim()) ?? 1.0;
      await DatabaseHelper.instance.saveSetting(
        'exchange_rate',
        (rateVal > 0 ? rateVal : 1.0).toString(),
      );
      await DatabaseHelper.instance.saveSetting('receipt_footer', _footerCtrl.text.trim());
      await DatabaseHelper.instance.saveSetting('paper_width', _paperWidth);

      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ إعدادات المتجر والطباعة بنجاح')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حدث خطأ أثناء حفظ الإعدادات')),
      );
    }
  }

  Future<void> _createAndShareBackup() async {
    setState(() => _busy = true);
    try {
      await AppPermissionsService.ensureStoragePermissions();
      final db = await DatabaseHelper.instance.database;
      try {
        await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      } catch (_) {}

      final dbPath = await DatabaseHelper.instance.getDatabaseFilePath();
      final dbFile = File(dbPath);
      if (!await dbFile.exists()) {
        throw Exception('Database file not found');
      }

      final docsDir = await getApplicationDocumentsDirectory();
      final now = DateTime.now();
      final stamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
      final backupFile = File('${docsDir.path}/Nebras_SofT_Backup_$stamp.db');
      await dbFile.copy(backupFile.path);

      if (!mounted) return;
      setState(() => _busy = false);

      await Share.shareXFiles(
        [XFile(backupFile.path)],
        text: 'نسخة احتياطية لقاعدة بيانات نظام نبراس SofT ($stamp)',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر إنشاء النسخة الاحتياطية')),
      );
    }
  }

  Future<void> _restoreBackupFromFile() async {
    await AppPermissionsService.ensureStoragePermissions();
    final picked = await FilePicker.platform.pickFiles(type: FileType.any);
    if (picked == null || picked.files.single.path == null) return;

    final selectedFile = File(picked.files.single.path!);
    if (!await selectedFile.exists()) return;

    final bytes = await selectedFile.openRead(0, 16).fold<List<int>>(
      <int>[],
      (prev, chunk) => prev..addAll(chunk),
    );
    final header = ascii.decode(bytes, allowInvalid: true);
    if (!header.startsWith('SQLite format 3')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('الملف المختار ليس نسخة احتياطية صالحة لقاعدة البيانات (.db)'),
        ),
      );
      return;
    }

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          title: const Text(
            'تأكيد استعادة النسخة الاحتياطية',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          content: const Text(
            'سيتم استبدال جميع البيانات الحالية بالبيانات الموجودة في ملف النسخة الاحتياطية المختار.\n\nهل أنت متأكد من المتابعة؟',
            style: TextStyle(fontSize: 14.5, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('نعم، استعادة البيانات'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      final dbPath = await DatabaseHelper.instance.getDatabaseFilePath();
      await DatabaseHelper.instance.closeAndResetForRestore();

      final walFile = File('$dbPath-wal');
      final shmFile = File('$dbPath-shm');
      if (await walFile.exists()) await walFile.delete();
      if (await shmFile.exists()) await shmFile.delete();

      await selectedFile.copy(dbPath);
      await DatabaseHelper.instance.database;

      if (!mounted) return;
      setState(() => _busy = false);

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('تمت الاستعادة بنجاح', style: TextStyle(fontWeight: FontWeight.bold)),
            content: const Text('تمت استعادة قاعدة البيانات بنجاح. سيتم تحديث واجهة النظام الآن.'),
            actions: [
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const HomeDashboardScreen()),
                    (route) => false,
                  );
                },
                child: const Text('تحديث النظام'),
              ),
            ],
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فشلت عملية استعادة النسخة الاحتياطية')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F4F6),
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          title: const Text(
            'النسخ الاحتياطي والإعدادات',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  // 1. قسم النسخ الاحتياطي والاستعادة
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.backup_rounded, color: Color(0xFF1545B5)),
                            SizedBox(width: 8),
                            Text(
                              'النسخ الاحتياطي لقاعدة البيانات',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'احفظ نسخة احتياطية من جميع الأصناف والفواتير والحسابات وشاركها عبر واتساب أو تيليجرام أو Google Drive.',
                          style: TextStyle(fontSize: 12.5, color: Colors.black54, height: 1.4),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF16A34A),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: _busy ? null : _createAndShareBackup,
                          icon: const Icon(Icons.cloud_upload_outlined),
                          label: const Text(
                            'إنشاء ومشاركة نسخة احتياطية الآن',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: _busy ? null : _restoreBackupFromFile,
                          icon: const Icon(Icons.restore_page_outlined),
                          label: const Text(
                            'استعادة البيانات من ملف نسخة احتياطية (.db)',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // 2. قسم إعدادات المتجر والفاتورة الحرارية
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.store_mall_directory_outlined, color: Color(0xFF1545B5)),
                            SizedBox(width: 8),
                            Text(
                              'إعدادات المتجر والفواتير',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _storeNameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'اسم المتجر / الشركة (يظهر أعلى الفاتورة)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _storePhoneCtrl,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'رقم هاتف المتجر',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _storeAddressCtrl,
                          decoration: const InputDecoration(
                            labelText: 'عنوان المتجر',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _currencyCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'رمز العملة',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _exchangeRateCtrl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'معامل العملة الثانية',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _footerCtrl,
                          decoration: const InputDecoration(
                            labelText: 'رسالة تذييل الفاتورة الحرارية',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'مقاس ورق الطابعة الحرارية:',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                        ),
                        const SizedBox(height: 6),
                        SegmentedButton(
                          segments: const [
                            ButtonSegment(value: '80', label: Text('ورق عريض 80mm')),
                            ButtonSegment(value: '58', label: Text('ورق صغير 58mm')),
                          ],
                          selected: {_paperWidth},
                          onSelectionChanged: (sel) => setState(() => _paperWidth = sel.first),
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF1545B5),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: _busy ? null : _saveAllSettings,
                          icon: const Icon(Icons.save_outlined),
                          label: const Text(
                            'حفظ الإعدادات',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // 3. زر إغلاق التطبيق بأمان
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFDC2626),
                      side: const BorderSide(color: Color(0xFFDC2626)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: ForceUpdateGuardService.exitAppCompletely,
                    icon: const Icon(Icons.exit_to_app),
                    label: const Text('إغلاق التطبيق'),
                  ),
                ],
              ),
      ),
    );
  }
}

// =============================================================================
// بوت الدردشة الذكي وشخصية الروبوت (NebrasBotChatScreen)
// =============================================================================

class NebrasRobotAvatar extends StatelessWidget {
  final double size;

  const NebrasRobotAvatar({super.key, this.size = 44});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0EA5E9), Color(0xFF1545B5)],
        ),
        border: Border.all(color: Colors.white, width: size * 0.045),
        boxShadow: const [
          BoxShadow(
            color: Color(0x590EA5E9),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: CustomPaint(
        painter: _NebrasRobotCharacterPainter(),
      ),
    );
  }
}

class _NebrasRobotCharacterPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final whitePaint = Paint()..color = Colors.white;
    final visorPaint = Paint()..color = const Color(0xFF0F172A);
    final eyeGlowPaint = Paint()..color = const Color(0xFF38BDF8);
    final antennaTipPaint = Paint()..color = const Color(0xFFFACC15);
    final earPaint = Paint()..color = const Color(0xFFE2E8F0);
    final neckPaint = Paint()..color = const Color(0xFFCBD5E1);

    // 1. الهوائي العلوي للروبوت
    final stemPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = w * 0.055
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(w * 0.50, h * 0.25),
      Offset(w * 0.50, h * 0.13),
      stemPaint,
    );
    canvas.drawCircle(Offset(w * 0.50, h * 0.11), w * 0.065, antennaTipPaint);

    // 2. سماعات الأذن الجانبية للروبوت
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.13, h * 0.37, w * 0.09, h * 0.22),
        Radius.circular(w * 0.04),
      ),
      earPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.78, h * 0.37, w * 0.09, h * 0.22),
        Radius.circular(w * 0.04),
      ),
      earPaint,
    );

    // 3. رأس الروبوت
    final headRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.20, h * 0.25, w * 0.60, h * 0.46),
      Radius.circular(w * 0.15),
    );
    canvas.drawRRect(headRect, whitePaint);

    // 4. شاشة الوجه الداكنة (Visor)
    final visorRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.26, h * 0.32, w * 0.48, h * 0.30),
      Radius.circular(w * 0.10),
    );
    canvas.drawRRect(visorRect, visorPaint);

    // 5. العيون المضيئة للروبوت
    canvas.drawCircle(Offset(w * 0.39, h * 0.44), w * 0.055, eyeGlowPaint);
    canvas.drawCircle(Offset(w * 0.61, h * 0.44), w * 0.055, eyeGlowPaint);

    // لمعة صغيرة داخل العين
    canvas.drawCircle(Offset(w * 0.375, h * 0.425), w * 0.018, whitePaint);
    canvas.drawCircle(Offset(w * 0.595, h * 0.425), w * 0.018, whitePaint);

    // 6. ابتسامة الروبوت الرقمية
    final smilePaint = Paint()
      ..color = const Color(0xFF4ADE80)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.042
      ..strokeCap = StrokeCap.round;
    final smilePath = Path()
      ..moveTo(w * 0.42, h * 0.53)
      ..quadraticBezierTo(w * 0.50, h * 0.59, w * 0.58, h * 0.53);
    canvas.drawPath(smilePath, smilePaint);

    // 7. رقبة / قاعدة الروبوت
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.36, h * 0.74, w * 0.28, h * 0.10),
        Radius.circular(w * 0.04),
      ),
      neckPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BotChatMessage {
  final String text;
  final bool isUser;
  final DateTime time;
  final bool showDeveloperCard;

  _BotChatMessage({
    required this.text,
    required this.isUser,
    required this.time,
    this.showDeveloperCard = false,
  });
}

class NebrasBotChatScreen extends StatefulWidget {
  const NebrasBotChatScreen({super.key});

  @override
  State<NebrasBotChatScreen> createState() => _NebrasBotChatScreenState();
}

class _NebrasBotChatScreenState extends State<NebrasBotChatScreen> {
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final List<_BotChatMessage> _messages = [];
  bool _isThinking = false;

  static const _quickQuestions = [
    'كيف أستخدم التطبيق؟',
    'مراسلة المطور أبو نبراس',
    'حل مشكلة الكاميرا والباركود',
    'حل مشكلة البحث الصوتي',
    'طريقة البيع الآجل والطباعة',
    'كم مبيعات اليوم والصندوق؟',
    'أخذ واستعادة نسخة احتياطية',
  ];

  @override
  void initState() {
    super.initState();
    _messages.add(
      _BotChatMessage(
        isUser: false,
        time: DateTime.now(),
        text: 'أهلاً بك في مساعد نبراس الذكي 🤖\n\n'
            'أنا هنا لمساعدتك في:\n'
            '• شرح طريقة استخدام جميع أقسام التطبيق (المبيعات، المشتريات، المخزون، الصندوق).\n'
            '• حل أي مشكلة تقنية تواجهك في الكاميرا أو الصوت أو الطابعة.\n'
            '• الاستعلام السريع عن مبيعات اليوم ورصيد الصندوق والنواقص.\n'
            '• التواصل المباشر مع المطور م. أحمد البدوي (أبو نبراس).\n\n'
            'اكتب سؤالك بالأسفل أو اختر من الأزرار السريعة:',
      ),
    );
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent + 120,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _normalizeArabic(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll(RegExp(r'[^\w\s\u0600-\u06FF%]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _hasAny(String normalizedText, List keywords) {
    for (final k in keywords) {
      if (normalizedText.contains(_normalizeArabic(k.toString()))) {
        return true;
      }
    }
    return false;
  }

  Future<void> _sendMessage([String? presetText]) async {
    final raw = (presetText ?? _inputCtrl.text).trim();
    if (raw.isEmpty || _isThinking) return;

    if (presetText == null) {
      _inputCtrl.clear();
    }

    setState(() {
      _messages.add(
        _BotChatMessage(
          text: raw,
          isUser: true,
          time: DateTime.now(),
        ),
      );
      _isThinking = true;
    });
    _scrollToBottom();

    final reply = await _generateSmartReply(raw);
    if (!mounted) return;

    setState(() {
      _isThinking = false;
      _messages.add(reply);
    });
    _scrollToBottom();
  }

  Future<_BotChatMessage> _generateSmartReply(String userQuestion) async {
    final q = _normalizeArabic(userQuestion);

    // 1. التواصل مع المطور ابو نبراس احمد البدوي
    if (_hasAny(q, [
      'مطور',
      'ابو نبراس',
      'احمد البدوي',
      'تواصل',
      'مراسله',
      'واتساب',
      'واتس',
      'تيليجرام',
      'تليجرام',
      'دعم',
      'تفعيل',
      'رقم',
      'صاحب البرنامج',
    ])) {
      return _BotChatMessage(
        isUser: false,
        time: DateTime.now(),
        showDeveloperCard: true,
        text: 'يسعدنا تواصلك مع مطور النظام:\n'
            '👨‍💻 م. أحمد البدوي (أبو نبراس) — فريق نبراس SofT\n\n'
            'يمكنك مراسلته مباشرة لطلب الدعم الفني، التحديثات، أو تخصيص ميزات إضافية لمتجرك عبر الأزرار بالأسفل:',
      );
    }

    // 2. استعلام حي من قاعدة البيانات: مبيعات اليوم / الصندوق / النواقص / الديون
    if (_hasAny(q, [
      'كم مبيعات',
      'مبيعات اليوم',
      'كم الصندوق',
      'رصيد الصندوق',
      'كم في الصندوق',
      'النواقص',
      'الاصناف الناقصه',
      'ديون العملاء',
      'كم الارباح',
      'صافي الربح',
    ])) {
      final settings = await DatabaseHelper.instance.getSettingsMap();
      final curr = (settings['currency_symbol'] ?? 'ريال').trim();
      final todayPrefix = DateTime.now().toIso8601String().split('T').first;
      final todaySummary = await DatabaseHelper.instance.getFinancialSummary(
        datePrefix: todayPrefix,
      );
      final products = await DatabaseHelper.instance.queryAllProducts();

      int lowCount = 0;
      final lowNames = [];
      for (final p in products) {
        final stock = (p['stock_quantity'] as num?)?.toDouble() ?? 0.0;
        final minStock = (p['min_stock'] as num?)?.toDouble() ?? 2.0;
        if (stock <= minStock) {
          lowCount++;
          if (lowNames.length < 5) {
            lowNames.add('• ${p['name']} (المتبقي: $stock)');
          }
        }
      }

      final todaySales = (todaySummary['salesTotal'] ?? 0.0).toStringAsFixed(2);
      final todayProfit = (todaySummary['netProfit'] ?? 0.0).toStringAsFixed(2);
      final cashBal = (todaySummary['cashBalance'] ?? 0.0).toStringAsFixed(2);
      final custDebt = (todaySummary['customersDebt'] ?? 0.0).toStringAsFixed(2);
      final suppDebt = (todaySummary['suppliersDebt'] ?? 0.0).toStringAsFixed(2);

      final lowSection = lowCount == 0
          ? '• النواقص: لا توجد أصناف ناقصة حالياً.'
          : '• الأصناف الناقصة ($lowCount صنف):\n${lowNames.join('\n')}';

      return _BotChatMessage(
        isUser: false,
        time: DateTime.now(),
        text: '📊 ملخص بيانات متجرك اللحظية من قاعدة البيانات:\n\n'
            '• مبيعات اليوم: $todaySales $curr\n'
            '• صافي ربح اليوم: $todayProfit $curr\n'
            '• الرصيد النقدي في الصندوق: $cashBal $curr\n'
            '• إجمالي ديون العملاء: $custDebt $curr\n'
            '• مستحقات الموردين: $suppDebt $curr\n'
            '$lowSection',
      );
    }

    // 3. حل مشكلة الكاميرا وقارئ الباركود
    if (_hasAny(q, [
      'كاميرا',
      'باركود',
      'مسح',
      'قراءه الباركود',
      'لا يمسح',
      'الكامرا',
    ])) {
      return _BotChatMessage(
        isUser: false,
        time: DateTime.now(),
        text: '📷 حل مشكلة الكاميرا وقارئ الباركود:\n\n'
            '1. تأكد من منح إذن الكاميرا للتطبيق: افتح (إعدادات الهاتف ← التطبيقات ← Nebras SofT Pos ← الأذونات ← الكاميرا ← سماح).\n'
            '2. في الإضاءة الضعيفة، اضغط على أيقونة الفلاش أعلى شاشة المسح.\n'
            '3. تأكد من عدم وجود تطبيق آخر يستخدم الكاميرا في الخلفية.\n'
            '4. إذا تعذر المسح لأي سبب، يمكنك الضغط على زر (إدخال يدوي) أسفل شاشة المسح وكتابة الرقم مباشرة.',
      );
    }

    // 4. حل مشكلة البحث الصوتي بدون إنترنت
    if (_hasAny(q, [
      'صوت',
      'مايك',
      'ميكروفون',
      'بحث صوتي',
      'بدون انترنت',
      'لا يسمع',
    ])) {
      return _BotChatMessage(
        isUser: false,
        time: DateTime.now(),
        text: '🎙️ حل مشكلة البحث الصوتي بدون إنترنت:\n\n'
            '1. تأكد من السماح بإذن الميكروفون للتطبيق من (إعدادات الهاتف ← الأذونات ← الميكروفون ← سماح).\n'
            '2. لتشغيل البحث الصوتي بدون إنترنت، افتح تطبيق Google (والإنترنت متصل مرة واحدة) وانتقل إلى:\n'
            '   صورة الحساب ← الإعدادات ← الصوت ← التعرف على الكلام بلا اتصال بالإنترنت ← الكل ← اختر (العربية) وحمّل الحزمة.\n'
            '3. بعدها سيعمل البحث الصوتي في شاشة المشتريات بسرعة وبدون إنترنت.',
      );
    }

    // 5. حل مشكلة الطابعة الحرارية والفواتير
    if (_hasAny(q, [
      'طابعه',
      'طباعه',
      'بلوتوث',
      'ورق',
      'حراريه',
      'فاتوره',
    ])) {
      return _BotChatMessage(
        isUser: false,
        time: DateTime.now(),
        text: '🖨️ حل مشاكل الطباعة الحرارية:\n\n'
            '1. تأكد من تشغيل البلوتوث في الهاتف واقتران الطابعة الحرارية من إعدادات بلوتوث الهاتف أولاً.\n'
            '2. ادخل إلى (النسخ الاحتياطي والإعدادات) داخل التطبيق واختر مقاس ورق طابعتك الصحيح (80mm للورق العريض أو 58mm للورق الصغير) ثم اضغط (حفظ الإعدادات).\n'
            '3. يمكنك إعادة طباعة أي فاتورة سابقة من خلال أيقونة السجل أعلى شاشة المبيعات أو المشتريات.',
      );
    }

    // 6. البيع الآجل والعملاء والموردين
    if (_hasAny(q, [
      'بيع',
      'مبيعات',
      'اجل',
      'دين',
      'عميل',
      'عملاء',
      'مورد',
      'سند',
      'تسعيره',
      'جمله',
    ])) {
      return _BotChatMessage(
        isUser: false,
        time: DateTime.now(),
        text: '🛒 طريقة العمل في المبيعات والبيع الآجل:\n\n'
            '1. اختر مستوى التسعيرة أعلى الشاشة (قطاعي 1 / جملة 2 / خاص 3).\n'
            '2. أضف الأصناف بالضغط عليها أو بمسح الباركود بالكاميرا، ويمكنك تعديل كمية أو سعر أي صنف بالضغط عليه في الجدول.\n'
            '3. عند البيع الآجل أو الجزئي: اضغط على أيقونة الشخص أعلى الشاشة لاختيار اسم العميل (أو إضافته)، ثم اختر (آجل) أو (جزئي) عند الحفظ ليُضاف المتبقي لحسابه تلقائياً.\n'
            '4. لتحصيل دفعة من عميل: افتح (العملاء والموردين) واضغط على أيقونة الدفع بجانب اسمه لتسجيل سند قبض.',
      );
    }

    // 7. المخزون، إضافة منتج، وتعديل الأسعار
    if (_hasAny(q, [
      'مخزون',
      'منتج',
      'صنف',
      'تصنيف',
      'تعديل اسعار',
      'سعر صرف',
      'صناعه الباركود',
    ])) {
      return _BotChatMessage(
        isUser: false,
        time: DateTime.now(),
        text: '📦 إدارة المخزون والأسعار والباركود:\n\n'
            '• إضافة منتج جديد: أدخل الاسم، التكلفة، وأسعار البيع الثلاثة، ويمكنك قراءة الباركود بالكاميرا أو ترك الرقم المولّد تلقائياً.\n'
            '• عرض المنتجات: يتيح لك البحث بالاسم أو الباركود، طباعة تقرير جرد PDF/Excel، وطباعة ملصقات الباركود للأصناف.\n'
            '• تعديل أسعار المنتجات: يتيح رفع أو خفض أسعار البيع أو الشراء لجميع المنتجات أو لتصنيف محدد دفعة واحدة (بمبلغ ثابت، نسبة %، أو معامل سعر صرف).',
      );
    }

    // 8. النسخ الاحتياطي والاستعادة
    if (_hasAny(q, [
      'نسخه',
      'احتياطي',
      'استعاده',
      'حفظ البيانات',
      'نقل البيانات',
      'ضاعت',
    ])) {
      return _BotChatMessage(
        isUser: false,
        time: DateTime.now(),
        text: '💾 النسخ الاحتياطي واستعادة البيانات:\n\n'
            '1. لحفظ بياناتك: افتح (النسخ الاحتياطي) واضغط على (إنشاء ومشاركة نسخة احتياطية الآن) ثم أرسل الملف إلى واتساب أو تيليجرام أو احفظه في Google Drive.\n'
            '2. للاستعادة: اضغط على (استعادة البيانات من ملف نسخة احتياطية) واختر الملف الذي ينتهي بصيغة (.db).\n'
            '⚠️ تنبيه: تأكد من اختيار ملف قاعدة البيانات (.db) الأصلي غير المضغوط.',
      );
    }

    // 9. شرح عام لكيفية التعامل مع التطبيق
    if (_hasAny(q, [
      'كيف استخدم',
      'شرح',
      'بدايه',
      'تعلم',
      'كيفيه التعامل',
      'دليل',
      'مرحبا',
      'السلام',
      'هلا',
    ])) {
      return _BotChatMessage(
        isUser: false,
        time: DateTime.now(),
        text: '📘 دليل البدء السريع في نظام Nebras SofT Pos:\n\n'
            '1️⃣ أضف بيانات متجرك وعملتك من (النسخ الاحتياطي والإعدادات).\n'
            '2️⃣ سجّل أصنافك وأسعارها من قسم (المخزون ← إضافة منتج جديد)، أو أدخلها عبر فاتورة (المشتريات) لتُضاف للمخزن تلقائياً.\n'
            '3️⃣ ابدأ البيع من قسم (المبيعات) نقداً أو آجلاً واطبع الفواتير حرارياً.\n'
            '4️⃣ راقب أرباحك ومصروفاتك من (الصندوق والمصاريف) و(التقارير والأرباح).\n'
            '5️⃣ احتفظ بنسخة احتياطية دورية لبياناتك.',
      );
    }

    // 10. رد ذكي عام عند طرح سؤال غير محدد مع عرض خيار مراسلة المطور
    return _BotChatMessage(
      isUser: false,
      time: DateTime.now(),
      showDeveloperCard: true,
      text: 'سؤالك مهم! للحصول على أفضل إجابة، يمكنك كتابة كلمات مفتاحية مثل:\n'
          '• "مبيعات اليوم" أو "رصيد الصندوق"\n'
          '• "مشكلة الكاميرا" أو "مشكلة الصوت" أو "الطابعة"\n'
          '• "البيع الآجل" أو "تعديل الأسعار" أو "النسخ الاحتياطي"\n\n'
          'أو يمكنك مراسلة المطور م. أحمد البدوي (أبو نبراس) مباشرة للمساعدة الفورية:',
    );
  }

  Future<void> _openTelegramDeveloper() async {
    final uri = Uri.parse('https://t.me/softnebras');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('معرف المطور على تيليجرام: @softnebras')),
      );
    }
  }

  Future<void> _openWhatsAppDeveloper() async {
    final msg = Uri.encodeComponent(
      'السلام عليكم أستاذ أحمد البدوي (أبو نبراس)، أحتاج مساعدة بخصوص تطبيق Nebras SofT Pos.',
    );
    final waUri = Uri.parse('whatsapp://send?text=$msg');
    final webUri = Uri.parse('https://api.whatsapp.com/send?text=$msg');
    try {
      if (!await launchUrl(waUri, mode: LaunchMode.externalApplication)) {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تأكد من تثبيت تطبيق واتساب على الهاتف')),
      );
    }
  }

  Widget _buildDeveloperContactCard() {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBAE6FD)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Color(0xFF1545B5),
                child: Icon(Icons.engineering, color: Colors.white, size: 20),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'المطور: م. أحمد البدوي (أبو نبراس)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      'نبراس SofT • @softnebras',
                      style: TextStyle(fontSize: 12, color: Color(0xFF0369A1)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onPressed: _openTelegramDeveloper,
                  icon: const Icon(Icons.send_rounded, size: 17),
                  label: const Text('تيليجرام', style: TextStyle(fontSize: 13)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onPressed: _openWhatsAppDeveloper,
                  icon: const Icon(Icons.chat_rounded, size: 17),
                  label: const Text('واتساب', style: TextStyle(fontSize: 13)),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.outlined(
                tooltip: 'نسخ معرف تيليجرام',
                onPressed: () {
                  Clipboard.setData(const ClipboardData(text: '@softnebras'));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم نسخ معرف المطور: @softnebras')),
                  );
                },
                icon: const Icon(Icons.copy, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F4F6),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1545B5),
          foregroundColor: Colors.white,
          titleSpacing: 4,
          title: const Row(
            children: [
              NebrasRobotAvatar(size: 38),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'مساعد نبراس الذكي',
                      style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    Text(
                      'متصل دائماً • شرح النظام والدعم الفني',
                      style: TextStyle(fontSize: 11.5, color: Color(0xFFBAE6FD)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'مراسلة المطور أبو نبراس',
              icon: const Icon(Icons.support_agent_rounded, color: Colors.white),
              onPressed: () => _sendMessage('مراسلة المطور أبو نبراس'),
            ),
          ],
        ),
        body: Column(
          children: [
            // شريط الأسئلة المقترحة السريعة
            Container(
              height: 48,
              color: Colors.white,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                itemCount: _quickQuestions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, idx) {
                  final qText = _quickQuestions[idx];
                  return ActionChip(
                    backgroundColor: const Color(0xFFEFF6FF),
                    side: const BorderSide(color: Color(0xFFBFDBFE)),
                    label: Text(
                      qText,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E40AF),
                      ),
                    ),
                    onPressed: () => _sendMessage(qText),
                  );
                },
              ),
            ),
            const Divider(height: 1),

            // سجل رسائل المحادثة
            Expanded(
              child: ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                itemCount: _messages.length + (_isThinking ? 1 : 0),
                itemBuilder: (_, idx) {
                  if (_isThinking && idx == _messages.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          NebrasRobotAvatar(size: 32),
                          SizedBox(width: 8),
                          Text('الروبوت يجهز الرد...', style: TextStyle(color: Colors.black54, fontSize: 13)),
                        ],
                      ),
                    );
                  }

                  final msg = _messages[idx];
                  final timeStr =
                      '${msg.time.hour.toString().padLeft(2, '0')}:${msg.time.minute.toString().padLeft(2, '0')}';

                  if (msg.isUser) {
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10, right: 44),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: const BoxDecoration(
                          color: Color(0xFF1545B5),
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(16),
                            topRight: Radius.circular(16),
                            bottomRight: Radius.circular(16),
                            bottomLeft: Radius.circular(4),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              msg.text,
                              style: const TextStyle(color: Colors.white, fontSize: 14.5, height: 1.4),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              timeStr,
                              style: const TextStyle(color: Colors.white70, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12, left: 26),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const NebrasRobotAvatar(size: 34),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(16),
                                topRight: Radius.circular(16),
                                bottomLeft: Radius.circular(16),
                                bottomRight: Radius.circular(4),
                              ),
                              border: Border.all(color: const Color(0xFFE5E7EB)),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x0A000000),
                                  blurRadius: 4,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  msg.text,
                                  style: const TextStyle(
                                    color: Color(0xFF1F2937),
                                    fontSize: 14,
                                    height: 1.5,
                                  ),
                                ),
                                if (msg.showDeveloperCard) _buildDeveloperContactCard(),
                                const SizedBox(height: 4),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    timeStr,
                                    style: const TextStyle(color: Colors.black45, fontSize: 10),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // شريط كتابة السؤال والإرسال
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _inputCtrl,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        decoration: InputDecoration(
                          hintText: 'اكتب سؤالك هنا (مثلاً: حل مشكلة الكاميرا)...',
                          hintStyle: const TextStyle(fontSize: 13.5),
                          isDense: true,
                          filled: true,
                          fillColor: const Color(0xFFF3F4F6),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFF1545B5),
                        padding: const EdgeInsets.all(11),
                      ),
                      tooltip: 'إرسال',
                      icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                      onPressed: () => _sendMessage(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
// =============================================================================
// بوابة التشغيل + شاشة الترحيب + واجهة طلب تسجيل الدخول وتنشيط النظام
// =============================================================================

class _CountryDialCode {
  final String name;
  final String flag;
  final String dialCode;

  const _CountryDialCode({
    required this.name,
    required this.flag,
    required this.dialCode,
  });

  String get formattedDial => '+$dialCode';
}

const List<_CountryDialCode> _kSupportedCountries = [
  _CountryDialCode(name: 'اليمن', flag: '🇾🇪', dialCode: '967'),
  _CountryDialCode(name: 'السعودية', flag: '🇸🇦', dialCode: '966'),
  _CountryDialCode(name: 'الإمارات', flag: '🇦🇪', dialCode: '971'),
  _CountryDialCode(name: 'سلطنة عُمان', flag: '🇴🇲', dialCode: '968'),
  _CountryDialCode(name: 'قطر', flag: '🇶🇦', dialCode: '974'),
  _CountryDialCode(name: 'الكويت', flag: '🇰🇼', dialCode: '965'),
  _CountryDialCode(name: 'البحرين', flag: '🇧🇭', dialCode: '973'),
  _CountryDialCode(name: 'مصر', flag: '🇪🇬', dialCode: '20'),
  _CountryDialCode(name: 'الأردن', flag: '🇯🇴', dialCode: '962'),
  _CountryDialCode(name: 'العراق', flag: '🇮🇶', dialCode: '964'),
  _CountryDialCode(name: 'سوريا', flag: '🇸🇾', dialCode: '963'),
  _CountryDialCode(name: 'لبنان', flag: '🇱🇧', dialCode: '961'),
  _CountryDialCode(name: 'فلسطين', flag: '🇵🇸', dialCode: '970'),
  _CountryDialCode(name: 'السودان', flag: '🇸🇩', dialCode: '249'),
  _CountryDialCode(name: 'ليبيا', flag: '🇱🇾', dialCode: '218'),
  _CountryDialCode(name: 'تونس', flag: '🇹🇳', dialCode: '216'),
  _CountryDialCode(name: 'الجزائر', flag: '🇩🇿', dialCode: '213'),
  _CountryDialCode(name: 'المغرب', flag: '🇲🇦', dialCode: '212'),
  _CountryDialCode(name: 'موريتانيا', flag: '🇲🇷', dialCode: '222'),
  _CountryDialCode(name: 'الصومال', flag: '🇸🇴', dialCode: '252'),
  _CountryDialCode(name: 'جيبوتي', flag: '🇩🇯', dialCode: '253'),
  _CountryDialCode(name: 'تركيا', flag: '🇹🇷', dialCode: '90'),
  _CountryDialCode(name: 'ماليزيا', flag: '🇲🇾', dialCode: '60'),
  _CountryDialCode(name: 'إندونيسيا', flag: '🇮🇩', dialCode: '62'),
  _CountryDialCode(name: 'الهند', flag: '🇮🇳', dialCode: '91'),
  _CountryDialCode(name: 'الولايات المتحدة', flag: '🇺🇸', dialCode: '1'),
  _CountryDialCode(name: 'بريطانيا', flag: '🇬🇧', dialCode: '44'),
];

class LicenseActivationService {
  static const String _secretSalt = 'NEBRAS_SOFT_POS_2026_ABU_NEBRAS';

  static Future<String> getOrCreateDeviceId() async {
    final settings = await DatabaseHelper.instance.getSettingsMap();
    final existing = (settings['device_hardware_id'] ?? '').trim();
    if (existing.isNotEmpty && existing.startsWith('NSFP-')) {
      return existing;
    }

    final raw =
        '${Platform.operatingSystem}_${Platform.localHostname}_${DateTime.now().microsecondsSinceEpoch}';
    int h1 = 0x811C9DC5;
    int h2 = 0x1545B5;
    int h3 = 5381;
    for (final unit in raw.codeUnits) {
      h1 ^= unit;
      h1 = (h1 * 0x01000193) & 0xFFFFFFFF;
      h2 = ((h2 << 5) - h2 + unit) & 0x7FFFFFFF;
      h3 = ((h3 << 7) ^ (h3 >> 3) ^ unit) & 0x7FFFFFFF;
    }
    final p1 = (h1 & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0');
    final p2 = (h2 & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0');
    final p3 = (h3 & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0');
    final deviceId = 'NSFP-$p1-$p2-$p3';

    await DatabaseHelper.instance.saveSetting('device_hardware_id', deviceId);
    return deviceId;
  }

  static String computeExpectedKey(String deviceId) {
    final cleanId = deviceId.trim().toUpperCase();
    final combined = '$cleanId|$_secretSalt';
    int h1 = 0x811C9DC5;
    int h2 = 0x1545B5;
    for (final c in combined.codeUnits) {
      h1 ^= c;
      h1 = (h1 * 0x01000193) & 0xFFFFFFFF;
      h2 = ((h2 << 5) - h2 + c) & 0x7FFFFFFF;
    }
    final part1 = (h1 & 0xFFFF).toRadixString(16).toUpperCase().padLeft(4, '0');
    final part2 = (h2 & 0xFFFF).toRadixString(16).toUpperCase().padLeft(4, '0');
    final part3 = ((h1 >> 16) & 0xFFFF).toRadixString(16).toUpperCase().padLeft(4, '0');
    return '$part1-$part2-$part3';
  }

  static Future<bool> isActivated() async {
    final settings = await DatabaseHelper.instance.getSettingsMap();
    final flag = (settings['is_app_activated'] ?? '').trim();
    if (flag != '1') return false;
    final deviceId = await getOrCreateDeviceId();
    final savedKey = (settings['activation_key'] ?? '').trim().toUpperCase();
    return savedKey == computeExpectedKey(deviceId);
  }

  static Future<bool> activateWithKey(String inputKey) async {
    final deviceId = await getOrCreateDeviceId();
    final expected = computeExpectedKey(deviceId);
    final normalizedInput = inputKey.trim().toUpperCase();
    if (normalizedInput == expected) {
      await DatabaseHelper.instance.saveSetting('activation_key', normalizedInput);
      await DatabaseHelper.instance.saveSetting('is_app_activated', '1');
      return true;
    }
    return false;
  }
}

// -----------------------------------------------------------------------------
// أيقونة التطبيق المدمجة برمجياً (NS sofT POS)
// -----------------------------------------------------------------------------
class NebrasAppLogoWidget extends StatelessWidget {
  final double size;

  const NebrasAppLogoWidget({super.key, this.size = 86});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _NebrasAppLogoPainter(),
        ),
      ),
    );
  }
}

class _NebrasAppLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Rect.fromLTWH(0, 0, w, h);

    final bgPaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment(0.0, -0.75),
        radius: 1.25,
        colors: [
          Color(0xFF0A84E3),
          Color(0xFF1545B5),
          Color(0xFF161366),
        ],
        stops: [0.0, 0.55, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, bgPaint);

    final inset = w * 0.055;
    final borderRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(inset, inset, w - inset * 2, h - inset * 2),
      Radius.circular(w * 0.23),
    );
    final borderPaint = Paint()
      ..color = const Color(0xFFA5C8FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.016;
    canvas.drawRRect(borderRect, borderPaint);

    final nsPainter = TextPainter(
      text: TextSpan(
        text: 'NS',
        style: TextStyle(
          color: Colors.white,
          fontSize: w * 0.44,
          fontWeight: FontWeight.w900,
          letterSpacing: -w * 0.015,
          height: 1.0,
          shadows: [
            Shadow(
              color: Colors.black.withAlpha(110),
              blurRadius: w * 0.03,
              offset: Offset(0, w * 0.018),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    nsPainter.paint(canvas, Offset((w - nsPainter.width) / 2, h * 0.22));

    final subPainter = TextPainter(
      text: TextSpan(
        text: 'sofT POS',
        style: TextStyle(
          color: const Color(0xFFB8D4FF),
          fontSize: w * 0.145,
          fontWeight: FontWeight.w800,
          letterSpacing: w * 0.005,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    subPainter.paint(canvas, Offset((w - subPainter.width) / 2, h * 0.71));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// -----------------------------------------------------------------------------
// الشريط المتحرك من اليمين إلى اليسار (Marquee Banner)
// -----------------------------------------------------------------------------
class _ArabicMarqueeBanner extends StatefulWidget {
  final String text;

  const _ArabicMarqueeBanner({required this.text});

  @override
  State<_ArabicMarqueeBanner> createState() => _ArabicMarqueeBannerState();
}

class _ArabicMarqueeBannerState extends State<_ArabicMarqueeBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(
      fontSize: 15.5,
      fontWeight: FontWeight.bold,
      color: Color(0xFFFEF08A),
      letterSpacing: 0.2,
    );

    final tp = TextPainter(
      text: TextSpan(text: widget.text, style: textStyle),
      maxLines: 1,
      textDirection: TextDirection.rtl,
    )..layout();
    final double textWidth = tp.width + 24;

    return Container(
      height: 44,
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0A2463), Color(0xFF1545B5), Color(0xFF0A2463)],
        ),
        border: Border(
          bottom: BorderSide(color: Color(0xFF38BDF8), width: 1.5),
        ),
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double boxWidth = constraints.maxWidth;
            final double totalDistance = boxWidth + textWidth;
            return AnimatedBuilder(
              animation: _controller,
              builder: (_, __) {
                final double dx = boxWidth - (_controller.value * totalDistance);
                return Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Positioned(
                      left: dx,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: Text(
                          widget.text,
                          textDirection: TextDirection.rtl,
                          maxLines: 1,
                          softWrap: false,
                          style: textStyle,
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// بوابة فحص التفعيل عند تشغيل التطبيق
// -----------------------------------------------------------------------------
class AppStartupGateScreen extends StatefulWidget {
  const AppStartupGateScreen({super.key});

  @override
  State<AppStartupGateScreen> createState() => _AppStartupGateScreenState();
}

class _AppStartupGateScreenState extends State<AppStartupGateScreen> {
  @override
  void initState() {
    super.initState();
    _checkRoute();
  }

  Future<void> _checkRoute() async {
    final active = await LicenseActivationService.isActivated();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => active
            ? const WelcomeSplashScreen()
            : const ActivationLoginScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0D2A7A),
      body: Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// شاشة الدخول الترحيبية بعد التنشيط (تستمر 3 ثوانٍ ثم تفتح التطبيق تلقائياً)
// -----------------------------------------------------------------------------
class WelcomeSplashScreen extends StatefulWidget {
  const WelcomeSplashScreen({super.key});

  @override
  State<WelcomeSplashScreen> createState() => _WelcomeSplashScreenState();
}

class _WelcomeSplashScreenState extends State<WelcomeSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeIn);
    _scaleAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutBack),
    );
    _animCtrl.forward();

    Future.delayed(const Duration(milliseconds: 2800), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeDashboardScreen()),
      );
    });
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF0A2463),
                Color(0xFF1545B5),
                Color(0xFF0F172A),
              ],
            ),
          ),
          child: SafeArea(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: ScaleTransition(
                scale: _scaleAnim,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x660EA5E9),
                              blurRadius: 24,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const NebrasAppLogoWidget(size: 120),
                      ),
                      const SizedBox(height: 28),
                      const Text(
                        'مرحبا بكم في نظام نبراس SofT المحاسبي المتكامل',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Nebras SofT Pos',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFBAE6FD),
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 36),
                      const SizedBox(
                        width: 30,
                        height: 30,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.8,
                          color: Color(0xFF38BDF8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// واجهة طلب تسجيل الدخول وتفعيل التطبيق
// -----------------------------------------------------------------------------
class ActivationLoginScreen extends StatefulWidget {
  const ActivationLoginScreen({super.key});

  @override
  State<ActivationLoginScreen> createState() => _ActivationLoginScreenState();
}

class _ActivationLoginScreenState extends State<ActivationLoginScreen> {
  final TextEditingController _userNameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _keyCtrl = TextEditingController();

  _CountryDialCode _selectedCountry = _kSupportedCountries.first; // اليمن افتراضياً
  String _deviceId = '...';
  bool _activating = false;
  bool _isParsingPhone = false;

  static const Color _primaryNavy = Color(0xFF0D2A7A);

  @override
  void initState() {
    super.initState();
    _initDeviceInfo();
  }

  @override
  void dispose() {
    _userNameCtrl.dispose();
    _phoneCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  String _normalizeDigits(String input) {
    const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
    const persianDigits = '۰۱۲۳۴۵۶۷۸۹';
    final buf = StringBuffer();
    for (int i = 0; i < input.length; i++) {
      final ch = input[i];
      final arIdx = arabicDigits.indexOf(ch);
      if (arIdx != -1) {
        buf.write(arIdx);
        continue;
      }
      final faIdx = persianDigits.indexOf(ch);
      if (faIdx != -1) {
        buf.write(faIdx);
        continue;
      }
      buf.write(ch);
    }
    return buf.toString();
  }

  void _onPhoneChanged(String rawValue) {
    if (_isParsingPhone) return;

    final normalized = _normalizeDigits(rawValue);
    final trimmed = normalized.trim();
    final hasInternationalPrefix =
        trimmed.startsWith('+') || trimmed.startsWith('00');
    String digitsOnly = trimmed.replaceAll(RegExp(r'[^0-9]'), '');

    if (digitsOnly.isEmpty) {
      if (normalized != rawValue) {
        _isParsingPhone = true;
        _phoneCtrl.value = const TextEditingValue(text: '');
        _isParsingPhone = false;
      }
      return;
    }

    if (digitsOnly.startsWith('00')) {
      digitsOnly = digitsOnly.substring(2);
    }

    final sortedCountries = List<_CountryDialCode>.from(_kSupportedCountries)
      ..sort((a, b) => b.dialCode.length.compareTo(a.dialCode.length));

    _CountryDialCode? detectedCountry;
    String localNumber = digitsOnly;

    for (final c in sortedCountries) {
      if (digitsOnly.startsWith(c.dialCode)) {
        final rest = digitsOnly.substring(c.dialCode.length);
        if (hasInternationalPrefix ? rest.isNotEmpty : rest.length >= 7) {
          detectedCountry = c;
          localNumber = rest.replaceFirst(RegExp(r'^0+'), '');
          break;
        }
      }
    }

    if (detectedCountry == null) {
      final noLeadingZero = digitsOnly.replaceFirst(RegExp(r'^0+'), '');
      if (noLeadingZero.length == 9 &&
          RegExp(r'^(70|71|73|77|78)\d{7}$').hasMatch(noLeadingZero)) {
        detectedCountry = _kSupportedCountries.first; // اليمن +967
        localNumber = noLeadingZero;
      } else if (digitsOnly.startsWith('05') && digitsOnly.length == 10) {
        localNumber = noLeadingZero;
      }
    }

    if (detectedCountry != null &&
        detectedCountry.dialCode != _selectedCountry.dialCode) {
      setState(() {
        _selectedCountry = detectedCountry!;
      });
    }

    if (localNumber != rawValue) {
      _isParsingPhone = true;
      _phoneCtrl.value = TextEditingValue(
        text: localNumber,
        selection: TextSelection.collapsed(offset: localNumber.length),
      );
      _isParsingPhone = false;
    }
  }

  String get _fullInternationalPhone {
    final local = _normalizeDigits(_phoneCtrl.text)
        .replaceAll(RegExp(r'[^0-9]'), '')
        .replaceFirst(RegExp(r'^0+'), '');
    if (local.isEmpty) return '';
    return '${_selectedCountry.formattedDial} $local';
  }

  bool _isValidName(String name) {
    final cleaned = name.trim();
    if (cleaned.length < 2) return false;
    return RegExp(r'^[\u0600-\u06FFa-zA-Z\s]+$').hasMatch(cleaned);
  }

  Future<void> _initDeviceInfo() async {
    final id = await LicenseActivationService.getOrCreateDeviceId();
    final settings = await DatabaseHelper.instance.getSettingsMap();
    if (!mounted) return;
    setState(() {
      _deviceId = id;
      final store = (settings['store_name'] ?? '').trim();
      if (store.isNotEmpty && store != 'نبراس SofT' && _isValidName(store)) {
        _userNameCtrl.text = store;
      }
      final savedPhone = (settings['store_phone'] ?? '').trim();
      if (savedPhone.isNotEmpty) {
        _onPhoneChanged(savedPhone);
        if (_phoneCtrl.text.isEmpty) {
          _phoneCtrl.text = savedPhone;
        }
      }
    });
  }

  Future<void> _openCountryPickerDialog() async {
    String searchQuery = '';
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final filtered = _kSupportedCountries.where((c) {
            if (searchQuery.trim().isEmpty) return true;
            final q = searchQuery.trim().toLowerCase();
            return c.name.toLowerCase().contains(q) ||
                c.dialCode.contains(q) ||
                c.formattedDial.contains(q);
          }).toList();

          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              title: const Text(
                'اختر الدولة ومفتاح الاتصال',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.5),
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 360,
                child: Column(
                  children: [
                    TextField(
                      onChanged: (v) => setDialogState(() => searchQuery = v),
                      decoration: InputDecoration(
                        hintText: 'ابحث باسم الدولة أو المفتاح (مثلاً: 967)...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        isDense: true,
                        filled: true,
                        fillColor: const Color(0xFFF3F4F6),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, idx) {
                          final country = filtered[idx];
                          final isSelected =
                              country.dialCode == _selectedCountry.dialCode;
                          return ListTile(
                            dense: true,
                            leading: Text(
                              country.flag,
                              style: const TextStyle(fontSize: 24),
                            ),
                            title: Text(
                              country.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14.5,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Directionality(
                                  textDirection: TextDirection.ltr,
                                  child: Text(
                                    country.formattedDial,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: _primaryNavy,
                                    ),
                                  ),
                                ),
                                if (isSelected) ...[
                                  const SizedBox(width: 6),
                                  const Icon(
                                    Icons.check_circle,
                                    color: Color(0xFF16A34A),
                                    size: 19,
                                  ),
                                ],
                              ],
                            ),
                            onTap: () {
                              setState(() => _selectedCountry = country);
                              Navigator.of(ctx).pop();
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _buildDeveloperRequestMessage(String name, String fullPhone) {
    return 'السلام عليكم أستاذ أبو نبراس أحمد البدوي، أرجو تفعيل النظام المحاسبي Nebras SofT Pos.\n'
        '• الاسم: $name\n'
        '• الدولة: ${_selectedCountry.flag} ${_selectedCountry.name}\n'
        '• رقم الهاتف: $fullPhone\n'
        '• معرّف الجهاز: $_deviceId';
  }

  bool _validateBeforeSending() {
    final name = _userNameCtrl.text.trim();
    final fullPhone = _fullInternationalPhone;

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFDC2626),
          content: Text('يرجى كتابة الاسم أولاً (بالحروف العربية أو الإنجليزية فقط).'),
        ),
      );
      return false;
    }
    if (!_isValidName(name)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFDC2626),
          content: Text('الاسم يجب أن يحتوي على حروف عربية أو إنجليزية فقط بدون أرقام أو رموز.'),
        ),
      );
      return false;
    }
    if (fullPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFDC2626),
          content: Text('يرجى إدخال رقم الهاتف أولاً قبل الإرسال للمطور.'),
        ),
      );
      return false;
    }
    return true;
  }

  Future<void> _sendToDeveloperWhatsApp() async {
    if (!_validateBeforeSending()) return;
    final msg = _buildDeveloperRequestMessage(
      _userNameCtrl.text.trim(),
      _fullInternationalPhone,
    );
    final encoded = Uri.encodeComponent(msg);
    final waUri = Uri.parse('whatsapp://send?phone=967735114406&text=$encoded');
    final webUri =
        Uri.parse('https://api.whatsapp.com/send?phone=967735114406&text=$encoded');
    try {
      if (!await launchUrl(waUri, mode: LaunchMode.externalApplication)) {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح تطبيق واتساب، تأكد من تثبيته على الهاتف')),
      );
    }
  }

  Future<void> _sendToDeveloperTelegram() async {
    if (!_validateBeforeSending()) return;
    final msg = _buildDeveloperRequestMessage(
      _userNameCtrl.text.trim(),
      _fullInternationalPhone,
    );
    await Clipboard.setData(ClipboardData(text: msg));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF0284C7),
          content: Text('تم نسخ بياناتك ومعرّف الجهاز — الصق الرسالة وأرسلها للمطور في تليجرام'),
        ),
      );
    }
    final uri = Uri.parse('https://t.me/softnebras');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حساب المطور على تليجرام: @softnebras')),
      );
    }
  }

  Future<void> _pasteSerialFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = (data?.text ?? '').trim();
    if (text.isNotEmpty) {
      setState(() => _keyCtrl.text = text);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الحافظة فارغة')),
      );
    }
  }

  Future<void> _submitActivation() async {
    if (!_validateBeforeSending()) return;

    final serial = _keyCtrl.text.trim();
    if (serial.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFDC2626),
          content: Text('يرجى لصق مفتاح التنشيط أو السريال المرسل من المطور أولاً'),
        ),
      );
      return;
    }

    setState(() => _activating = true);
    final isValid = await LicenseActivationService.activateWithKey(serial);
    if (!mounted) return;
    setState(() => _activating = false);

    if (isValid) {
      await DatabaseHelper.instance
          .saveSetting('store_name', _userNameCtrl.text.trim());
      await DatabaseHelper.instance
          .saveSetting('store_phone', _fullInternationalPhone);
      if (!mounted) return;
      // الانتقال إلى شاشة الدخول الترحيبية لمدة 3 ثوانٍ ثم فتح البرنامج
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const WelcomeSplashScreen()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFDC2626),
          content: Text(
            'مفتاح التنشيط غير صحيح لمعرّف الجهاز هذا، تأكد من السريال أو راسل المطور أبو نبراس',
          ),
        ),
      );
    }
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    String? helperText,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      helperText: helperText,
      helperStyle: const TextStyle(
        color: Color(0xFF047857),
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
      labelStyle: const TextStyle(color: Color(0xFF4B5563), fontSize: 14.5),
      prefixIcon: Icon(icon, color: const Color(0xFF4B5563), size: 22),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF3F4F6),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF9CA3AF), width: 1.1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _primaryNavy, width: 1.8),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFECEFF3),
        appBar: AppBar(
          backgroundColor: _primaryNavy,
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 0,
          automaticallyImplyLeading: false,
          title: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              NebrasAppLogoWidget(size: 32),
              SizedBox(width: 10),
              Text(
                'تسجيل الدخول وتفعيل التطبيق',
                style: TextStyle(
                  fontSize: 18.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              // الشريط المتحرك في أعلى الصفحة من اليمين إلى اليسار
              const _ArabicMarqueeBanner(
                text:
                    'مرحبا بك عزيزنا المستخدم ، نرجو كتابة البيانات كما هو مطلوب منك ، وإرسالها للمطور / ابو نبراس أحمد البدوي ، ليتم تفعيل النظام المحاسبي بنجاح',
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // =======================================================
                      // البطاقة الأولى: الاسم + الدولة والهاتف + معرف الجهاز + الإرسال
                      // =======================================================
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7F8FA),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x0D000000),
                              blurRadius: 8,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'بيانات المستخدم',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1F2937),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // أولاً: الاسم (حروف عربية أو إنجليزية فقط)
                            TextField(
                              controller: _userNameCtrl,
                              textInputAction: TextInputAction.next,
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[\u0600-\u06FFa-zA-Z\s]'),
                                ),
                              ],
                              decoration: _fieldDecoration(
                                label: 'الاسم الكامل (حروف عربية أو إنجليزية فقط) *',
                                icon: Icons.person_outline_rounded,
                              ),
                            ),
                            const SizedBox(height: 12),

                            // ثانياً: مفتاح وشعار الدولة + رقم الهاتف
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _phoneCtrl,
                                    keyboardType: TextInputType.phone,
                                    textInputAction: TextInputAction.next,
                                    onChanged: _onPhoneChanged,
                                    decoration: _fieldDecoration(
                                      label: 'رقم الهاتف *',
                                      icon: Icons.smartphone_rounded,
                                      helperText:
                                          'الدولة: ${_selectedCountry.flag} ${_selectedCountry.name}',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                InkWell(
                                  onTap: _openCountryPickerDialog,
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    height: 52,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF3F4F6),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: const Color(0xFF9CA3AF),
                                        width: 1.1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          _selectedCountry.flag,
                                          style: const TextStyle(fontSize: 22),
                                        ),
                                        const SizedBox(width: 5),
                                        Directionality(
                                          textDirection: TextDirection.ltr,
                                          child: Text(
                                            _selectedCountry.formattedDial,
                                            style: const TextStyle(
                                              fontSize: 14.5,
                                              fontWeight: FontWeight.bold,
                                              color: _primaryNavy,
                                            ),
                                          ),
                                        ),
                                        const Icon(
                                          Icons.arrow_drop_down_rounded,
                                          color: Color(0xFF4B5563),
                                          size: 22,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // ثالثاً: معرّف الجهاز
                            const Text(
                              'معرّف الجهاز (Device ID)',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1F2937),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 13,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3F4F6),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFD1D5DB)),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: SelectableText(
                                      _deviceId,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 15.5,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.6,
                                        color: Color(0xFF111827),
                                      ),
                                    ),
                                  ),
                                  InkWell(
                                    onTap: () {
                                      Clipboard.setData(
                                          ClipboardData(text: _deviceId));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content: Text('تم نسخ معرّف الجهاز')),
                                      );
                                    },
                                    borderRadius: BorderRadius.circular(8),
                                    child: const Padding(
                                      padding: EdgeInsets.all(4),
                                      child: Icon(
                                        Icons.copy_rounded,
                                        color: _primaryNavy,
                                        size: 23,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),

                            // رابعاً: خيار إرسال المعلومات للمطور واتساب أو تليجرام
                            const Text(
                              'إرسال البيانات ومعرّف الجهاز للمطور:',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF374151),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFF16A34A),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(28),
                                      ),
                                    ),
                                    onPressed: _sendToDeveloperWhatsApp,
                                    icon: const Icon(Icons.chat_rounded, size: 19),
                                    label: const Text(
                                      'واتساب',
                                      style: TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFF0284C7),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(28),
                                      ),
                                    ),
                                    onPressed: _sendToDeveloperTelegram,
                                    icon: const Icon(Icons.send_rounded, size: 19),
                                    label: const Text(
                                      'تليجرام',
                                      style: TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // =======================================================
                      // البطاقة الثانية: لصق مفتاح التنشيط أو السريال + زر الدخول
                      // =======================================================
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7F8FA),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x0D000000),
                              blurRadius: 8,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'مفتاح التنشيط أو السريال المرسل من المطور',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1F2937),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // خامساً: خانة لصق مفتاح التنشيط / السريال
                            TextField(
                              controller: _keyCtrl,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _submitActivation(),
                              decoration: _fieldDecoration(
                                label: 'الصق مفتاح التنشيط أو السريال هنا *',
                                icon: Icons.vpn_key_outlined,
                                suffixIcon: IconButton(
                                  tooltip: 'لصق من الحافظة',
                                  icon: const Icon(
                                    Icons.content_paste_rounded,
                                    color: _primaryNavy,
                                  ),
                                  onPressed: _pasteSerialFromClipboard,
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),

                            // زر التفعيل والدخول
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: _primaryNavy,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                              ),
                              onPressed: _activating ? null : _submitActivation,
                              icon: const Icon(
                                Icons.verified_user_rounded,
                                size: 22,
                              ),
                              label: Text(
                                _activating
                                    ? 'جاري التحقق من السريال...'
                                    : 'تفعيل ودخول التطبيق',
                                style: const TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
