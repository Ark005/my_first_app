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

class _BudgetPageState extends State<BudgetPage> with TickerProviderStateMixin {
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

  late TabController _tabController;
  List<DateTime> _months = [];
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _loadAndInit();
  }

  Future<void> _loadAndInit() async {
    await _loadTransactions();
    _buildMonthTabs();
    _tabController = TabController(length: _months.length, vsync: this);
    final now = DateTime.now();
    final currentIndex = _months.indexWhere((m) => m.year == now.year && m.month == now.month);
    if (currentIndex != -1) {
      _tabController.index = currentIndex;
    }
    _tabController.addListener(_handleTabChange);
    setState(() {
      _isInitialized = true;
    });
  }

  void _handleTabChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    _titleController.dispose();
    _incomeController.dispose();
    _expenseController.dispose();
    _recTitleController.dispose();
    _recAmountController.dispose();
    super.dispose();
  }

  Future<void> _saveTransactions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'transactions',
      _transactions.map((tx) => tx.toStorageString()).toList(),
    );
    await prefs.setStringList(
      'recurring_expenses',
      _recurringExpenses.map((tx) => tx.toStorageString()).toList(),
    );
    await prefs.setStringList(
      'recurring_incomes',
      _recurringIncomes.map((tx) => tx.toStorageString()).toList(),
    );
  }

  Future<void> _loadTransactions() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? data = prefs.getStringList('transactions');
    final List<String>? recExpData = prefs.getStringList('recurring_expenses');
    final List<String>? recIncData = prefs.getStringList('recurring_incomes');

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

  void _buildMonthTabs() {
    final now = DateTime.now();
    final currentYear = now.year;
    _months = List.generate(12, (index) {
      return DateTime(currentYear, index + 1, 1);
    });
  }

  int _daysInMonth(int year, int month) {
    if (month == 2) {
      return _isLeapYear(year) ? 29 : 28;
    }
    return [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1];
  }

  bool _isLeapYear(int year) {
    return (year % 4 == 0) && (year % 100 != 0 || year % 400 == 0);
  }

  DateTime _addMonths(DateTime date, int months) {
    final year = date.year + ((date.month + months - 1) ~/ 12);
    final month = ((date.month + months - 1) % 12) + 1;
    final day = date.day;
    final daysInNewMonth = _daysInMonth(year, month);
    final newDay = day > daysInNewMonth ? daysInNewMonth : day;
    return DateTime(year, month, newDay);
  }

  // ✅ ФОРМАТ МЕСЯЦА: "январь", "февраль" (именительный падеж, строчные)
  String _formatMonthName(DateTime date) {
    return DateFormat('MMMM', 'ru_RU').format(date).toLowerCase();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      locale: const Locale('ru'),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  void _addTransaction() {
    final title = _titleController.text.trim();
    final income = double.tryParse(_incomeController.text) ?? 0.0;
    final expense = double.tryParse(_expenseController.text) ?? 0.0;
    if (title.isEmpty && income == 0.0 && expense == 0.0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите название или сумму')),
      );
      return;
    }

    final currentMonth = _months[_tabController.index];
    final now = DateTime.now();
    final day = now.day <= _daysInMonth(currentMonth.year, currentMonth.month)
        ? now.day
        : _daysInMonth(currentMonth.year, currentMonth.month);

    final currentRegular = _transactions.where((tx) =>
        tx.date.year == currentMonth.year &&
        tx.date.month == currentMonth.month &&
        !tx.isRecurring);
    final maxOrder = currentRegular.isEmpty ? 0 : currentRegular.map((tx) => tx.order).reduce(math.max);

    setState(() {
      _transactions.add(
        Transaction(
          title: title.isEmpty ? 'Без названия' : title,
          income: income,
          expense: expense,
          date: _selectedDate.year == currentMonth.year && _selectedDate.month == currentMonth.month
              ? _selectedDate
              : DateTime(currentMonth.year, currentMonth.month, day),
          order: maxOrder + 1,
        ),
      );
      _titleController.clear();
      _incomeController.clear();
      _expenseController.clear();
      _selectedDate = DateTime.now();
    });
    _saveTransactions();
  }

  void _addRecurring() {
    final title = _recTitleController.text.trim();
    final amount = double.tryParse(_recAmountController.text) ?? 0.0;
    if (title.isEmpty || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Укажите название и сумму > 0')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Укажите название и сумму > 0')),
      );
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

  void _deleteTransaction(Transaction tx) {
    setState(() {
      _transactions.remove(tx);
    });
    _saveTransactions();
  }

  // ✅ ПЕРЕНОС ЗАПИСИ В ДРУГОЙ МЕСЯЦ
  Future<void> _moveTransactionToAnotherMonth(Transaction tx) async {
    final now = DateTime.now();
    final months = List.generate(12, (i) => DateTime(now.year, i + 1, 1));

    final result = await showDialog<DateTime?>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Перенести в месяц'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var month in months)
                    ListTile(
                      title: Text(_formatMonthName(month)), // ✅ "январь", "февраль"
                      onTap: () => Navigator.of(ctx).pop(month),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Отмена'),
            ),
          ],
        );
      },
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
      SnackBar(content: Text('Запись перенесена в ${_formatMonthName(result)}')),
    );
  }

  Future<void> _clearAllData() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Очистить все данные?'),
            content: const Text('Это действие удалит все транзакции и настройки.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Отмена'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Очистить', style: TextStyle(color: Colors.red)),
              ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Все данные удалены')),
      );
    }
  }

  // ✅ ЭКСПОРТ В CSV (УПРОЩЁННЫЙ)
  Future<void> _exportToCSV() async {
    try {
      final buffer = StringBuffer();
      buffer.writeln('"Дата","Название","Доход","Расход","Постоянная"');

      final allTxs = [
        ..._transactions,
        ..._recurringIncomes.map((tx) => Transaction(
              title: tx.title,
              income: tx.income,
              expense: 0.0,
              date: tx.date,
              isRecurring: true,
            )),
        ..._recurringExpenses.map((tx) => Transaction(
              title: tx.title,
              income: 0.0,
              expense: tx.expense,
              date: tx.date,
              isRecurring: true,
            )),
      ];

      for (final tx in allTxs) {
        final dateStr = DateFormat('dd.MM.yyyy', 'ru_RU').format(tx.date);
        buffer.writeln(
          '"$dateStr","${tx.title}","${tx.income}","${tx.expense}","${tx.isRecurring ? 'Да' : 'Нет'}"',
        );
      }

      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/budget_export.csv');
      await file.writeAsString(buffer.toString());

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Экспорт завершён. Файл: ${file.path}')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка экспорта: $e')),
      );
    }
  }

  Future<void> _importFromCSV() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result == null) return;

      final file = File(result.files.single.path!);
      final lines = await file.readAsLines();

      if (lines.isEmpty) return;

      final List<Transaction> newTransactions = [];
      final List<Transaction> newRecurringIncomes = [];
      final List<Transaction> newRecurringExpenses = [];

      for (int i = 1; i < lines.length; i++) {
        List<String> cells;
        if (lines[i].contains(';')) {
          cells = lines[i].split(';');
        } else {
          cells = lines[i].split(',');
        }

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
            newRecurringIncomes.add(Transaction(
              title: title,
              income: income,
              expense: 0.0,
              date: date,
              isRecurring: true,
            ));
          } else if (expense > 0) {
            newRecurringExpenses.add(Transaction(
              title: title,
              income: 0.0,
              expense: expense,
              date: date,
              isRecurring: true,
            ));
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Данные успешно импортированы из CSV')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка импорта: $e')),
      );
    }
  }

  // ✅ ПЕРЕНОС ИТОГА ТЕКУЩЕГО МЕСЯЦА В СЛЕДУЮЩИЙ
  void _shiftCurrentMonthForward() {
    final currentMonth = _months[_tabController.index];
    final currentTransactions = _transactions.where((tx) =>
        tx.date.year == currentMonth.year &&
        tx.date.month == currentMonth.month
    ).toList();

    if (currentTransactions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет записей для переноса')),
      );
      return;
    }

    final balance = currentTransactions.fold(0.0, (sum, tx) => sum + tx.income - tx.expense);
    if (balance == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Итог = 0, перенос не требуется')),
      );
      return;
    }

    final nextMonth = _addMonths(currentMonth, 1);
    final transferTx = Transaction(
      title: 'Перенос с ${_formatMonthName(currentMonth)}',
      income: balance > 0 ? balance : 0.0,
      expense: balance < 0 ? -balance : 0.0,
      date: DateTime(nextMonth.year, nextMonth.month, 1),
    );

    setState(() {
      _transactions.add(transferTx);
    });
    _saveTransactions();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Итог за ${_formatMonthName(currentMonth)} перенесён в ${_formatMonthName(nextMonth)}')),
    );
  }

  Widget _buildRecurringItem(Transaction tx, bool isIncome) {
    final txBalance = tx.income - tx.expense;
    final key = ValueKey('recurring_${isIncome ? 'inc' : 'exp'}_${tx.title}_${tx.income}_${tx.expense}');
    return Card(
      key: key,
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
                if (tx.income > 0)
                  Text('+${tx.income.toStringAsFixed(2)} ₽',
                      style: const TextStyle(color: Colors.green)),
                if (tx.expense > 0)
                  Text('-${tx.expense.toStringAsFixed(2)} ₽',
                      style: const TextStyle(color: Colors.red)),
                Text(
                  'Итого: ${txBalance.toStringAsFixed(2)} ₽',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: txBalance >= 0 ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            IconButton(
              icon: const Icon(Icons.edit, size: 18, color: Colors.blue),
              onPressed: () {
                final index = isIncome
                    ? _recurringIncomes.indexWhere((r) =>
                        r.title == tx.title && r.income == tx.income)
                    : _recurringExpenses.indexWhere((r) =>
                        r.title == tx.title && r.expense == tx.expense);
                if (index != -1) {
                  _editRecurring(index, isIncome);
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete, size: 18, color: Colors.red),
              onPressed: () {
                final index = isIncome
                    ? _recurringIncomes.indexWhere((r) =>
                        r.title == tx.title && r.income == tx.income)
                    : _recurringExpenses.indexWhere((r) =>
                        r.title == tx.title && r.expense == tx.expense);
                if (index != -1) {
                  _deleteRecurring(index, isIncome);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildRecurringSection(DateTime month) {
    final recurringItems = [
      ..._recurringIncomes.map((tx) {
        return Transaction(
          title: tx.title,
          income: tx.income,
          expense: 0.0,
          date: DateTime(month.year, month.month, 1),
          isRecurring: true,
        );
      }).map((tx) => _buildRecurringItem(tx, true)),
      ..._recurringExpenses.map((tx) {
        return Transaction(
          title: tx.title,
          income: 0.0,
          expense: tx.expense,
          date: DateTime(month.year, month.month, 1),
          isRecurring: true,
        );
      }).map((tx) => _buildRecurringItem(tx, false)),
    ];
    if (recurringItems.isEmpty) {
      return [];
    }
    return [
      const Divider(key: ValueKey('divider_recurring'), height: 1, thickness: 1),
      ...recurringItems,
      const SizedBox(key: ValueKey('spacer_after_recurring'), height: 8),
    ];
  }

  void _showTransactionActions(Transaction tx) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
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
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Текущий месяц (выбранный в табе)
    final currentMonth = _months[_tabController.index];
    // Следующий месяц
    final nextMonth = _addMonths(currentMonth, 1);

    final today = DateTime.now();

    // Транзакции для текущего месяца
    final regularTransactionsCurrent = _transactions
        .where((tx) =>
            tx.date.year == currentMonth.year &&
            tx.date.month == currentMonth.month &&
            !tx.isRecurring)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    // Транзакции для следующего месяца
    final regularTransactionsNext = _transactions
        .where((tx) =>
            tx.date.year == nextMonth.year &&
            tx.date.month == nextMonth.month &&
            !tx.isRecurring)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    // Постоянные записи для текущего месяца
    final recurringExpensesCurrent = _recurringExpenses.map((tx) {
      return Transaction(
        title: tx.title,
        income: 0.0,
        expense: tx.expense,
        date: DateTime(currentMonth.year, currentMonth.month, 1),
        isRecurring: true,
      );
    }).toList();

    final recurringIncomesCurrent = _recurringIncomes.map((tx) {
      return Transaction(
        title: tx.title,
        income: tx.income,
        expense: 0.0,
        date: DateTime(currentMonth.year, currentMonth.month, 1),
        isRecurring: true,
      );
    }).toList();

    // Постоянные записи для следующего месяца
    final recurringExpensesNext = _recurringExpenses.map((tx) {
      return Transaction(
        title: tx.title,
        income: 0.0,
        expense: tx.expense,
        date: DateTime(nextMonth.year, nextMonth.month, 1),
        isRecurring: true,
      );
    }).toList();

    final recurringIncomesNext = _recurringIncomes.map((tx) {
      return Transaction(
        title: tx.title,
        income: tx.income,
        expense: 0.0,
        date: DateTime(nextMonth.year, nextMonth.month, 1),
        isRecurring: true,
      );
    }).toList();

    // Итоги
    final balanceCurrent = [...regularTransactionsCurrent, ...recurringExpensesCurrent, ...recurringIncomesCurrent]
        .fold(0.0, (sum, tx) => sum + tx.income - tx.expense);
    final balanceNext = [...regularTransactionsNext, ...recurringExpensesNext, ...recurringIncomesNext]
        .fold(0.0, (sum, tx) => sum + tx.income - tx.expense);

    return DefaultTabController(
      length: _months.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Бюджет'),
          centerTitle: true,
          bottom: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabs: _months.map((month) {
              return Tab(text: DateFormat('MMM yyyy', 'ru_RU').format(month));
            }).toList(),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.upload_file),
              onPressed: _importFromCSV,
              tooltip: 'Импорт из CSV',
            ),
            IconButton(
              icon: const Icon(Icons.download),
              onPressed: _exportToCSV,
              tooltip: 'Экспорт в CSV',
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'clear') {
                  _clearAllData();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'clear',
                  child: Text('Очистить все данные'),
                ),
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
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _recTitleController,
                      decoration: const InputDecoration(hintText: 'Название постоянной записи'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 80,
                    child: TextField(
                      controller: _recAmountController,
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(hintText: 'Сумма'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Switch(
                    value: _isRecurringIncome,
                    onChanged: (value) {
                      setState(() {
                        _isRecurringIncome = value;
                      });
                    },
                    activeColor: Colors.green,
                    inactiveThumbColor: Colors.red,
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _isEditingRecurring ? _saveRecurringEdit : _addRecurring,
                    child: Text(_isEditingRecurring
                        ? 'Сохранить'
                        : _isRecurringIncome
                            ? 'Доход'
                            : 'Расход'),
                  ),
                  if (_isEditingRecurring) ...[
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _cancelRecurringEdit,
                      child: const Text('Отмена'),
                    ),
                  ],
                ],
              ),
            ),

            const Divider(),

            if (!_isEditingRecurring)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _titleController,
                        decoration: const InputDecoration(hintText: 'Название'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 80,
                      child: TextField(
                        controller: _incomeController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(hintText: 'Доход'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 80,
                      child: TextField(
                        controller: _expenseController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(hintText: 'Расход'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _selectDate,
                      child: Text(DateFormat('dd.MM', 'ru_RU').format(_selectedDate)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _addTransaction,
                      child: const Icon(Icons.add),
                    ),
                  ],
                ),
              ),

            // ✅ ДВА МЕСЯЦА РЯДОМ С РЕАЛЬНЫМИ НАЗВАНИЯМИ
            Expanded(
              child: Row(
                children: [
                  // Текущий месяц
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Text(
                            _formatMonthName(currentMonth), // ✅ "январь"
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                          ),
                        ),
                        Expanded(
                          child: ReorderableListView(
                            padding: const EdgeInsets.only(bottom: 70),
                            onReorder: (oldIndex, newIndex) {
                              if (regularTransactionsCurrent.isEmpty) return;
                              if (oldIndex < 0 || oldIndex >= regularTransactionsCurrent.length) return;
                              if (newIndex < 0 || newIndex > regularTransactionsCurrent.length) return;

                              setState(() {
                                if (newIndex > oldIndex) {
                                  newIndex -= 1;
                                }
                                if (newIndex < 0 || newIndex >= regularTransactionsCurrent.length) return;

                                final item = regularTransactionsCurrent.removeAt(oldIndex);
                                regularTransactionsCurrent.insert(newIndex, item);

                                for (int i = 0; i < regularTransactionsCurrent.length; i++) {
                                  regularTransactionsCurrent[i].order = i;
                                }

                                _transactions.removeWhere((tx) =>
                                    tx.date.year == currentMonth.year &&
                                    tx.date.month == currentMonth.month &&
                                    !tx.isRecurring);
                                _transactions.addAll(regularTransactionsCurrent);
                                _saveTransactions();
                              });
                            },
                            children: [
                              ..._buildRecurringSection(currentMonth),
                              if (regularTransactionsCurrent.isEmpty)
                                const Center(
                                  key: ValueKey('no_transactions_current'),
                                  child: Padding(
                                    padding: EdgeInsets.all(16.0),
                                    child: Text('Нет обычных транзакций'),
                                  ),
                                )
                              else
                                for (int i = 0; i < regularTransactionsCurrent.length; i++)
                                  Card(
                                    key: ValueKey('tx_current_${regularTransactionsCurrent[i].date.millisecondsSinceEpoch}_${regularTransactionsCurrent[i].title}_${regularTransactionsCurrent[i].order}'),
                                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                    child: ListTile(
                                      title: Text(regularTransactionsCurrent[i].title),
                                      subtitle: Text(
                                        DateFormat('dd MMMM yyyy', 'ru_RU').format(regularTransactionsCurrent[i].date),
                                        style: TextStyle(
                                          color: regularTransactionsCurrent[i].date.isBefore(today) ||
                                                  (regularTransactionsCurrent[i].date.day == today.day &&
                                                      regularTransactionsCurrent[i].date.month == today.month &&
                                                      regularTransactionsCurrent[i].date.year == today.year)
                                              ? Colors.red
                                              : null,
                                          fontWeight: regularTransactionsCurrent[i].date.isBefore(today) ||
                                                  (regularTransactionsCurrent[i].date.day == today.day &&
                                                      regularTransactionsCurrent[i].date.month == today.month &&
                                                      regularTransactionsCurrent[i].date.year == today.year)
                                              ? FontWeight.bold
                                              : null,
                                        ),
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              if (regularTransactionsCurrent[i].income > 0)
                                                Text('+${regularTransactionsCurrent[i].income.toStringAsFixed(2)} ₽',
                                                    style: const TextStyle(color: Colors.green)),
                                              if (regularTransactionsCurrent[i].expense > 0)
                                                Text('-${regularTransactionsCurrent[i].expense.toStringAsFixed(2)} ₽',
                                                    style: const TextStyle(color: Colors.red)),
                                              Text(
                                                'Итого: ${(regularTransactionsCurrent[i].income - regularTransactionsCurrent[i].expense).toStringAsFixed(2)} ₽',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: (regularTransactionsCurrent[i].income - regularTransactionsCurrent[i].expense) >= 0
                                                      ? Colors.green
                                                      : Colors.red,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(width: 12),
                                          if (!regularTransactionsCurrent[i].isRecurring)
                                            IconButton(
                                              icon: const Icon(Icons.more_vert),
                                              onPressed: () => _showTransactionActions(regularTransactionsCurrent[i]),
                                            )
                                          else
                                            const SizedBox(),
                                        ],
                                      ),
                                    ),
                                  ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('ИТОГО:'),
                              Text(
                                '${balanceCurrent.toStringAsFixed(2)} ₽',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: balanceCurrent >= 0 ? Colors.green : Colors.red,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const VerticalDivider(width: 1, thickness: 1),

                  // Следующий месяц
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Text(
                            _formatMonthName(nextMonth), // ✅ "февраль"
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                          ),
                        ),
                        Expanded(
                          child: ReorderableListView(
                            padding: const EdgeInsets.only(bottom: 70),
                            onReorder: (oldIndex, newIndex) {
                              if (regularTransactionsNext.isEmpty) return;
                              if (oldIndex < 0 || oldIndex >= regularTransactionsNext.length) return;
                              if (newIndex < 0 || newIndex > regularTransactionsNext.length) return;

                              setState(() {
                                if (newIndex > oldIndex) {
                                  newIndex -= 1;
                                }
                                if (newIndex < 0 || newIndex >= regularTransactionsNext.length) return;

                                final item = regularTransactionsNext.removeAt(oldIndex);
                                regularTransactionsNext.insert(newIndex, item);

                                for (int i = 0; i < regularTransactionsNext.length; i++) {
                                  regularTransactionsNext[i].order = i;
                                }

                                _transactions.removeWhere((tx) =>
                                    tx.date.year == nextMonth.year &&
                                    tx.date.month == nextMonth.month &&
                                    !tx.isRecurring);
                                _transactions.addAll(regularTransactionsNext);
                                _saveTransactions();
                              });
                            },
                            children: [
                              ..._buildRecurringSection(nextMonth),
                              if (regularTransactionsNext.isEmpty)
                                const Center(
                                  key: ValueKey('no_transactions_next'),
                                  child: Padding(
                                    padding: EdgeInsets.all(16.0),
                                    child: Text('Нет обычных транзакций'),
                                  ),
                                )
                              else
                                for (int i = 0; i < regularTransactionsNext.length; i++)
                                  Card(
                                    key: ValueKey('tx_next_${regularTransactionsNext[i].date.millisecondsSinceEpoch}_${regularTransactionsNext[i].title}_${regularTransactionsNext[i].order}'),
                                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                    child: ListTile(
                                      title: Text(regularTransactionsNext[i].title),
                                      subtitle: Text(
                                        DateFormat('dd MMMM yyyy', 'ru_RU').format(regularTransactionsNext[i].date),
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              if (regularTransactionsNext[i].income > 0)
                                                Text('+${regularTransactionsNext[i].income.toStringAsFixed(2)} ₽',
                                                    style: const TextStyle(color: Colors.green)),
                                              if (regularTransactionsNext[i].expense > 0)
                                                Text('-${regularTransactionsNext[i].expense.toStringAsFixed(2)} ₽',
                                                    style: const TextStyle(color: Colors.red)),
                                              Text(
                                                'Итого: ${(regularTransactionsNext[i].income - regularTransactionsNext[i].expense).toStringAsFixed(2)} ₽',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: (regularTransactionsNext[i].income - regularTransactionsNext[i].expense) >= 0
                                                      ? Colors.green
                                                      : Colors.red,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(width: 12),
                                          if (!regularTransactionsNext[i].isRecurring)
                                            IconButton(
                                              icon: const Icon(Icons.more_vert),
                                              onPressed: () => _showTransactionActions(regularTransactionsNext[i]),
                                            )
                                          else
                                            const SizedBox(),
                                        ],
                                      ),
                                    ),
                                  ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('ИТОГО:'),
                              Text(
                                '${balanceNext.toStringAsFixed(2)} ₽',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: balanceNext >= 0 ? Colors.green : Colors.red,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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