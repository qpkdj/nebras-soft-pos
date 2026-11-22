import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/database/database_helper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NebrasPosApp());
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

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _productsCount = 0;
  bool _dbReady = false;

  @override
  void initState() {
    super.initState();
    _initDatabase();
  }

  Future<void> _initDatabase() async {
    final products = await DatabaseHelper.instance.queryAllProducts();
    if (!mounted) return;
    setState(() {
      _productsCount = products.length;
      _dbReady = true;
    });
  }

  void _showComingSoon(String moduleName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('وحدة "$moduleName" جاهزة للبرمجة في المرحلة القادمة'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final modules = [
      ('نقطة البيع (POS)', Icons.point_of_sale, const Color(0xFF1545B5)),
      ('إدارة الأصناف', Icons.inventory_2, const Color(0xFF0D7C66)),
      ('فواتير المشتريات', Icons.shopping_cart, const Color(0xFFD97706)),
      ('العملاء والموردين', Icons.people, const Color(0xFF7C3AED)),
      ('التقارير والأرباح', Icons.bar_chart, const Color(0xFFDC2626)),
      ('النسخ الاحتياطي', Icons.settings_backup_restore, const Color(0xFF334155)),
    ];

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
                itemCount: modules.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: 1.15,
                ),
                itemBuilder: (context, index) {
                  final item = modules[index];
                  return Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _showComingSoon(item.$1),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            radius: 26,
                            backgroundColor: item.$3.withAlpha(30),
                            child: Icon(item.$2, color: item.$3, size: 28),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            item.$1,
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

