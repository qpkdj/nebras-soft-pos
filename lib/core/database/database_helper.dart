import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

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
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';
    const textNullable = 'TEXT';
    const intType = 'INTEGER NOT NULL';
    const doubleType = 'REAL NOT NULL';
    const doubleDefaultZero = 'REAL NOT NULL DEFAULT 0.0';

    // 1. جدول المجموعات / التصنيفات
    await db.execute('''
      CREATE TABLE categories (
        id $idType,
        name $textType,
        color $textNullable
      )
    ''');

    // 2. جدول الأصناف (المخزون)
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

    // 3. جدول العملاء والموردين
    await db.execute('''
      CREATE TABLE contacts (
        id $idType,
        name $textType,
        phone $textNullable,
        type $textType,
        balance $doubleDefaultZero
      )
    ''');

    // 4. جدول الفواتير
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

    // 5. تفاصيل الفواتير
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

    // 6. جدول السندات (قبض وصرف)
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

    // 7. إعدادات النظام
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

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {}

  Future<int> insertProduct(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert(
      'products',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List>> queryAllProducts() async {
    final db = await instance.database;
    return await db.query('products', where: 'is_active = 1');
  }

  Future<int> updateProduct(Map<String, dynamic> row) async {
    final db = await instance.database;
    final int id = row['id'];
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

  Future close() async {
    final db = _database;
    if (db != null) {
      await db.close();
    }
  }
}

