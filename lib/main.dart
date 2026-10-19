import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:io';

/// Global, app-wide dark/light mode toggle. Any widget can flip
/// `themeModeNotifier.value` and the whole app rebuilds instantly.
final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(ThemeMode.light);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  ThemeData _buildTheme(ColorScheme scheme) {
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: scheme.brightness == Brightness.light
          ? const Color(0xFFF7F6FB)
          : const Color(0xFF15131C),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'Notepad',
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          theme: _buildTheme(ColorScheme.fromSeed(seedColor: const Color(0xFF6C5CE7))),
          darkTheme: _buildTheme(ColorScheme.fromSeed(
            seedColor: const Color(0xFF6C5CE7),
            brightness: Brightness.dark,
          )),
          home: const SplashScreen(),
        );
      },
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigate();
  }

  Future<void> _navigate() async {
    final Future<Database> dbFuture = DatabaseHelper.instance.database;
    // Give the splash a moment to render, and let the DB init in parallel.
    await Future.wait([
      dbFuture,
      Future.delayed(const Duration(milliseconds: 700)),
    ]);

    final bool onboarded = await DatabaseHelper.instance.isOnboarded();
    final bool lockEnabled = await DatabaseHelper.instance.isLockEnabled();
    final bool hasPin = await DatabaseHelper.instance.hasPin();

    if (!mounted) return;

    Widget next;
    if (!onboarded) {
      next = const WelcomeScreen();
    } else if (lockEnabled && hasPin) {
      next = const PinEntryScreen();
    } else {
      next = const NotesHomePage();
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => next),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF6C5CE7), Color(0xFFA29BFE)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.edit_note_rounded, size: 84, color: Colors.white),
                SizedBox(height: 20),
                Text(
                  'My Notepad',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                SizedBox(height: 24),
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A short, professional intro shown once per app launch: greets the
/// user and lets them tap through to their notes when they're ready.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  static const List<_WelcomeHighlight> _highlights = [
    _WelcomeHighlight(
      icon: Icons.folder_copy_rounded,
      title: 'Organize with folders',
      subtitle: 'Group notes by Personal, Work, Ideas, or your own folders.',
    ),
    _WelcomeHighlight(
      icon: Icons.push_pin_rounded,
      title: 'Pin what matters',
      subtitle: 'Keep important notes at the top of the list.',
    ),
    _WelcomeHighlight(
      icon: Icons.palette_rounded,
      title: 'Color-coded and searchable',
      subtitle: 'Color your notes and find them instantly with search.',
    ),
    _WelcomeHighlight(
      icon: Icons.lock_rounded,
      title: 'Private and PIN-protected',
      subtitle: 'Lock the app and mark notes as private. Everything stays on this device.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    await DatabaseHelper.instance.setOnboarded();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const PinSetupScreen(mode: PinSetupMode.initial)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  CircleAvatar(
                    radius: 34,
                    backgroundColor: scheme.primary.withValues(alpha: 0.12),
                    child: Icon(Icons.edit_note_rounded, color: scheme.primary, size: 34),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Welcome',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your own private space for notes and thoughts, kept just for you.',
                    style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant, height: 1.4),
                  ),
                  const SizedBox(height: 32),
                  Expanded(
                    child: ListView.separated(
                      itemCount: _highlights.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 18),
                      itemBuilder: (context, index) {
                        final h = _highlights[index];
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: scheme.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(h.icon, color: scheme.primary, size: 22),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    h.title,
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    h.subtitle,
                                    style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant, height: 1.35),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _start,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: scheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Get Started', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          SizedBox(width: 8),
                          Icon(Icons.arrow_forward_rounded, size: 20),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WelcomeHighlight {
  final IconData icon;
  final String title;
  final String subtitle;
  const _WelcomeHighlight({required this.icon, required this.title, required this.subtitle});
}

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('notes.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final Directory documentsDirectory = await getApplicationDocumentsDirectory();
    final String dbPath = p.join(documentsDirectory.path, filePath);
    return await openDatabase(
      dbPath,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        folder TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_pinned INTEGER DEFAULT 0,
        is_private INTEGER DEFAULT 0,
        color TEXT DEFAULT '#FFFFFF'
      )
    ''');

    await db.execute('''
      CREATE TABLE folders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    final String now = DateTime.now().toIso8601String();
    await db.insert('folders', {'name': 'Personal', 'created_at': now});
    await db.insert('folders', {'name': 'Work', 'created_at': now});
    await db.insert('folders', {'name': 'Ideas', 'created_at': now});
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE notes ADD COLUMN is_private INTEGER DEFAULT 0');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS app_settings (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');
    }
  }

  // ---- App settings (key/value), used for the local PIN lock ----

  Future<String?> getSetting(String key) async {
    final db = await database;
    final rows = await db.query('app_settings', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      'app_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteSetting(String key) async {
    final db = await database;
    await db.delete('app_settings', where: 'key = ?', whereArgs: [key]);
  }

  String _hashPin(String pin) => sha256.convert(utf8.encode(pin)).toString();

  Future<bool> hasPin() async => (await getSetting('pin_hash')) != null;

  Future<void> setPin(String pin) async {
    await setSetting('pin_hash', _hashPin(pin));
    await setSetting('lock_enabled', '1');
  }

  Future<void> removePin() async {
    await deleteSetting('pin_hash');
    await setSetting('lock_enabled', '0');
  }

  Future<bool> verifyPin(String pin) async {
    final stored = await getSetting('pin_hash');
    if (stored == null) return false;
    return stored == _hashPin(pin);
  }

  Future<bool> isLockEnabled() async {
    final value = await getSetting('lock_enabled');
    return value == '1';
  }

  Future<void> setLockEnabled(bool enabled) async {
    await setSetting('lock_enabled', enabled ? '1' : '0');
  }

  Future<bool> isOnboarded() async {
    final value = await getSetting('onboarded');
    return value == '1';
  }

  Future<void> setOnboarded() async {
    await setSetting('onboarded', '1');
  }

  Future<int> insertNote(Map<String, dynamic> note) async {
    final db = await database;
    return await db.insert('notes', note);
  }

  Future<int> updateNote(int id, Map<String, dynamic> note) async {
    final db = await database;
    return await db.update('notes', note, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteNote(int id) async {
    final db = await database;
    return await db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> duplicateNote(Map<String, dynamic> note) async {
    final db = await database;
    final copy = Map<String, dynamic>.from(note);
    copy.remove('id');
    copy['title'] = '${copy['title']} (copy)';
    copy['created_at'] = DateTime.now().toIso8601String();
    copy['updated_at'] = DateTime.now().toIso8601String();
    return await db.insert('notes', copy);
  }

  Future<int> deleteFolder(String name) async {
    final db = await database;
    // Move any notes in the deleted folder back to a safe default.
    await db.update(
      'notes',
      {'folder': 'Personal'},
      where: 'folder = ?',
      whereArgs: [name],
    );
    return await db.delete('folders', where: 'name = ?', whereArgs: [name]);
  }

  Future<List<Map<String, dynamic>>> getNotes({String? folder}) async {
    final db = await database;
    if (folder != null && folder != 'All Notes') {
      return await db.query(
        'notes',
        where: 'folder = ?',
        whereArgs: [folder],
        orderBy: 'is_pinned DESC, updated_at DESC',
      );
    }
    return await db.query('notes', orderBy: 'is_pinned DESC, updated_at DESC');
  }

  Future<List<Map<String, dynamic>>> getAllFolders() async {
    final db = await database;
    return await db.query('folders', orderBy: 'name ASC');
  }

  Future<int> insertFolder(String name) async {
    final db = await database;
    return await db.insert('folders', {
      'name': name,
      'created_at': DateTime.now().toIso8601String(),
    });
  }
}

class Note {
  final int? id;
  final String title;
  final String content;
  final String folder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isPinned;
  final bool isPrivate;
  final String color;

  Note({
    this.id,
    required this.title,
    required this.content,
    required this.folder,
    required this.createdAt,
    required this.updatedAt,
    this.isPinned = false,
    this.isPrivate = false,
    this.color = '#FFFFFF',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'folder': folder,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_pinned': isPinned ? 1 : 0,
      'is_private': isPrivate ? 1 : 0,
      'color': color,
    };
  }

  static Note fromMap(Map<String, dynamic> map) {
    return Note(
      id: map['id'],
      title: map['title'],
      content: map['content'],
      folder: map['folder'],
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
      isPinned: map['is_pinned'] == 1,
      isPrivate: map['is_private'] == 1,
      color: map['color'] ?? '#FFFFFF',
    );
  }

  Color get displayColor {
    try {
      return Color(int.parse(color.replaceFirst('#', '0xFF')));
    } catch (_) {
      return Colors.white;
    }
  }
}

/// Small helper for friendly relative timestamps ("Just now", "3h ago", etc).
String friendlyTimestamp(DateTime dateTime) {
  final Duration diff = DateTime.now().difference(dateTime);
  if (diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return DateFormat('MMM d, y').format(dateTime);
}

enum NoteSort { updatedDesc, createdDesc, titleAsc }

class NotesHomePage extends StatefulWidget {
  const NotesHomePage({super.key});

  @override
  State<NotesHomePage> createState() => _NotesHomePageState();
}

class _NotesHomePageState extends State<NotesHomePage> {
  List<Note> _allNotes = [];
  List<String> _folders = ['All Notes'];
  Map<String, int> _folderCounts = {};
  String _selectedFolder = 'All Notes';
  bool _isGridView = false;
  bool _isLoading = true;
  bool _hasPin = false;
  NoteSort _sort = NoteSort.updatedDesc;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final hasPin = await DatabaseHelper.instance.hasPin();
    await _loadFolders();
    await _loadNotes();
    if (!mounted) return;
    setState(() {
      _hasPin = hasPin;
      _isLoading = false;
    });
  }

  Future<void> _loadFolders() async {
    final folders = await DatabaseHelper.instance.getAllFolders();
    final allNotes = await DatabaseHelper.instance.getNotes();
    if (!mounted) return;

    final Map<String, int> counts = {};
    for (final n in allNotes) {
      final String f = n['folder'] as String;
      counts[f] = (counts[f] ?? 0) + 1;
    }

    setState(() {
      _folders = ['All Notes', ...folders.map((f) => f['name'] as String)];
      _folderCounts = counts;
    });
  }

  Future<void> _loadNotes() async {
    final notes = await DatabaseHelper.instance.getNotes(folder: _selectedFolder);
    if (!mounted) return;
    setState(() {
      _allNotes = notes.map((n) => Note.fromMap(n)).toList();
    });
  }

  List<Note> get _visibleNotes {
    Iterable<Note> notes = _allNotes;
    if (_searchQuery.isNotEmpty) {
      notes = notes.where((n) =>
      n.title.toLowerCase().contains(_searchQuery) ||
          n.content.toLowerCase().contains(_searchQuery));
    }
    final List<Note> list = notes.toList();
    switch (_sort) {
      case NoteSort.updatedDesc:
        list.sort((a, b) {
          if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
          return b.updatedAt.compareTo(a.updatedAt);
        });
        break;
      case NoteSort.createdDesc:
        list.sort((a, b) {
          if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
          return b.createdAt.compareTo(a.createdAt);
        });
        break;
      case NoteSort.titleAsc:
        list.sort((a, b) {
          if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        });
        break;
    }
    return list;
  }

  void _showNoteEditor({Note? existingNote}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => NoteEditorSheet(
        note: existingNote,
        folders: _folders.where((f) => f != 'All Notes').toList(),
        lockAvailable: _hasPin,
        onSave: () async {
          await _loadFolders();
          await _loadNotes();
          if (!sheetContext.mounted) return;
          Navigator.pop(sheetContext);
        },
      ),
    );
  }

  /// Opens a note, asking for the PIN first if the note is marked private.
  Future<void> _openNote(Note note) async {
    if (note.isPrivate) {
      final bool ok = await _verifyPinDialog();
      if (!ok) return;
    }
    if (!mounted) return;
    _showNoteEditor(existingNote: note);
  }

  /// Shows a PIN entry dialog and returns true only if the PIN is correct.
  Future<bool> _verifyPinDialog() async {
    final TextEditingController pinController = TextEditingController();
    bool wrongPin = false;

    final bool? result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Enter PIN'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('This note is private.'),
              const SizedBox(height: 16),
              TextField(
                controller: pinController,
                autofocus: true,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                  counterText: '',
                  hintText: 'PIN',
                  errorText: wrongPin ? 'Incorrect PIN' : null,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final bool ok = await DatabaseHelper.instance.verifyPin(pinController.text.trim());
                if (ok) {
                  if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                } else {
                  setDialogState(() => wrongPin = true);
                }
              },
              child: const Text('Unlock'),
            ),
          ],
        ),
      ),
    );

    return result ?? false;
  }

  void _showFolderDialog() {
    final TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Folder name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final String name = controller.text.trim();
              if (name.isEmpty) return;
              await DatabaseHelper.instance.insertFolder(name);
              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext);
              await _loadFolders();
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteFolder(String folder) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Folder'),
        content: Text(
          'Delete "$folder"? Notes inside will be moved to Personal.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await DatabaseHelper.instance.deleteFolder(folder);
              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext);
              if (_selectedFolder == folder) {
                setState(() => _selectedFolder = 'All Notes');
              }
              await _loadFolders();
              await _loadNotes();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _deleteNote(Note note) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Note'),
        content: Text('Delete "${note.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (note.id != null) {
                await DatabaseHelper.instance.deleteNote(note.id!);
              }
              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext);
              await _loadFolders();
              await _loadNotes();
              _showUndoDeleteSnackBar(note);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showUndoDeleteSnackBar(Note note) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('"${note.title}" deleted'),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'UNDO',
            onPressed: () async {
              await DatabaseHelper.instance.insertNote(Note(
                title: note.title,
                content: note.content,
                folder: note.folder,
                createdAt: note.createdAt,
                updatedAt: DateTime.now(),
                isPinned: note.isPinned,
                isPrivate: note.isPrivate,
                color: note.color,
              ).toMap());
              await _loadFolders();
              await _loadNotes();
            },
          ),
          duration: const Duration(seconds: 4),
        ),
      );
  }

  Future<void> _duplicateNote(Note note) async {
    await DatabaseHelper.instance.duplicateNote(note.toMap());
    await _loadFolders();
    await _loadNotes();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Note duplicated'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _copyNoteToClipboard(Note note) {
    final text = note.content.isEmpty ? note.title : '${note.title}\n\n${note.content}';
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showNoteActions(Note note) async {
    if (note.isPrivate) {
      final bool ok = await _verifyPinDialog();
      if (!ok) return;
    }
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      // Material is provided by the bottom sheet itself, so ListTile ink
      // and background effects render correctly here.
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  note.title,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            ListTile(
              leading: Icon(note.isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined),
              title: Text(note.isPinned ? 'Unpin note' : 'Pin note'),
              onTap: () {
                Navigator.pop(sheetContext);
                _togglePin(note);
              },
            ),
            ListTile(
              leading: Icon(note.isPrivate ? Icons.lock_open_rounded : Icons.lock_rounded),
              title: Text(note.isPrivate ? 'Remove from private' : 'Make private'),
              onTap: () {
                Navigator.pop(sheetContext);
                _togglePrivate(note);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_all_rounded),
              title: const Text('Duplicate'),
              onTap: () {
                Navigator.pop(sheetContext);
                _duplicateNote(note);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('Copy content'),
              onTap: () {
                Navigator.pop(sheetContext);
                _copyNoteToClipboard(note);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(sheetContext);
                _deleteNote(note);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _togglePin(Note note) async {
    if (note.id == null) return;
    final updatedNote = Note(
      id: note.id,
      title: note.title,
      content: note.content,
      folder: note.folder,
      createdAt: note.createdAt,
      updatedAt: note.updatedAt,
      isPinned: !note.isPinned,
      isPrivate: note.isPrivate,
      color: note.color,
    );
    await DatabaseHelper.instance.updateNote(note.id!, updatedNote.toMap());
    await _loadNotes();
  }

  Future<void> _togglePrivate(Note note) async {
    if (note.id == null) return;
    final hasPin = await DatabaseHelper.instance.hasPin();
    if (!hasPin && !note.isPrivate) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Set up a PIN in Settings first to mark notes as private.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final updatedNote = Note(
      id: note.id,
      title: note.title,
      content: note.content,
      folder: note.folder,
      createdAt: note.createdAt,
      updatedAt: note.updatedAt,
      isPinned: note.isPinned,
      isPrivate: !note.isPrivate,
      color: note.color,
    );
    await DatabaseHelper.instance.updateNote(note.id!, updatedNote.toMap());
    await _loadNotes();
  }

  @override
  Widget build(BuildContext context) {
    final visibleNotes = _visibleNotes;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Notes'),
        actions: [
          PopupMenuButton<NoteSort>(
            icon: const Icon(Icons.sort_rounded),
            tooltip: 'Sort notes',
            onSelected: (value) => setState(() => _sort = value),
            itemBuilder: (context) => const [
              PopupMenuItem(value: NoteSort.updatedDesc, child: Text('Last edited')),
              PopupMenuItem(value: NoteSort.createdDesc, child: Text('Date created')),
              PopupMenuItem(value: NoteSort.titleAsc, child: Text('Title (A to Z)')),
            ],
          ),
          IconButton(
            icon: Icon(_isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded),
            tooltip: _isGridView ? 'List view' : 'Grid view',
            onPressed: () => setState(() => _isGridView = !_isGridView),
          ),
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: 'New folder',
            onPressed: _showFolderDialog,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
              await _loadData();
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
          onRefresh: _loadData,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search notes...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => _searchController.clear(),
                    )
                        : null,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _statChip(
                            icon: Icons.description_outlined,
                            label: '${_allNotes.length} note${_allNotes.length == 1 ? '' : 's'}',
                          ),
                          const SizedBox(width: 8),
                          _statChip(
                            icon: Icons.push_pin_outlined,
                            label: '${_allNotes.where((n) => n.isPinned).length} pinned',
                          ),
                          const SizedBox(width: 8),
                          _statChip(
                            icon: Icons.folder_outlined,
                            label: '${_folders.length - 1} folders',
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  children: _folders.map((folder) {
                    final isSelected = _selectedFolder == folder;
                    final count = folder == 'All Notes'
                        ? _folderCounts.values.fold(0, (a, b) => a + b)
                        : (_folderCounts[folder] ?? 0);
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: GestureDetector(
                        onLongPress: folder == 'All Notes'
                            ? null
                            : () => _confirmDeleteFolder(folder),
                        child: FilterChip(
                          label: Text('$folder  ·  $count'),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() => _selectedFolder = folder);
                            _loadNotes();
                          },
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              Expanded(
                child: visibleNotes.isEmpty
                    ? _buildEmptyState()
                    : (_isGridView
                    ? _buildGridView(visibleNotes)
                    : _buildListView(visibleNotes)),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showNoteEditor(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New note'),
      ),
    );
  }

  Widget _statChip({required IconData icon, required String label}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final bool searching = _searchQuery.isNotEmpty;
    return LayoutBuilder(
      builder: (context, constraints) {
        return ListView(
          // ListView so RefreshIndicator still works on an empty state.
          children: [
            SizedBox(
              height: constraints.maxHeight < 380 ? constraints.maxHeight : 380,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        searching ? Icons.search_off_rounded : Icons.note_add_outlined,
                        size: 72,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        searching ? 'No notes match "$_searchQuery"' : 'No notes yet',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                      ),
                      if (!searching) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Tap "New note" to get started',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildListView(List<Note> notes) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: notes.length,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _buildNoteCard(notes[index]),
      ),
    );
  }

  Widget _buildGridView(List<Note> notes) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Keep grid cards comfortably sized on both phones and wider screens.
        final int crossAxisCount = constraints.maxWidth >= 700 ? 3 : 2;
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.8,
          ),
          itemCount: notes.length,
          itemBuilder: (context, index) => _buildNoteCard(notes[index], isGrid: true),
        );
      },
    );
  }

  /// Builds a single note card.
  ///
  /// IMPORTANT: in list mode this card lives directly inside a `Column`
  /// with unbounded height (no `childAspectRatio` to constrain it, unlike
  /// grid mode). Using `Expanded` for the content text there causes
  /// "RenderFlex children have non-zero flex but incoming height
  /// constraints are unbounded". So content sizing is height-capped via
  /// `maxLines` in list mode, and only uses `Expanded` in grid mode where
  /// the cell height is actually bounded.
  Widget _buildNoteCard(Note note, {bool isGrid = false}) {
    final contentText = Text(
      note.isPrivate
          ? 'Private note — tap to unlock'
          : (note.content.isEmpty ? 'No additional text' : note.content),
      style: TextStyle(
        fontSize: 14,
        height: 1.35,
        color: note.content.isEmpty ? Colors.grey.shade500 : Colors.black87,
        fontStyle: note.content.isEmpty ? FontStyle.italic : FontStyle.normal,
      ),
      maxLines: isGrid ? 5 : 3,
      overflow: TextOverflow.ellipsis,
    );

    return Card(
      color: note.displayColor,
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.04)),
      ),
      // Material wraps InkWell here via Card, so ink splashes render
      // correctly on top of the card's background color.
      child: InkWell(
        onTap: () => _openNote(note),
        onLongPress: () => _showNoteActions(note),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: isGrid ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      note.title,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (note.isPrivate)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Icon(Icons.lock_rounded, size: 15, color: Theme.of(context).colorScheme.primary),
                    ),
                  if (note.isPinned)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Icon(Icons.push_pin_rounded, size: 16, color: Theme.of(context).colorScheme.primary),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              // Only use Expanded when the parent height is actually bounded
              // (grid cells are; list-mode cards inside a Column are not).
              isGrid ? Expanded(child: contentText) : contentText,
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.folder_rounded, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      note.folder,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    friendlyTimestamp(note.updatedAt),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
              if (!isGrid)
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: Icon(
                        note.isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      onPressed: () => _togglePin(note),
                    ),
                    IconButton(
                      icon: const Icon(Icons.more_vert_rounded, size: 18),
                      tooltip: 'More actions',
                      onPressed: () => _showNoteActions(note),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class NoteEditorSheet extends StatefulWidget {
  final Note? note;
  final List<String> folders;
  final VoidCallback onSave;
  final bool lockAvailable;

  const NoteEditorSheet({
    super.key,
    this.note,
    required this.folders,
    required this.onSave,
    this.lockAvailable = false,
  });

  @override
  State<NoteEditorSheet> createState() => _NoteEditorSheetState();
}

class _NoteEditorSheetState extends State<NoteEditorSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  late String _selectedFolder;
  late bool _isPinned;
  late bool _isPrivate;
  late String _selectedColor;
  bool _isSaving = false;

  static const List<String> _colors = [
    '#FFFFFF', '#FFE5E5', '#E5F6FF', '#E5FFE5', '#FFF9E5', '#F3E5FF',
  ];
  static const List<Color> _colorValues = [
    Colors.white, Color(0xFFFFEBEE), Color(0xFFE3F2FD),
    Color(0xFFE8F5E9), Color(0xFFFFFDE7), Color(0xFFF3E5F5),
  ];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note?.title ?? '');
    _contentController = TextEditingController(text: widget.note?.content ?? '');
    _selectedFolder = widget.note?.folder ??
        (widget.folders.isNotEmpty ? widget.folders.first : 'Personal');
    _isPinned = widget.note?.isPinned ?? false;
    _isPrivate = widget.note?.isPrivate ?? false;
    _selectedColor = widget.note?.color ?? '#FFFFFF';
    _contentController.addListener(() => setState(() {}));
  }

  int get _wordCount {
    final text = _contentController.text.trim();
    if (text.isEmpty) return 0;
    return text.split(RegExp(r'\s+')).length;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _saveNote() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a title'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    final now = DateTime.now();
    final note = Note(
      id: widget.note?.id,
      title: _titleController.text.trim(),
      content: _contentController.text.trim(),
      folder: _selectedFolder,
      createdAt: widget.note?.createdAt ?? now,
      updatedAt: now,
      isPinned: _isPinned,
      isPrivate: _isPrivate,
      color: _selectedColor,
    );

    if (widget.note?.id != null) {
      await DatabaseHelper.instance.updateNote(widget.note!.id!, note.toMap());
    } else {
      await DatabaseHelper.instance.insertNote(note.toMap());
    }

    if (!mounted) return;
    widget.onSave();
  }

  @override
  Widget build(BuildContext context) {
    final double viewInsetsBottom = MediaQuery.of(context).viewInsets.bottom;
    final double sheetHeight = MediaQuery.of(context).size.height * 0.92;

    return Padding(
      // Keep the sheet clear of the keyboard so the active field never
      // ends up hidden behind it.
      padding: EdgeInsets.only(bottom: viewInsetsBottom),
      child: SizedBox(
        height: sheetHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          // Material ensures ink/selection effects on any interactive
          // widgets inside the sheet paint correctly over this background.
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.note == null ? 'New Note' : 'Edit Note',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _titleController,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'Title',
                            prefixIcon: Icon(Icons.title_rounded),
                          ),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 20),
                        // Roomier, more comfortable typing area for note content.
                        ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 220),
                          child: TextField(
                            controller: _contentController,
                            minLines: 10,
                            maxLines: 24,
                            textCapitalization: TextCapitalization.sentences,
                            textAlignVertical: TextAlignVertical.top,
                            decoration: const InputDecoration(
                              labelText: 'Content',
                              alignLabelWithHint: true,
                              prefixIcon: Padding(
                                padding: EdgeInsets.only(bottom: 140),
                                child: Icon(Icons.notes_rounded),
                              ),
                              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                            ),
                            style: const TextStyle(fontSize: 16, height: 1.5),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              '$_wordCount word${_wordCount == 1 ? '' : 's'}  ·  '
                                  '${_contentController.text.trim().length} characters',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedFolder,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Folder',
                            prefixIcon: Icon(Icons.folder_rounded),
                          ),
                          items: widget.folders
                              .map((folder) => DropdownMenuItem(
                            value: folder,
                            child: Text(folder, overflow: TextOverflow.ellipsis),
                          ))
                              .toList(),
                          onChanged: (value) {
                            if (value != null) setState(() => _selectedFolder = value);
                          },
                        ),
                        const SizedBox(height: 24),
                        const Text('Note Color', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: _colors.asMap().entries.map((entry) {
                            final selected = _selectedColor == entry.value;
                            return GestureDetector(
                              onTap: () => setState(() => _selectedColor = entry.value),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: selected ? 38 : 32,
                                height: selected ? 38 : 32,
                                decoration: BoxDecoration(
                                  color: _colorValues[entry.key],
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: selected
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.grey.shade400,
                                    width: selected ? 3 : 1,
                                  ),
                                ),
                                child: selected
                                    ? Icon(Icons.check_rounded,
                                    size: 16, color: Theme.of(context).colorScheme.primary)
                                    : null,
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Pin this note'),
                          subtitle: const Text('Pinned notes stay at the top'),
                          value: _isPinned,
                          onChanged: (value) => setState(() => _isPinned = value),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Private note'),
                          subtitle: Text(
                            widget.lockAvailable
                                ? 'Requires your PIN to open'
                                : 'Set up a PIN in Settings to use this',
                          ),
                          value: _isPrivate,
                          onChanged: widget.lockAvailable
                              ? (value) => setState(() => _isPrivate = value)
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveNote,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6C5CE7),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                            : const Text(
                          'Save Note',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
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
}

enum PinSetupMode { initial, change }

/// Lets the user create (or change) their local PIN. Works fully offline —
/// the PIN is hashed and stored only in the on-device database.
class PinSetupScreen extends StatefulWidget {
  final PinSetupMode mode;
  const PinSetupScreen({super.key, required this.mode});

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final String pin = _pinController.text.trim();
    final String confirm = _confirmController.text.trim();

    if (pin.length < 4) {
      setState(() => _error = 'PIN must be at least 4 digits');
      return;
    }
    if (pin != confirm) {
      setState(() => _error = 'PINs do not match');
      return;
    }

    setState(() {
      _error = null;
      _saving = true;
    });

    await DatabaseHelper.instance.setPin(pin);

    if (!mounted) return;

    if (widget.mode == PinSetupMode.initial) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const NotesHomePage()),
      );
    } else {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _skip() async {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const NotesHomePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bool isInitial = widget.mode == PinSetupMode.initial;

    return Scaffold(
      appBar: AppBar(
        title: Text(isInitial ? 'Set up a PIN' : 'Change PIN'),
        automaticallyImplyLeading: !isInitial,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: scheme.primary.withValues(alpha: 0.12),
                      child: Icon(Icons.lock_rounded, color: scheme.primary, size: 30),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      isInitial ? 'Protect this app with a PIN' : 'Choose a new PIN',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This PIN stays on your device only. It is never sent anywhere '
                          'and works even without an internet connection.',
                      style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant, height: 1.4),
                    ),
                    const SizedBox(height: 28),
                    TextField(
                      controller: _pinController,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: const InputDecoration(
                        labelText: 'New PIN (4-6 digits)',
                        counterText: '',
                        prefixIcon: Icon(Icons.password_rounded),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _confirmController,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: const InputDecoration(
                        labelText: 'Confirm PIN',
                        counterText: '',
                        prefixIcon: Icon(Icons.password_rounded),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                    ],
                    const SizedBox(height: 32),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: scheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: _saving
                            ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                            : Text(
                          isInitial ? 'Set PIN' : 'Save',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    if (isInitial) ...[
                      const SizedBox(height: 12),
                      Center(
                        child: TextButton(
                          onPressed: _saving ? null : _skip,
                          child: const Text('Skip for now'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Lock screen shown on launch when app lock is enabled. Verifies the
/// PIN entirely offline against the locally stored hash.
class PinEntryScreen extends StatefulWidget {
  const PinEntryScreen({super.key});

  @override
  State<PinEntryScreen> createState() => _PinEntryScreenState();
}

class _PinEntryScreenState extends State<PinEntryScreen> {
  final TextEditingController _pinController = TextEditingController();
  String? _error;
  bool _checking = false;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    setState(() {
      _checking = true;
      _error = null;
    });

    final bool ok = await DatabaseHelper.instance.verifyPin(_pinController.text.trim());

    if (!mounted) return;

    if (ok) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const NotesHomePage()),
      );
    } else {
      setState(() {
        _checking = false;
        _error = 'Incorrect PIN. Try again.';
      });
      _pinController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 56),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CircleAvatar(
                      radius: 34,
                      backgroundColor: scheme.primary.withValues(alpha: 0.12),
                      child: Icon(Icons.lock_rounded, color: scheme.primary, size: 34),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Enter your PIN',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This app is locked for privacy.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 28),
                    TextField(
                      controller: _pinController,
                      obscureText: true,
                      autofocus: true,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      style: const TextStyle(fontSize: 22, letterSpacing: 6),
                      decoration: InputDecoration(
                        counterText: '',
                        errorText: _error,
                      ),
                      onSubmitted: (_) => _unlock(),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _checking ? null : _unlock,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: scheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _checking
                          ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                          : const Text('Unlock', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// App settings: dark mode and the local, offline PIN lock.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _hasPin = false;
  bool _lockEnabled = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final hasPin = await DatabaseHelper.instance.hasPin();
    final lockEnabled = await DatabaseHelper.instance.isLockEnabled();
    if (!mounted) return;
    setState(() {
      _hasPin = hasPin;
      _lockEnabled = lockEnabled;
      _loading = false;
    });
  }

  Future<void> _onLockToggled(bool value) async {
    if (value && !_hasPin) {
      final bool? created = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (context) => const PinSetupScreen(mode: PinSetupMode.change)),
      );
      if (created == true) await _load();
      return;
    }

    if (!value) {
      final bool confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Turn off App Lock?'),
          content: const Text(
            'Your notes, including private ones, will open without a PIN.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Turn off'),
            ),
          ],
        ),
      ) ??
          false;
      if (!confirmed) return;
      await DatabaseHelper.instance.setLockEnabled(false);
      await _load();
      return;
    }

    await DatabaseHelper.instance.setLockEnabled(true);
    await _load();
  }

  Future<void> _changePin() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const PinSetupScreen(mode: PinSetupMode.change)),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Text('Appearance', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            ValueListenableBuilder<ThemeMode>(
              valueListenable: themeModeNotifier,
              builder: (context, mode, _) => SwitchListTile(
                title: const Text('Dark mode'),
                secondary: const Icon(Icons.dark_mode_rounded),
                value: mode == ThemeMode.dark,
                onChanged: (value) {
                  themeModeNotifier.value = value ? ThemeMode.dark : ThemeMode.light;
                },
              ),
            ),
            const Divider(height: 24),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text('Privacy & Security', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            SwitchListTile(
              title: const Text('App Lock'),
              subtitle: const Text('Require a PIN to open the app'),
              secondary: const Icon(Icons.lock_outline_rounded),
              value: _lockEnabled,
              onChanged: _onLockToggled,
            ),
            ListTile(
              leading: const Icon(Icons.password_rounded),
              title: Text(_hasPin ? 'Change PIN' : 'Set a PIN'),
              subtitle: const Text('Stored securely on this device only'),
              onTap: _changePin,
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 20, 16, 4),
              child: Text(
                'App Lock and private notes work fully offline. Your PIN never '
                    'leaves this device and no account or internet connection is required.',
                style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}