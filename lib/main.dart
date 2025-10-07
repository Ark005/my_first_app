import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru_RU', null);
  runApp(const BudgetApp());
}

// Модель транзакции — не изменилась
class Transaction {
  String title;
  double income;
  double expense;
  DateTime date;
  bool isRecurring;
  int order;

  Transaction({
    required this.title,
    this.income = 0.0,
    this.expense = 0.0,
    required this.date,
    this.isRecurring = false,
    this.order = 0,
  });

  String toStorageString() {
    return '${date.millisecondsSinceEpoch}|$title|$income|$expense|$isRecurring|$order';
  }

  static Transaction fromStorageString(String s) {
    final parts = s.split('|');
    final order = parts.length > 5 ? int.tryParse(parts[5]) ?? 0 : 0;
    return Transaction(
      date: DateTime.fromMillisecondsSinceEpoch(int.parse(parts[0])),
      title: parts[1],
      income: double.parse(parts[2]),
      expense: double.parse(parts[3]),
      isRecurring: parts.length > 4 ? parts[4] == 'true' : false,
      order: order,
    );
  }
}

class BudgetApp extends StatelessWidget {
  const BudgetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Бюджет',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
      ),
      home: const BudgetPage(),
    );
  }
}

class BudgetPage extends StatefulWidget {
  const BudgetPage({super.key});

  @override
  State<BudgetPage> createState() => _BudgetPageState();
}

class _BudgetPageState extends State<BudgetPage> {
  final List<Transaction> _transactions = [];
  final List<Transaction> _recurringExpenses = [];
  final List<Transaction> _recurringIncomes = [];

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _incomeController = TextEditingController();
  final TextEditingController _expenseController = TextEditingController();
  DateTime _selectedDate = DateTime.now();

  final TextEditingController _recTitleController = TextEditingController();
  final TextEditingController _recAmountController = TextEditingController();
  bool _isRecurringIncome = true;

  bool _isEditingRecurring = false;
  int? _editingRecurringIndex;
  bool _isEditingRecurringIsIncome = true;

  bool _isInitialized = false;

  // Два месяца: текущий и следующий
  late DateTime _currentMonth;
  late DateTime _nextMonth;

  @override
  void initState() {
    super.initState();
    _loadAndInit();
  }

  Future<void> _loadAndInit() async {
    await _loadTransactions();
    _setCurrentAndNextMonth();
    setState(() {
      _isInitialized = true;
    });
  }

  void _setCurrentAndNextMonth() {
    final now = DateTime.now();
    _currentMonth = DateTime(now.year, now.month, 1);
    _nextMonth = _addMonths(_currentMonth, 1);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _incomeController.dispose();
    _expenseController.dispose();
    _recTitleController.dispose();
    _recAmountController.dispose();
    super.dispose();
  }

  // === Сохранение и загрузка ===
  Future<void> _saveTransactions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('transactions', _transactions.map((tx) => tx.toStorageString()).toList());
    await prefs.setStringList('recurring_expenses', _recurringExpenses.map((tx) => tx.toStorageString()).toList());
    await prefs.setStringList('recurring_incomes', _recurringIncomes.map((tx) => tx.toStorageString()).toList());
  }

  Future<void> _loadTransactions() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList('transactions');
    final recExpData = prefs.getStringList('recurring_expenses');
    final recIncData = prefs.getStringList('recurring_incomes');

    if (data != null) {
      _transactions.clear();
      _transactions.addAll(data.map(Transaction.fromStorageString));
    }
    if (recExpData != null) {
      _recurringExpenses.clear();
      _recurringExpenses.addAll(recExpData.map(Transaction.fromStorageString));
    }
    if (recIncData != null) {
      _recurringIncomes.clear();
      _recurringIncomes.addAll(recIncData.map(Transaction.fromStorageString));
    }
  }

  // === Вспомогательные функции даты ===
  int _daysInMonth(int year, int month) {
    if (month == 2) return _isLeapYear(year) ? 29 : 28;
    return [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1];
  }

  bool _isLeapYear(int year) {
    return (year % 4 == 0) && (year % 100 != 0 || year % 400 == 0);
  }

  // === UI: выбор даты ===
  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      locale: const Locale('ru'),
    );
    if (picked != null) {
      setState(() { _selectedDate = picked; });
    }
  }

  // === Добавление обычной транзакции ===
  void _addTransaction() {
    final title = _titleController.text.trim();
    final income = double.tryParse(_incomeController.text) ?? 0.0;
    final expense = double.tryParse(_expenseController.text) ?? 0.0;
    if (title.isEmpty && income == 0.0 && expense == 0.0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Введите название или сумму')));
      return;
    }

    // Определяем, в какой из двух месяцев добавлять запись
    DateTime targetMonth;
    if (_selectedDate.year == _currentMonth.year && _selectedDate.month == _currentMonth.month) {
      targetMonth = _currentMonth;
    } else if (_selectedDate.year == _nextMonth.year && _selectedDate.month == _nextMonth.month) {
      targetMonth = _nextMonth;
    } else {
      targetMonth = _currentMonth;
    }

    final day = math.min(_selectedDate.day, _daysInMonth(targetMonth.year, targetMonth.month));
    final currentRegular = _transactions.where((tx) =>
        tx.date.year == targetMonth.year && tx.date.month == targetMonth.month && !tx.isRecurring);
    final maxOrder = currentRegular.isEmpty ? 0 : currentRegular.map((tx) => tx.order).reduce(math.max);

    setState(() {
      _transactions.add(Transaction(
        title: title.isEmpty ? 'Без названия' : title,
        income: income,
        expense: expense,
        date: DateTime(targetMonth.year, targetMonth.month, day),
        order: maxOrder + 1,
      ));
      _titleController.clear();
      _incomeController.clear();
      _expenseController.clear();
      _selectedDate = DateTime.now();
    });
    _saveTransactions();
  }

  // === Постоянные доходы/расходы ===
  void _addRecurring() {
    final title = _recTitleController.text.trim();
    final amount = double.tryParse(_recAmountController.text) ?? 0.0;
    if (title.isEmpty || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Укажите название и сумму > 0')));
      return;
    }

    final tx = Transaction(
      title: title,
      income: _isRecurringIncome ? amount : 0.0,
      expense: _isRecurringIncome ? 0.0 : amount,
      date: DateTime.now(),
      isRecurring: true,
    );

    setState(() {
      if (_isRecurringIncome) {
        _recurringIncomes.add(tx);
      } else {
        _recurringExpenses.add(tx);
      }
      _recTitleController.clear();
      _recAmountController.clear();
    });
    _saveTransactions();
  }

  void _editRecurring(int index, bool isIncome) {
    final list = isIncome ? _recurringIncomes : _recurringExpenses;
    final tx = list[index];
    _recTitleController.text = tx.title;
    _recAmountController.text = (isIncome ? tx.income : tx.expense).toString();
    _isRecurringIncome = isIncome;
    _isEditingRecurring = true;
    _editingRecurringIndex = index;
    _isEditingRecurringIsIncome = isIncome;
  }

  void _saveRecurringEdit() {
    if (_editingRecurringIndex == null) return;
    final title = _recTitleController.text.trim();
    final amount = double.tryParse(_recAmountController.text) ?? 0.0;
    if (title.isEmpty || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Укажите название и сумму > 0')));
      return;
    }

    final tx = Transaction(
      title: title,
      income: _isEditingRecurringIsIncome ? amount : 0.0,
      expense: _isEditingRecurringIsIncome ? 0.0 : amount,
      date: DateTime.now(),
      isRecurring: true,
    );

    setState(() {
      if (_isEditingRecurringIsIncome) {
        _recurringIncomes[_editingRecurringIndex!] = tx;
      } else {
        _recurringExpenses[_editingRecurringIndex!] = tx;
      }
      _cancelRecurringEdit();
    });
    _saveTransactions();
  }

  void _cancelRecurringEdit() {
    _isEditingRecurring = false;
    _editingRecurringIndex = null;
    _recTitleController.clear();
    _recAmountController.clear();
  }

  void _deleteRecurring(int index, bool isIncome) {
    setState(() {
      if (isIncome) {
        _recurringIncomes.removeAt(index);
      } else {
        _recurringExpenses.removeAt(index);
      }
    });
    _saveTransactions();
  }

  // === Удаление обычной транзакции ===
  void _deleteTransaction(Transaction tx) {
    setState(() { _transactions.remove(tx); });
    _saveTransactions();
  }

  // === Перенос транзакции между двумя месяцами ===
  Future<void> _moveTransactionToAnotherMonth(Transaction tx) async {
    final months = [_currentMonth, _nextMonth];
    final result = await showDialog<DateTime?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Перенести в месяц'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var month in months)
                  ListTile(
                    title: Text(DateFormat('MMMM yyyy', 'ru_RU').format(month)),
                    onTap: () => Navigator.of(ctx).pop(month),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(null), child: const Text('Отмена')),
        ],
      ),
    );

    if (result == null) return;

    final newDay = math.min(tx.date.day, _daysInMonth(result.year, result.month));
    final newTx = Transaction(
      title: tx.title,
      income: tx.income,
      expense: tx.expense,
      date: DateTime(result.year, result.month, newDay),
      isRecurring: tx.isRecurring,
      order: tx.order,
    );

    setState(() {
      _transactions.remove(tx);
      _transactions.add(newTx);
    });
    _saveTransactions();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Запись перенесена в ${DateFormat('MMMM yyyy', 'ru_RU').format(result)}')),
    );
  }

  // === Очистка всех данных ===
  Future<void> _clearAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Очистить все данные?'),
        content: const Text('Это действие удалит все транзакции и настройки.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Очистить', style: TextStyle(color: Colors.red))),
        ],
      ),
    ) ?? false;

    if (confirmed) {
      setState(() {
        _transactions.clear();
        _recurringExpenses.clear();
        _recurringIncomes.clear();
      });
      await _saveTransactions();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Все данные удалены')));
    }
  }

  // === Экспорт в CSV ===
  Future<void> _exportToCSV() async {
    final buffer = StringBuffer();
    buffer.writeln('"Дата","Название","Доход","Расход","Постоянная"');

    final allTxs = [
      ..._transactions,
      ..._recurringIncomes.map((tx) => Transaction(title: tx.title, income: tx.income, expense: 0.0, date: tx.date, isRecurring: true)),
      ..._recurringExpenses.map((tx) => Transaction(title: tx.title, income: 0.0, expense: tx.expense, date: tx.date, isRecurring: true)),
    ];

    for (final tx in allTxs) {
      final dateStr = DateFormat('dd.MM.yyyy', 'ru_RU').format(tx.date);
      buffer.writeln('"$dateStr","${tx.title}","${tx.income}","${tx.expense}","${tx.isRecurring ? 'Да' : 'Нет'}"');
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/budget_export.csv');
      await file.writeAsString(buffer.toString());

      if (Platform.isMacOS) {
        final user = Platform.environment['USER'] ?? 'Shared';
        final downloadsDir = Directory('/Users/$user/Downloads');
        if (await downloadsDir.exists()) {
          final publicFile = File('${downloadsDir.path}/budget_export.csv');
          await file.copy(publicFile.path);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Файл сохранён в Папку Загрузок')));
          return;
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Файл сохранён: ${file.path}')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка экспорта: $e')));
    }
  }

  // === Импорт из CSV ===
  Future<void> _importFromCSV() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv']);
      if (result == null) return;

      final file = File(result.files.single.path!);
      final lines = await file.readAsLines();
      if (lines.isEmpty) return;

      final List<Transaction> newTransactions = [];
      final List<Transaction> newRecurringIncomes = [];
      final List<Transaction> newRecurringExpenses = [];

      for (int i = 1; i < lines.length; i++) {
        List<String> cells = lines[i].contains(';') ? lines[i].split(';') : lines[i].split(',');
        if (cells.length < 5) continue;

        final dateStr = cells[0].trim().replaceAll('"', '');
        final title = cells[1].trim().replaceAll('"', '');
        final income = double.tryParse(cells[2].trim()) ?? 0.0;
        final expense = double.tryParse(cells[3].trim()) ?? 0.0;
        final isRecurring = cells[4].trim().replaceAll('"', '').toLowerCase() == 'да';

        DateTime? date;
        try {
          if (dateStr.contains('.')) {
            date = DateFormat('dd.MM.yyyy', 'ru_RU').parse(dateStr);
          } else if (dateStr.contains('-')) {
            date = DateFormat('yyyy-MM-dd').parse(dateStr);
          } else {
            continue;
          }
        } catch (e) {
          continue;
        }

        if (isRecurring) {
          if (income > 0) {
            newRecurringIncomes.add(Transaction(title: title, income: income, expense: 0.0, date: date, isRecurring: true));
          } else if (expense > 0) {
            newRecurringExpenses.add(Transaction(title: title, income: 0.0, expense: expense, date: date, isRecurring: true));
          }
        } else {
          newTransactions.add(Transaction(
            title: title,
            income: income,
            expense: expense,
            date: date,
            isRecurring: false,
            order: newTransactions.length,
          ));
        }
      }

      setState(() {
        _transactions.clear();
        _transactions.addAll(newTransactions);
        _recurringIncomes.clear();
        _recurringIncomes.addAll(newRecurringIncomes);
        _recurringExpenses.clear();
        _recurringExpenses.addAll(newRecurringExpenses);
      });

      await _saveTransactions();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Данные успешно импортированы из CSV')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка импорта: $e')));
    }
  }

  // === Перенос итога текущего месяца в следующий ===
  void _shiftCurrentMonthForward() {
    final currentTransactions = _transactions.where((tx) =>
        tx.date.year == _currentMonth.year && tx.date.month == _currentMonth.month).toList();

    if (currentTransactions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Нет записей для переноса')));
      return;
    }

    final balance = currentTransactions.fold(0.0, (sum, tx) => sum + tx.income - tx.expense);
    if (balance == 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Итог = 0, перенос не требуется')));
      return;
    }

    final transferTx = Transaction(
      title: 'Перенос с ${_getMonthNameInNominative(_currentMonth)}',
      income: balance > 0 ? balance : 0.0,
      expense: balance < 0 ? -balance : 0.0,
      date: DateTime(_nextMonth.year, _nextMonth.month, 1),
    );

    setState(() { _transactions.add(transferTx); });
    _saveTransactions();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Итог за ${_getMonthNameInNominative(_currentMonth)} перенесён в ${_getMonthNameInNominative(_nextMonth)}')),
    );
  }

  String _getMonthNameInNominative(DateTime date) {
    return '${DateFormat('MMMM', 'ru_RU').format(date)} ${date.year}';
  }

  DateTime _addMonths(DateTime date, int months) {
    final year = date.year + ((date.month + months - 1) ~/ 12);
    final month = ((date.month + months - 1) % 12) + 1;
    final day = date.day;
    final daysInNewMonth = _daysInMonth(year, month);
    final newDay = day > daysInNewMonth ? daysInNewMonth : day;
    return DateTime(year, month, newDay);
  }

  // === Виджет постоянной записи ===
  Widget _buildRecurringItem(Transaction tx, bool isIncome) {
    final txBalance = tx.income - tx.expense;
    return Card(
      key: ValueKey('recurring_${isIncome ? 'inc' : 'exp'}_${tx.title}_${tx.income}_${tx.expense}'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: const Icon(Icons.repeat, color: Colors.grey),
        title: Text(tx.title),
        subtitle: Text(DateFormat('dd MMMM yyyy', 'ru_RU').format(tx.date)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (tx.income > 0) Text('+${tx.income.toStringAsFixed(2)} ₽', style: const TextStyle(color: Colors.green)),
                if (tx.expense > 0) Text('-${tx.expense.toStringAsFixed(2)} ₽', style: const TextStyle(color: Colors.red)),
                Text('Итого: ${txBalance.toStringAsFixed(2)} ₽', style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: txBalance >= 0 ? Colors.green : Colors.red,
                )),
              ],
            ),
            const SizedBox(width: 12),
            IconButton(
              icon: const Icon(Icons.edit, size: 18, color: Colors.blue),
              onPressed: () {
                final index = isIncome
                    ? _recurringIncomes.indexWhere((r) => r.title == tx.title && r.income == tx.income)
                    : _recurringExpenses.indexWhere((r) => r.title == tx.title && r.expense == tx.expense);
                if (index != -1) _editRecurring(index, isIncome);
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete, size: 18, color: Colors.red),
              onPressed: () {
                final index = isIncome
                    ? _recurringIncomes.indexWhere((r) => r.title == tx.title && r.income == tx.income)
                    : _recurringExpenses.indexWhere((r) => r.title == tx.title && r.expense == tx.expense);
                if (index != -1) _deleteRecurring(index, isIncome);
              },
            ),
          ],
        ),
      ),
    );
  }

  // === Секция постоянных записей для конкретного месяца ===
  List<Widget> _buildRecurringSection(DateTime month) {
    final recurringItems = [
      ..._recurringIncomes.map((tx) => _buildRecurringItem(Transaction(
        title: tx.title, income: tx.income, expense: 0.0, date: DateTime(month.year, month.month, 1), isRecurring: true,
      ), true)),
      ..._recurringExpenses.map((tx) => _buildRecurringItem(Transaction(
        title: tx.title, income: 0.0, expense: tx.expense, date: DateTime(month.year, month.month, 1), isRecurring: true,
      ), false)),
    ];
    if (recurringItems.isEmpty) return [];
    return [
      const Divider(key: ValueKey('divider_recurring'), height: 1, thickness: 1),
      ...recurringItems,
      const SizedBox(key: ValueKey('spacer_after_recurring'), height: 8),
    ];
  }

  // === Действия с транзакцией (меню) ===
  void _showTransactionActions(Transaction tx) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.arrow_forward, color: Colors.blue),
              title: const Text('Перенести в другой месяц'),
              onTap: () {
                Navigator.of(ctx).pop();
                _moveTransactionToAnotherMonth(tx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Удалить'),
              onTap: () {
                Navigator.of(ctx).pop();
                _deleteTransaction(tx);
              },
            ),
          ],
        ),
      ),
    );
  }

  // === Секция для одного месяца (с ReorderableListView) ===
  Widget _buildMonthSection(DateTime month, String title) {
    final regularTransactions = _transactions
        .where((tx) => tx.date.year == month.year && tx.date.month == month.month && !tx.isRecurring)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    // Вычисляем баланс для итога
    final allForBalance = [
      ...regularTransactions,
      ..._recurringIncomes.map((tx) => Transaction(title: tx.title, income: tx.income, expense: 0, date: month, isRecurring: true)),
      ..._recurringExpenses.map((tx) => Transaction(title: tx.title, income: 0, expense: tx.expense, date: month, isRecurring: true)),
    ];
    final balance = allForBalance.fold(0.0, (sum, tx) => sum + tx.income - tx.expense);

    // Формируем список виджетов для ReorderableListView
    final allWidgets = [
      ..._buildRecurringSection(month),
      if (regularTransactions.isEmpty)
        // 🔑 ОБЯЗАТЕЛЬНО: добавляем key к placeholder-виджету!
        Center(
          key: const ValueKey('no_transactions_placeholder'),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text('Нет обычных транзакций за этот месяц'),
          ),
        )
      else
        for (int i = 0; i < regularTransactions.length; i++)
          Card(
            // 🔑 У каждой обычной транзакции тоже есть уникальный key
            key: ValueKey('tx_${regularTransactions[i].date.millisecondsSinceEpoch}_${regularTransactions[i].title}_${regularTransactions[i].order}'),
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ListTile(
              title: Text(regularTransactions[i].title),
              subtitle: Text(DateFormat('dd MMMM yyyy', 'ru_RU').format(regularTransactions[i].date)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (regularTransactions[i].income > 0)
                        Text('+${regularTransactions[i].income.toStringAsFixed(2)} ₽', style: const TextStyle(color: Colors.green)),
                      if (regularTransactions[i].expense > 0)
                        Text('-${regularTransactions[i].expense.toStringAsFixed(2)} ₽', style: const TextStyle(color: Colors.red)),
                      Text(
                        'Итого: ${(regularTransactions[i].income - regularTransactions[i].expense).toStringAsFixed(2)} ₽',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: (regularTransactions[i].income - regularTransactions[i].expense) >= 0 ? Colors.green : Colors.red,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.more_vert),
                    onPressed: () => _showTransactionActions(regularTransactions[i]),
                  ),
                ],
              ),
            ),
          ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        ),
        Expanded(
          child: ReorderableListView(
            padding: const EdgeInsets.only(bottom: 70),
            onReorder: (oldIndex, newIndex) {
              if (regularTransactions.isEmpty) return;
              if (oldIndex < 0 || oldIndex >= regularTransactions.length) return;
              if (newIndex < 0 || newIndex > regularTransactions.length) return;

              setState(() {
                if (newIndex > oldIndex) newIndex -= 1;
                if (newIndex < 0 || newIndex >= regularTransactions.length) return;

                final item = regularTransactions.removeAt(oldIndex);
                regularTransactions.insert(newIndex, item);
                for (int i = 0; i < regularTransactions.length; i++) {
                  regularTransactions[i].order = i;
                }

                // Обновляем глобальный список
                _transactions.removeWhere((tx) =>
                    tx.date.year == month.year && tx.date.month == month.month && !tx.isRecurring);
                _transactions.addAll(regularTransactions);
                _saveTransactions();
              });
            },
            children: allWidgets, // ✅ Теперь ВСЕ элементы имеют key
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('ИТОГО:'),
              Text(
                '${balance.toStringAsFixed(2)} ₽',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: balance >= 0 ? Colors.green : Colors.red,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // === Основной build ===
  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Бюджет'),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.upload_file), onPressed: _importFromCSV, tooltip: 'Импорт из CSV'),
          IconButton(icon: const Icon(Icons.download), onPressed: _exportToCSV, tooltip: 'Экспорт в CSV'),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'clear') _clearAllData();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'clear', child: Text('Очистить все данные')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward),
            onPressed: _shiftCurrentMonthForward,
            tooltip: 'Перенести итог текущего месяца в следующий',
          ),
        ],
      ),
      body: Column(
        children: [
          // Панель постоянных записей
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(child: TextField(controller: _recTitleController, decoration: const InputDecoration(hintText: 'Название постоянной записи'))),
                const SizedBox(width: 8),
                SizedBox(width: 80, child: TextField(controller: _recAmountController, keyboardType: TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(hintText: 'Сумма'))),
                const SizedBox(width: 8),
                Switch(
                  value: _isRecurringIncome,
                  onChanged: (value) => setState(() => _isRecurringIncome = value),
                  activeColor: Colors.green,
                  inactiveThumbColor: Colors.red,
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isEditingRecurring ? _saveRecurringEdit : _addRecurring,
                  child: Text(_isEditingRecurring ? 'Сохранить' : _isRecurringIncome ? 'Доход' : 'Расход'),
                ),
                if (_isEditingRecurring) ...[
                  const SizedBox(width: 8),
                  OutlinedButton(onPressed: _cancelRecurringEdit, child: const Text('Отмена')),
                ],
              ],
            ),
          ),

          const Divider(),

          // Панель обычных транзакций
          if (!_isEditingRecurring)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(child: TextField(controller: _titleController, decoration: const InputDecoration(hintText: 'Название'))),
                  const SizedBox(width: 8),
                  SizedBox(width: 80, child: TextField(controller: _incomeController, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'Доход'))),
                  const SizedBox(width: 8),
                  SizedBox(width: 80, child: TextField(controller: _expenseController, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'Расход'))),
                  const SizedBox(width: 8),
                  TextButton(onPressed: _selectDate, child: Text(DateFormat('dd.MM', 'ru_RU').format(_selectedDate))),
                  const SizedBox(width: 8),
                  ElevatedButton(onPressed: _addTransaction, child: const Icon(Icons.add)),
                ],
              ),
            ),

          // ДВА МЕСЯЦА РЯДОМ
          Expanded(
            child: Row(
              children: [
                Expanded(child: _buildMonthSection(_currentMonth, 'Текущий месяц')),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(child: _buildMonthSection(_nextMonth, 'Следующий месяц')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}