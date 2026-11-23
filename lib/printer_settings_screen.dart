import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef JsonMap = Map<String, dynamic>;

class PrinterSettingsModel {
  String invoiceFooterText;
  String a4ReportFooterText;
  int textHeightPosition;
  String printerType; // 'PDF', 'Bluetooth', 'WIFI', 'USB'
  String printerAddress;
  String thermalPaperSize; // '58mm', '80mm'
  int invoiceCopies;
  int thermalPrinterModel;
  int barcodePrinterModel;
  int paperCutCommand;
  int cashDrawerCommand;
  int fontSize;
  int rightMargin;
  int bottomMargin;

  // خيارات التبديل (Switches)
  bool showCustomerAddressAndPhone;
  bool showPreviousCustomerDebt;
  bool printProductNameSeparateRow;
  bool showExpiryDateInA4;
  bool showProductNumberInA4;
  bool showProductDescription;
  bool selectA4OnSendInvoice;
  bool printImmediatelyAfterSave;
  bool showTaxQrInInvoice;
  bool showProductImageInInvoice;

  // مسميات الفاتورة القابلة للتعديل
  String labelInvoiceTitle;
  String labelCustomer;
  String labelTotal;
  String labelPaid;
  String labelRemaining;

  PrinterSettingsModel({
    this.invoiceFooterText = '',
    this.a4ReportFooterText = '',
    this.textHeightPosition = 10,
    this.printerType = 'PDF',
    this.printerAddress = '',
    this.thermalPaperSize = '58mm',
    this.invoiceCopies = 1,
    this.thermalPrinterModel = 1,
    this.barcodePrinterModel = 1,
    this.paperCutCommand = 0,
    this.cashDrawerCommand = 0,
    this.fontSize = 20,
    this.rightMargin = 0,
    this.bottomMargin = 0,
    this.showCustomerAddressAndPhone = false,
    this.showPreviousCustomerDebt = false,
    this.printProductNameSeparateRow = false,
    this.showExpiryDateInA4 = false,
    this.showProductNumberInA4 = false,
    this.showProductDescription = false,
    this.selectA4OnSendInvoice = false,
    this.printImmediatelyAfterSave = false,
    this.showTaxQrInInvoice = false,
    this.showProductImageInInvoice = false,
    this.labelInvoiceTitle = 'فاتورة مبيعات',
    this.labelCustomer = 'العميل',
    this.labelTotal = 'الإجمالي',
    this.labelPaid = 'المدفوع',
    this.labelRemaining = 'المتبقي',
  });

  JsonMap toJson() => {
        'invoiceFooterText': invoiceFooterText,
        'a4ReportFooterText': a4ReportFooterText,
        'textHeightPosition': textHeightPosition,
        'printerType': printerType,
        'printerAddress': printerAddress,
        'thermalPaperSize': thermalPaperSize,
        'invoiceCopies': invoiceCopies,
        'thermalPrinterModel': thermalPrinterModel,
        'barcodePrinterModel': barcodePrinterModel,
        'paperCutCommand': paperCutCommand,
        'cashDrawerCommand': cashDrawerCommand,
        'fontSize': fontSize,
        'rightMargin': rightMargin,
        'bottomMargin': bottomMargin,
        'showCustomerAddressAndPhone': showCustomerAddressAndPhone,
        'showPreviousCustomerDebt': showPreviousCustomerDebt,
        'printProductNameSeparateRow': printProductNameSeparateRow,
        'showExpiryDateInA4': showExpiryDateInA4,
        'showProductNumberInA4': showProductNumberInA4,
        'showProductDescription': showProductDescription,
        'selectA4OnSendInvoice': selectA4OnSendInvoice,
        'printImmediatelyAfterSave': printImmediatelyAfterSave,
        'showTaxQrInInvoice': showTaxQrInInvoice,
        'showProductImageInInvoice': showProductImageInInvoice,
        'labelInvoiceTitle': labelInvoiceTitle,
        'labelCustomer': labelCustomer,
        'labelTotal': labelTotal,
        'labelPaid': labelPaid,
        'labelRemaining': labelRemaining,
      };

  factory PrinterSettingsModel.fromJson(JsonMap json) {
    return PrinterSettingsModel(
      invoiceFooterText: (json['invoiceFooterText'] ?? '').toString(),
      a4ReportFooterText: (json['a4ReportFooterText'] ?? '').toString(),
      textHeightPosition: (json['textHeightPosition'] ?? 10) as int,
      printerType: (json['printerType'] ?? 'PDF').toString(),
      printerAddress: (json['printerAddress'] ?? '').toString(),
      thermalPaperSize: (json['thermalPaperSize'] ?? '58mm').toString(),
      invoiceCopies: (json['invoiceCopies'] ?? 1) as int,
      thermalPrinterModel: (json['thermalPrinterModel'] ?? 1) as int,
      barcodePrinterModel: (json['barcodePrinterModel'] ?? 1) as int,
      paperCutCommand: (json['paperCutCommand'] ?? 0) as int,
      cashDrawerCommand: (json['cashDrawerCommand'] ?? 0) as int,
      fontSize: (json['fontSize'] ?? 20) as int,
      rightMargin: (json['rightMargin'] ?? 0) as int,
      bottomMargin: (json['bottomMargin'] ?? 0) as int,
      showCustomerAddressAndPhone: (json['showCustomerAddressAndPhone'] ?? false) as bool,
      showPreviousCustomerDebt: (json['showPreviousCustomerDebt'] ?? false) as bool,
      printProductNameSeparateRow: (json['printProductNameSeparateRow'] ?? false) as bool,
      showExpiryDateInA4: (json['showExpiryDateInA4'] ?? false) as bool,
      showProductNumberInA4: (json['showProductNumberInA4'] ?? false) as bool,
      showProductDescription: (json['showProductDescription'] ?? false) as bool,
      selectA4OnSendInvoice: (json['selectA4OnSendInvoice'] ?? false) as bool,
      printImmediatelyAfterSave: (json['printImmediatelyAfterSave'] ?? false) as bool,
      showTaxQrInInvoice: (json['showTaxQrInInvoice'] ?? false) as bool,
      showProductImageInInvoice: (json['showProductImageInInvoice'] ?? false) as bool,
      labelInvoiceTitle: (json['labelInvoiceTitle'] ?? 'فاتورة مبيعات').toString(),
      labelCustomer: (json['labelCustomer'] ?? 'العميل').toString(),
      labelTotal: (json['labelTotal'] ?? 'الإجمالي').toString(),
      labelPaid: (json['labelPaid'] ?? 'المدفوع').toString(),
      labelRemaining: (json['labelRemaining'] ?? 'المتبقي').toString(),
    );
  }

  static const String _storageKey = 'nebras_printer_settings_v1';

  static Future<PrinterSettingsModel> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return PrinterSettingsModel();
    try {
      final decoded = jsonDecode(raw) as JsonMap;
      return PrinterSettingsModel.fromJson(decoded);
    } catch (_) {
      return PrinterSettingsModel();
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(toJson()));
  }
}

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  PrinterSettingsModel _settings = PrinterSettingsModel();
  bool _loading = true;

  final _invoiceFooterCtrl = TextEditingController();
  final _a4FooterCtrl = TextEditingController();
  final _heightPosCtrl = TextEditingController(text: '10');
  final _printerAddressCtrl = TextEditingController();
  final _fontSizeCtrl = TextEditingController(text: '20');
  final _rightMarginCtrl = TextEditingController(text: '0');
  final _bottomMarginCtrl = TextEditingController(text: '0');

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    final loaded = await PrinterSettingsModel.load();
    if (!mounted) return;
    setState(() {
      _settings = loaded;
      _invoiceFooterCtrl.text = loaded.invoiceFooterText;
      _a4FooterCtrl.text = loaded.a4ReportFooterText;
      _heightPosCtrl.text = loaded.textHeightPosition.toString();
      _printerAddressCtrl.text = loaded.printerAddress;
      _fontSizeCtrl.text = loaded.fontSize.toString();
      _rightMarginCtrl.text = loaded.rightMargin.toString();
      _bottomMarginCtrl.text = loaded.bottomMargin.toString();
      _loading = false;
    });
  }

  @override
  void dispose() {
    _invoiceFooterCtrl.dispose();
    _a4FooterCtrl.dispose();
    _heightPosCtrl.dispose();
    _printerAddressCtrl.dispose();
    _fontSizeCtrl.dispose();
    _rightMarginCtrl.dispose();
    _bottomMarginCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    _settings.invoiceFooterText = _invoiceFooterCtrl.text.trim();
    _settings.a4ReportFooterText = _a4FooterCtrl.text.trim();
    _settings.textHeightPosition = int.tryParse(_heightPosCtrl.text.trim()) ?? 10;
    _settings.printerAddress = _printerAddressCtrl.text.trim();
    _settings.fontSize = int.tryParse(_fontSizeCtrl.text.trim()) ?? 20;
    _settings.rightMargin = int.tryParse(_rightMarginCtrl.text.trim()) ?? 0;
    _settings.bottomMargin = int.tryParse(_bottomMarginCtrl.text.trim()) ?? 0;

    await _settings.save();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حفظ إعدادات الطابعة بنجاح')),
    );
    Navigator.of(context).pop(_settings);
  }

  Future<void> _searchPrinterDialog() async {
    final tempCtrl = TextEditingController(text: _printerAddressCtrl.text);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('بحث عن طابعة (${_settings.printerType})'),
          content: TextField(
            controller: tempCtrl,
            decoration: const InputDecoration(
              labelText: 'أدخل عنوان الطابعة (IP أو MAC)',
              hintText: 'مثال: 192.168.1.100 أو 00:11:22:33:44:55',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, tempCtrl.text.trim()),
              child: const Text('اعتماد'),
            ),
          ],
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => _printerAddressCtrl.text = result);
    }
  }

  Future<void> _editInvoiceLabelsDialog() async {
    final titleCtrl = TextEditingController(text: _settings.labelInvoiceTitle);
    final customerCtrl = TextEditingController(text: _settings.labelCustomer);
    final totalCtrl = TextEditingController(text: _settings.labelTotal);
    final paidCtrl = TextEditingController(text: _settings.labelPaid);
    final remCtrl = TextEditingController(text: _settings.labelRemaining);

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تعديل مسميات الفاتورة'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'عنوان الفاتورة'),
                ),
                TextField(
                  controller: customerCtrl,
                  decoration: const InputDecoration(labelText: 'مسمى العميل'),
                ),
                TextField(
                  controller: totalCtrl,
                  decoration: const InputDecoration(labelText: 'مسمى الإجمالي'),
                ),
                TextField(
                  controller: paidCtrl,
                  decoration: const InputDecoration(labelText: 'مسمى المدفوع'),
                ),
                TextField(
                  controller: remCtrl,
                  decoration: const InputDecoration(labelText: 'مسمى المتبقي'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حفظ المسميات'),
            ),
          ],
        ),
      ),
    );

    if (saved == true && mounted) {
      setState(() {
        _settings.labelInvoiceTitle = titleCtrl.text.trim();
        _settings.labelCustomer = customerCtrl.text.trim();
        _settings.labelTotal = totalCtrl.text.trim();
        _settings.labelPaid = paidCtrl.text.trim();
        _settings.labelRemaining = remCtrl.text.trim();
      });
    }
  }

  Widget _buildRoundedField({
    required TextEditingController controller,
    String? hint,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    TextAlign textAlign = TextAlign.right,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      textAlign: textAlign,
      decoration: InputDecoration(
        hintText: hint,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        filled: true,
        fillColor: Colors.white,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF90A4AE), width: 1.3),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF0F2C7E), width: 1.6),
        ),
      ),
    );
  }

  Widget _buildNumberRow(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(label, style: const TextStyle(fontSize: 15)),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 5,
            child: _buildRoundedField(
              controller: controller,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownRow({
    required String label,
    required int value,
    required List<int> items,
    required ValueChanged<int?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 6,
            child: Text(label, style: const TextStyle(fontSize: 15)),
          ),
          Expanded(
            flex: 4,
            child: DropdownButton<int>(
              value: value,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              items: items
                  .map((e) => DropdownMenuItem<int>(
                        value: e,
                        child: Text(e.toString(), style: const TextStyle(fontSize: 16)),
                      ))
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchRow(String title, bool value, ValueChanged<bool> onChanged) {
    return Column(
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(title, style: const TextStyle(fontSize: 15)),
          value: value,
          onChanged: onChanged,
        ),
        const Divider(height: 1),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: AppBar(
          title: const Text(
            'إعدادات الطابعه',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 1. نص اسفل فاتورة البيع
                          const Text('نص اسفل فاتورة البيع', style: TextStyle(fontSize: 15)),
                          const SizedBox(height: 6),
                          _buildRoundedField(
                            controller: _invoiceFooterCtrl,
                            hint: 'نص اسفل فاتورة البيع',
                            maxLines: 2,
                          ),
                          const SizedBox(height: 14),

                          // 2. نص اسفل التقارير قياس A4
                          const Text('نص اسفل التقارير قياس A4', style: TextStyle(fontSize: 15)),
                          const SizedBox(height: 6),
                          _buildRoundedField(
                            controller: _a4FooterCtrl,
                            hint: 'نص اسفل التقارير قياس A4',
                            maxLines: 2,
                          ),
                          const SizedBox(height: 10),

                          // 3. موقع النص الارتفاع
                          _buildNumberRow('موقع النص الارتفاع', _heightPosCtrl),
                          const SizedBox(height: 8),

                          // 4. نوع الطابعه
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('نوع الطابعه', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                                _buildPrinterTypeRadio('PDF', 'A4'),
                                _buildPrinterTypeRadio('Bluetooth', '58/80mm'),
                                _buildPrinterTypeRadio('WIFI', '58/80mm'),
                                _buildPrinterTypeRadio('USB', '58/80mm'),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),

                          // 5. بحث + عنوان الطابعه
                          Row(
                            children: [
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.grey.shade300,
                                  foregroundColor: Colors.black87,
                                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                                ),
                                onPressed: _searchPrinterDialog,
                                child: const Text('بحث'),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildRoundedField(
                                  controller: _printerAddressCtrl,
                                  hint: 'عنوان الطابعه',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // 6. حجم ورق الطابعه الحراريه
                          Row(
                            children: [
                              const Expanded(
                                flex: 5,
                                child: Text('حجم ورق الطابعه الحراريه', style: TextStyle(fontSize: 15)),
                              ),
                              Expanded(
                                flex: 5,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Radio<String>(
                                      value: '58mm',
                                      groupValue: _settings.thermalPaperSize,
                                      onChanged: (v) => setState(() => _settings.thermalPaperSize = v ?? '58mm'),
                                    ),
                                    const Text('58mm'),
                                    Radio<String>(
                                      value: '80mm',
                                      groupValue: _settings.thermalPaperSize,
                                      onChanged: (v) => setState(() => _settings.thermalPaperSize = v ?? '80mm'),
                                    ),
                                    const Text('80mm'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Divider(),

                          // 7. القوائم المنسدلة بالترتيب
                          _buildDropdownRow(
                            label: 'عدد نسخ الفاتورة',
                            value: _settings.invoiceCopies,
                            items: const [1, 2, 3, 4, 5],
                            onChanged: (v) => setState(() => _settings.invoiceCopies = v ?? 1),
                          ),
                          _buildDropdownRow(
                            label: 'موديل الطابعه الحراريه',
                            value: _settings.thermalPrinterModel,
                            items: const [1, 2, 3, 4, 5],
                            onChanged: (v) => setState(() => _settings.thermalPrinterModel = v ?? 1),
                          ),
                          _buildDropdownRow(
                            label: 'موديل طابعة الباركود',
                            value: _settings.barcodePrinterModel,
                            items: const [1, 2, 3, 4, 5],
                            onChanged: (v) => setState(() => _settings.barcodePrinterModel = v ?? 1),
                          ),
                          _buildDropdownRow(
                            label: 'امر قص الورق',
                            value: _settings.paperCutCommand,
                            items: const [0, 1, 2, 3],
                            onChanged: (v) => setState(() => _settings.paperCutCommand = v ?? 0),
                          ),
                          _buildDropdownRow(
                            label: 'امر فتح الدرج',
                            value: _settings.cashDrawerCommand,
                            items: const [0, 1, 2, 3],
                            onChanged: (v) => setState(() => _settings.cashDrawerCommand = v ?? 0),
                          ),
                          const Divider(),

                          // 8. حجم الخط والهوامش
                          _buildNumberRow('حجم الخط', _fontSizeCtrl),
                          _buildNumberRow('الهامش الايمن', _rightMarginCtrl),
                          _buildNumberRow('الهامش الاسفل', _bottomMarginCtrl),
                          const SizedBox(height: 8),

                          // 9. مفاتيح التبديل (Switches) بالترتيب
                          _buildSwitchRow(
                            'اظهار عنوان العميل ورقم تلفونه في الفاتورة',
                            _settings.showCustomerAddressAndPhone,
                            (v) => setState(() => _settings.showCustomerAddressAndPhone = v),
                          ),
                          _buildSwitchRow(
                            'اظهار مديونيه العميل السابقه في الفاتورة',
                            _settings.showPreviousCustomerDebt,
                            (v) => setState(() => _settings.showPreviousCustomerDebt = v),
                          ),
                          _buildSwitchRow(
                            'طباعه اسم المنتج في صف مستقل',
                            _settings.printProductNameSeparateRow,
                            (v) => setState(() => _settings.printProductNameSeparateRow = v),
                          ),
                          _buildSwitchRow(
                            'عرض تاريخ الانتهاء في فاتورة المبيعات A4',
                            _settings.showExpiryDateInA4,
                            (v) => setState(() => _settings.showExpiryDateInA4 = v),
                          ),
                          _buildSwitchRow(
                            'عرض رقم المنتج في فاتورة المبيعات A4',
                            _settings.showProductNumberInA4,
                            (v) => setState(() => _settings.showProductNumberInA4 = v),
                          ),
                          _buildSwitchRow(
                            'اظهار وصف المنتج في الفاتورة',
                            _settings.showProductDescription,
                            (v) => setState(() => _settings.showProductDescription = v),
                          ),
                          _buildSwitchRow(
                            'اختيار قياس A4 عند ارسال فاتورة البيع',
                            _settings.selectA4OnSendInvoice,
                            (v) => setState(() => _settings.selectA4OnSendInvoice = v),
                          ),
                          _buildSwitchRow(
                            'طباعة الفاتورة مباشرة بعد الحفظ',
                            _settings.printImmediatelyAfterSave,
                            (v) => setState(() => _settings.printImmediatelyAfterSave = v),
                          ),
                          _buildSwitchRow(
                            'اظهار QR الضريبه في فاتوره البيع',
                            _settings.showTaxQrInInvoice,
                            (v) => setState(() => _settings.showTaxQrInInvoice = v),
                          ),
                          _buildSwitchRow(
                            'اظهار صورة المنتج في فاتورة البيع',
                            _settings.showProductImageInInvoice,
                            (v) => setState(() => _settings.showProductImageInInvoice = v),
                          ),

                          const SizedBox(height: 12),

                          // 10. تعديل مسميات الفاتورة
                          Row(
                            children: [
                              const Expanded(
                                child: Text('تعديل مسميات الفاتورة', style: TextStyle(fontSize: 15)),
                              ),
                              SizedBox(
                                width: 150,
                                height: 42,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.grey.shade300,
                                    foregroundColor: Colors.black87,
                                  ),
                                  onPressed: _editInvoiceLabelsDialog,
                                  child: const Text('تعديل'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),

                  // 11. زر الحفظ المثبت في الأسفل
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      border: Border(top: BorderSide(color: Colors.grey.shade400)),
                    ),
                    child: SizedBox(
                      height: 46,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey.shade300,
                          foregroundColor: Colors.black87,
                        ),
                        onPressed: _saveSettings,
                        child: const Text('حفظ', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildPrinterTypeRadio(String type, String sizeHint) {
    return InkWell(
      onTap: () => setState(() => _settings.printerType = type),
      child: Row(
        children: [
          Radio<String>(
            value: type,
            groupValue: _settings.printerType,
            onChanged: (v) => setState(() => _settings.printerType = v ?? 'PDF'),
          ),
          SizedBox(width: 90, child: Text(type, style: const TextStyle(fontSize: 15))),
          Text(sizeHint, style: const TextStyle(fontSize: 14, color: Colors.black54)),
        ],
      ),
    );
  }
}
