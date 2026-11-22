import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path/path.dart' as p;
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
  bool _dbReady = false;

  static const List<_ModuleItem> _modules = [
    _ModuleItem('نقطة البيع (POS)', Icons.point_of_sale, Color(0xFF1545B5)),
    _ModuleItem('إدارة الأصناف', Icons.inventory_2, Color(0xFF0D7C66)),
    _ModuleItem('فواتير المشتريات', Icons.shopping_cart, Color(0xFFD97706)),
    _ModuleItem('العملاء والموردين', Icons.people, Color(0xFF7C3AED)),
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
      if (!mounted) return;
      setState(() {
        _productsCount = products.length;
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
    if (moduleName == 'إدارة الأصناف') {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ProductsScreen()),
      );
      _refreshStats();
      return;
    }

    if (moduleName == 'نقطة البيع (POS)') {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PosScreen()),
      );
      _refreshStats();
      return;
    }

    if (moduleName == 'فواتير المشتريات') {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PurchasesScreen()),
      );
      _refreshStats();
      return;
    }

    if (moduleName == 'العملاء والموردين') {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ContactsScreen()),
      );
      _refreshStats();
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('وحدة "$moduleName" جاهزة للبرمجة في المرحلة القادمة'),
        behavior: SnackBarBehavior.floating,
      ),
    );
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
                  const Text(
                    'نظام نقاط البيع والمحاسبة الذكي',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _dbReady
                        ? 'قاعدة البيانات متصلة • عدد الأصناف: $_productsCount'
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
                    border: OutlineInputBorder(),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم حفظ فاتورة المشتريات $purNumber وتغذية المخزون'),
          behavior: SnackBarBehavior.floating,
        ),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم حفظ الفاتورة رقم $invNum وتحديث المخزون والحساب'),
          behavior: SnackBarBehavior.floating,
        ),
      );
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
