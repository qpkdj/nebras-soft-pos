import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
class BotReply {
  final String text;
  final List<String> suggestions;

  const BotReply({
    required this.text,
    this.suggestions = const [],
  });
}

class _BotIntent {
  final String id;
  final List<String> keywords;
  final String answer;
  final List<String> followUps;

  const _BotIntent({
    required this.id,
    required this.keywords,
    required this.answer,
    this.followUps = const [],
  });
}

class NebrasSmartBotEngine {
  static String _normalizeArabic(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
        .replaceAll(RegExp(r'[أإآ]'), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll('ؤ', 'و')
        .replaceAll('ئ', 'ي')
        .replaceAll(RegExp(r'[^\w\s\u0621-\u064A0-9]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static final List<_BotIntent> _knowledgeBase = [
    _BotIntent(
      id: 'welcome',
      keywords: [
        'مرحبا',
        'السلام',
        'هلا',
        'اهلا',
        'صباح',
        'مساء',
        'بدايه',
        'مساعده',
        'من انت'
      ],
      answer:
          'أهلاً بك في المساعد الذكي لنظام نبراس SofT المحاسبي (Nebras SofT Pos) 👋\n\n'
          'أنا هنا لمساعدتك خطوة بخطوة في:\n'
          '• إدارة نقطة البيع والفواتير (نقدي وآجل)\n'
          '• المخزون والباركود وتنبيهات النواقص\n'
          '• حسابات العملاء والموردين وسندات القبض والصرف\n'
          '• الطباعة الحرارية والنسخ الاحتياطي والتفعيل\n\n'
          'اكتب سؤالك مباشرة أو اختر من المواضيع بالأسفل:',
      followUps: [
        'كيف أبدأ البيع؟',
        'إضافة منتج وباركود',
        'إعداد الطابعة الحرارية',
        'النسخ الاحتياطي'
      ],
    ),
    _BotIntent(
      id: 'pos_sales',
      keywords: [
        'بيع',
        'مبيعات',
        'فاتوره',
        'كاشير',
        'نقطه البيع',
        'سله',
        'خصم',
        'مرتجع',
        'ارجاع'
      ],
      answer: '🛒 دليل نقطة البيع والمبيعات السريعة:\n\n'
          '1. إضافة الأصناف: امسح الباركود بالكاميرا أو قارئ الباركود، أو ابحث باسم الصنف في شريط البحث.\n'
          '2. تعديل الكمية والسعر: اضغط على الصنف داخل السلة لزيادة الكمية أو تطبيق خصم مباشر.\n'
          '3. الدفع النقدي والآجل:\n'
          '   • نقدي: اضغط "إتمام البيع" ليتم ترحيل المبلغ للصندوق فوراً.\n'
          '   • آجل (دين): اختر اسم العميل أولاً ثم اختر نوع الدفع "آجل" ليُقيد المبلغ تلقائياً في كشف حسابه.\n'
          '4. المرتجعات: من سجل الفواتير، افتح الفاتورة واختر "مرتجع" لإعادة الكمية للمخزون وتعديل الصندوق تلقائياً.',
      followUps: [
        'كيف أطبع الفاتورة؟',
        'حسابات العملاء والديون',
        'تقرير أرباح اليوم'
      ],
    ),
    _BotIntent(
      id: 'inventory_barcode',
      keywords: [
        'مخزون',
        'منتج',
        'صنف',
        'اصناف',
        'باركود',
        'جرد',
        'نواقص',
        'كميه',
        'تكلفه',
        'سعر الشراء'
      ],
      answer: '📦 إدارة المخزون والباركود:\n\n'
          '• إضافة صنف جديد: أدخل اسم الصنف، سعر الشراء (التكلفة)، سعر البيع، والكمية الحالية.\n'
          '• توليد باركود تلقائي: إذا لم يكن للمنتج باركود، اضغط زر "توليد باركود" ليقوم النظام بإنشاء كود فريد جاهز للطباعة واللصق.\n'
          '• تنبيهات النواقص: حدد "الحد الأدنى للطلب" لكل صنف، وسيقوم النظام بتنبيهك تلقائياً قبل نفاد الكمية.\n'
          '• دقة الأرباح: احرص دائماً على إدخال "سعر الشراء" بدقة لأن النظام يحسب صافي الربح بناءً على الفرق بين سعر البيع وسعر التكلفة.',
      followUps: [
        'كيف أبدأ البيع؟',
        'إعداد الطابعة الحرارية',
        'التقارير والأرباح'
      ],
    ),
    _BotIntent(
      id: 'customers_suppliers',
      keywords: [
        'عميل',
        'عملاء',
        'مورد',
        'موردين',
        'دين',
        'ديون',
        'اجل',
        'سند',
        'قبض',
        'صرف',
        'كشف حساب',
        'متبقي'
      ],
      answer: '📒 حسابات العملاء والموردين (الديون والآجل):\n\n'
          '• تسجيل دفعة من عميل (سند قبض): افتح ملف العميل واضغط "تسديد / سند قبض"، أدخل المبلغ المستلم وسيتم خصمه من دينه وإضافته للصندوق فوراً.\n'
          '• دفع مبلغ لمورد (سند صرف): من قائمة الموردين، اختر المورد وسجّل الدفعة ليتم خصمها من رصيده.\n'
          '• كشف حساب تفصيلي: يمكنك استعراض جميع فواتير ودفعات أي عميل أو مورد بالتاريخ والوقت، ومشاركته كملف PDF عبر واتساب بضغطة زر.',
      followUps: ['كيف أبدأ البيع؟', 'النسخ الاحتياطي', 'التقارير والأرباح'],
    ),
    _BotIntent(
      id: 'thermal_printing',
      keywords: [
        'طابعه',
        'طباعه',
        'بلوتوث',
        'حراريه',
        'ورق',
        'ايصال',
        'فاتوره pdf',
        'لا تطبع',
        'مشكله الطباعه'
      ],
      answer: '🖨️ إعداد وحل مشاكل الطباعة الحرارية:\n\n'
          '1. تأكد من تشغيل البلوتوث والموقع (GPS) في هاتفك (مطلوب في أندرويد للبحث عن الطابعات).\n'
          '2. قم بإقران الطابعة أولاً من إعدادات البلوتوث في الهاتف (الرمز الافتراضي غالباً 0000 أو 1234).\n'
          '3. افتح إعدادات الطباعة داخل التطبيق واختر الطابعة ومقاس الورق (58mm أو 80mm).\n'
          '4. إذا ظهرت حروف عربية مقطّعة: تأكد من تفعيل خيار "الطباعة كصورة (Image Mode)" من إعدادات الطباعة لضمان ظهور الخط العربي والشعار بوضوح تام.',
      followUps: ['كيف أبدأ البيع؟', 'التواصل مع الدعم الفني'],
    ),
    _BotIntent(
      id: 'backup_restore',
      keywords: [
        'نسخ',
        'احتياطي',
        'نسخه',
        'استعاده',
        'فرمته',
        'نقل',
        'حفظ البيانات',
        'ضياع',
        'سحابي',
        'جوجل درايف'
      ],
      answer: '☁️ النسخ الاحتياطي وحماية بياناتك:\n\n'
          '• النسخ المحلي: من قسم "النسخ الاحتياطي"، اضغط "إنشاء نسخة احتياطية" لحفظ قاعدة البيانات كاملة في ذاكرة الجهاز.\n'
          '• المشاركة الآمنة: ننصح يومياً بعد إغلاق المحل بمشاركة ملف النسخة الاحتياطية إلى حسابك الشخصي في واتساب أو تيليجرام أو Google Drive.\n'
          '• استعادة البيانات: عند تغيير الهاتف أو الفرمتة، ثبّت التطبيق واختر "استعادة نسخة احتياطية" وحدد آخر ملف قمت بحفظه لتعود جميع الأصناف والديون والفواتير كما كانت.',
      followUps: [
        'التفعيل والسريال',
        'التقارير والأرباح',
        'التواصل مع الدعم الفني'
      ],
    ),
    _BotIntent(
      id: 'reports_profits',
      keywords: [
        'تقرير',
        'تقارير',
        'ربح',
        'ارباح',
        'خساره',
        'مصروف',
        'مصروفات',
        'صندوق',
        'يومي',
        'شهري',
        'احصائيات'
      ],
      answer: '📊 التقارير المالية والأرباح:\n\n'
          '• ملخص اليوم / الفترة: يعرض إجمالي المبيعات (النقدي + الآجل)، إجمالي التكلفة، والمصروفات التشغيلية.\n'
          '• صافي الربح الحقيقي: يُحسب تلقائياً بالمعادلة:\n'
          '  (إجمالي المبيعات - تكلفة البضاعة المباعة) - المصروفات.\n'
          '• جرد الصندوق: يوضح المبلغ النقدي الفعلي الذي يجب أن يكون موجوداً في الدرج (المبيعات النقدية + سندات القبض - المصروفات وسندات الصرف).',
      followUps: ['النسخ الاحتياطي', 'إضافة منتج وباركود'],
    ),
    _BotIntent(
      id: 'activation_license',
      keywords: [
        'تفعيل',
        'سريال',
        'مفتاح',
        'ترخيص',
        'بصمه',
        'معرف الجهاز',
        'nsfp',
        'nsact',
        'انتهى',
        'اشتراك',
        'تجديد'
      ],
      answer: '🔐 نظام التفعيل والترخيص (Ed25519):\n\n'
          '• يرتبط التفعيل ببصمة جهازك الفريدة (NSFP-...) لضمان أمان نسختك.\n'
          '• لتفعيل التطبيق أو تجديد الاشتراك:\n'
          '  1. انسخ معرّف جهازك من شاشة التفعيل.\n'
          '  2. أرسله للمطور عبر واتساب أو تيليجرام.\n'
          '  3. ستستلم مفتاح التنشيط (NSACT-...)، انسخه بالكامل والصقه في خانة التفعيل.\n'
          '• تنبيه: لا تترك مسافات إضافية عند لصق السريال، وتأكد من ضبط تاريخ الهاتف بشكل صحيح.',
      followUps: ['التواصل مع الدعم الفني', 'النسخ الاحتياطي'],
    ),
    _BotIntent(
      id: 'support_contact',
      keywords: [
        'دعم',
        'تواصل',
        'مطور',
        'واتساب',
        'تيليجرام',
        'رقم',
        'مشكله',
        'خطا',
        'عطل',
        'ابو نبراس',
        'نبراس'
      ],
      answer: '📞 الدعم الفني والتواصل المباشر مع المطور:\n\n'
          '• المطور: م. أبو نبراس أحمد البدوي (فريق نبراس SofT)\n'
          '• واتساب: 735114406\n'
          '• تيليجرام: @softnebras\n\n'
          'عند التواصل بخصوص مشكلة تقنية، يُفضل إرسال لقطة شاشة للخطأ مع ذكر نوع الجهاز لتقديم الحل بشكل أسرع.',
      followUps: [
        'التفعيل والسريال',
        'النسخ الاحتياطي',
        'إعداد الطابعة الحرارية'
      ],
    ),
  ];

  static BotReply getReply(String userMessage) {
    final normalized = _normalizeArabic(userMessage);
    if (normalized.isEmpty) {
      return const BotReply(
        text: 'يرجى كتابة سؤالك أو اختيار موضوع من الاقتراحات بالأسفل.',
        suggestions: [
          'كيف أبدأ البيع؟',
          'إضافة منتج وباركود',
          'إعداد الطابعة الحرارية',
          'التواصل مع الدعم الفني'
        ],
      );
    }

    _BotIntent? bestIntent;
    int bestScore = 0;

    for (final intent in _knowledgeBase) {
      int score = 0;
      for (final rawKw in intent.keywords) {
        final kw = _normalizeArabic(rawKw);
        if (normalized == kw) {
          score += 5;
        } else if (normalized.contains(kw)) {
          score += kw.length >= 4 ? 3 : 2;
        }
      }
      if (score > bestScore) {
        bestScore = score;
        bestIntent = intent;
      }
    }

    if (bestIntent != null && bestScore > 0) {
      return BotReply(
        text: bestIntent.answer,
        suggestions: bestIntent.followUps,
      );
    }

    return const BotReply(
      text: 'لم أتمكن من تحديد قصدك بدقة 🤔\n\n'
          'يمكنك سؤالي عن أي موضوع يتعلق بالنظام مثل: المبيعات، المخزون، الباركود، الديون، الطباعة الحرارية، الأرباح، النسخ الاحتياطي، أو التفعيل.\n'
          'أو اختر أحد المواضيع الجاهزة بالأسفل:',
      suggestions: [
        'كيف أبدأ البيع؟',
        'حسابات العملاء والديون',
        'إعداد الطابعة الحرارية',
        'النسخ الاحتياطي',
        'التواصل مع الدعم الفني',
      ],
    );
  }
}

/// زر البوت العائم المتحرك بالسحب مع الالتصاق التلقائي بأقرب حافة
class FloatingDraggableBotButton extends StatefulWidget {
  final GlobalKey<NavigatorState>? navigatorKey;
  const FloatingDraggableBotButton({super.key, this.navigatorKey});

  @override
  State<FloatingDraggableBotButton> createState() =>
      _FloatingDraggableBotButtonState();
}

class _FloatingDraggableBotButtonState
    extends State<FloatingDraggableBotButton> {
  static const double _buttonSize = 58.0;
  static const double _edgeMargin = 8.0;

  Offset? _position;
  bool _isDragging = false;

  void _openBotChat(BuildContext context) {
    final navContext = widget.navigatorKey?.currentContext ?? context;
    showModalBottomSheet(
      context: navContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _NebrasBotChatSheet(),
    );
  }

  void _snapToNearestEdge(Size screenSize) {
    if (_position == null) return;
    final centerX = _position!.dx + (_buttonSize / 2);
    final snapToLeft = centerX < (screenSize.width / 2);
    final targetX = snapToLeft
        ? _edgeMargin
        : (screenSize.width - _buttonSize - _edgeMargin);

    setState(() {
      _isDragging = false;
      _position = Offset(targetX, _position!.dy);
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screenSize = media.size;
    final topPadding = media.padding.top + 12;
    final bottomPadding = media.padding.bottom + 16;

    // الموضع الافتراضي عند أول تشغيل (أسفل يسار الشاشة)
    _position ??= Offset(
      _edgeMargin,
      screenSize.height - _buttonSize - bottomPadding - 70,
    );

    return AnimatedPositioned(
      duration:
          _isDragging ? Duration.zero : const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      left: _position!.dx,
      top: _position!.dy,
      child: GestureDetector(
        onPanStart: (_) {
          setState(() => _isDragging = true);
        },
        onPanUpdate: (details) {
          setState(() {
            final newX = (_position!.dx + details.delta.dx).clamp(
              _edgeMargin,
              screenSize.width - _buttonSize - _edgeMargin,
            );
            final newY = (_position!.dy + details.delta.dy).clamp(
              topPadding,
              screenSize.height - _buttonSize - bottomPadding,
            );
            _position = Offset(newX, newY);
          });
        },
        onPanEnd: (_) => _snapToNearestEdge(screenSize),
        onPanCancel: () => _snapToNearestEdge(screenSize),
        onTap: () => _openBotChat(context),
        child: Material(
          color: Colors.transparent,
          elevation: 8,
          shape: const CircleBorder(),
          child: Container(
            width: _buttonSize,
            height: _buttonSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF0A1D56), Color(0xFF0D7C66)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: const Color(0xFFFEF08A), width: 1.8),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x550A1D56),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.smart_toy_rounded,
              color: Color(0xFFFEF08A),
              size: 30,
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatMessage {
  final String text;
  final bool isUser;
  final List<String> suggestions;

  const _ChatMessage({
    required this.text,
    required this.isUser,
    this.suggestions = const [],
  });
}

/// نافذة محادثة البوت المنبثقة
class _NebrasBotChatSheet extends StatefulWidget {
  const _NebrasBotChatSheet();

  @override
  State<_NebrasBotChatSheet> createState() => _NebrasBotChatSheetState();
}

class _NebrasBotChatSheetState extends State<_NebrasBotChatSheet> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];

  @override
  void initState() {
    super.initState();
    final welcome = NebrasSmartBotEngine.getReply('مرحبا');
    _messages.add(
      _ChatMessage(
        text: welcome.text,
        isUser: false,
        suggestions: welcome.suggestions,
      ),
    );
  }

  void _sendMessage(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final reply = NebrasSmartBotEngine.getReply(trimmed);
    setState(() {
      _messages.add(_ChatMessage(text: trimmed, isUser: true));
      _messages.add(
        _ChatMessage(
          text: reply.text,
          isUser: false,
          suggestions: reply.suggestions,
        ),
      );
    });

    _controller.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.78,
        decoration: const BoxDecoration(
          color: Color(0xFFF4F6FA),
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            children: [
              // رأس النافذة
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF0A1D56),
                      Color(0xFF0F2C7E),
                      Color(0xFF0D7C66)
                    ],
                  ),
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(22)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.smart_toy_rounded,
                        color: Color(0xFFFEF08A), size: 26),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'مساعد نبراس SofT الذكي',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // قائمة الرسائل
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final msg = _messages[index];
                    return Column(
                      crossAxisAlignment: msg.isUser
                          ? CrossAxisAlignment.start
                          : CrossAxisAlignment.end,
                      children: [
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 5),
                          padding: const EdgeInsets.all(12),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.82,
                          ),
                          decoration: BoxDecoration(
                            color: msg.isUser
                                ? const Color(0xFF0F2C7E)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x14000000),
                                blurRadius: 5,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            msg.text,
                            style: TextStyle(
                              color: msg.isUser
                                  ? Colors.white
                                  : const Color(0xFF1E293B),
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                        ),
                        if (!msg.isUser && msg.suggestions.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 8),
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: msg.suggestions.map((s) {
                                return ActionChip(
                                  label: Text(
                                    s,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      color: Color(0xFF0F2C7E),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  backgroundColor: const Color(0xFFE0E7FF),
                                  side: BorderSide.none,
                                  onPressed: () => _sendMessage(s),
                                );
                              }).toList(),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),

              // شريط الكتابة والإرسال
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                color: Colors.white,
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        textInputAction: TextInputAction.send,
                        onSubmitted: _sendMessage,
                        decoration: InputDecoration(
                          hintText: 'اكتب سؤالك هنا...',
                          filled: true,
                          fillColor: const Color(0xFFF1F5F9),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    CircleAvatar(
                      backgroundColor: const Color(0xFF0D7C66),
                      child: IconButton(
                        icon: const Icon(Icons.send_rounded,
                            color: Colors.white, size: 20),
                        onPressed: () => _sendMessage(_controller.text),
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
