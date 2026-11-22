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
      version: 1,
      onCreate: _createDB,
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
        name $textType,
        phone $textNullable,
        type $textType,
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
