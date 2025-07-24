import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../../services/secure_storage_service.dart';

class ThemeSettingsScreen extends StatefulWidget {
  @override
  State<ThemeSettingsScreen> createState() => _ThemeSettingsScreenState();
}

class _ThemeSettingsScreenState extends State<ThemeSettingsScreen> {
  bool _isDark = false;
  Map<String, Color> _customColors = {};
  final _storage = SecureStorageService();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadThemeColors();
  }

  Future<void> _loadThemeColors() async {
    final stored = await _storage.getThemeColors();
    if (stored != null) {
      setState(() {
        _customColors = stored.map((k, v) => MapEntry(k, Color(int.parse(v))));
      });
    }
    setState(() => _loading = false);
  }

  Future<void> _saveThemeColors() async {
    final hexMap = _customColors.map((k, v) => MapEntry(k, v.value.toString()));
    await _storage.storeThemeColors(hexMap);
  }

  Future<void> _resetThemeColors() async {
    await _storage.deleteThemeColors();
    setState(() => _customColors = {});
  }

  void _pickColor(String key, Color currentColor) async {
    Color selectedColor = currentColor;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Pick $key color'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: currentColor,
            onColorChanged: (color) => selectedColor = color,
            enableAlpha: false,
            showLabel: false,
            pickerAreaHeightPercent: 0.7,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(selectedColor),
            child: const Text('Select'),
          ),
        ],
      ),
    ).then((color) async {
      if (color != null && color is Color) {
        setState(() {
          _customColors[key] = color;
        });
        await _saveThemeColors();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final baseScheme = Theme.of(context).colorScheme;
    final colorScheme = baseScheme.copyWith(
      primary: _customColors['Primary'] ?? baseScheme.primary,
      onPrimary: _customColors['On Primary'] ?? baseScheme.onPrimary,
      secondary: _customColors['Secondary'] ?? baseScheme.secondary,
      onSecondary: _customColors['On Secondary'] ?? baseScheme.onSecondary,
      background: _customColors['Background'] ?? baseScheme.background,
      onBackground: _customColors['On Background'] ?? baseScheme.onBackground,
      surface: _customColors['Surface'] ?? baseScheme.surface,
      onSurface: _customColors['On Surface'] ?? baseScheme.onSurface,
      error: _customColors['Error'] ?? baseScheme.error,
      onError: _customColors['On Error'] ?? baseScheme.onError,
    );
    final theme = Theme.of(context).copyWith(colorScheme: colorScheme);
    final colors = [
      {
        'label': 'Primary (AppBar, Buttons)',
        'key': 'Primary',
        'color': colorScheme.primary,
      },
      {
        'label': 'On Primary (Text on Primary)',
        'key': 'On Primary',
        'color': colorScheme.onPrimary,
      },
      {
        'label': 'Secondary (Accent)',
        'key': 'Secondary',
        'color': colorScheme.secondary,
      },
      {
        'label': 'On Secondary (Text on Accent)',
        'key': 'On Secondary',
        'color': colorScheme.onSecondary,
      },
      {
        'label': 'Background (Main Background)',
        'key': 'Background',
        'color': colorScheme.background,
      },
      {
        'label': 'On Background (Text on Background)',
        'key': 'On Background',
        'color': colorScheme.onBackground,
      },
      {
        'label': 'Surface (Cards, Sheets)',
        'key': 'Surface',
        'color': colorScheme.surface,
      },
      {
        'label': 'On Surface (Text on Cards)',
        'key': 'On Surface',
        'color': colorScheme.onSurface,
      },
      {
        'label': 'Error',
        'key': 'Error',
        'color': colorScheme.error,
      },
      {
        'label': 'On Error (Text on Error)',
        'key': 'On Error',
        'color': colorScheme.onError,
      },
    ];
    return Theme(
      data: _isDark ? ThemeData.dark().copyWith(colorScheme: colorScheme) : theme,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Theme & Colors'),
          // Removed day/night toggle button
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Container(
                color: colorScheme.background,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text('Preview of App Colors', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    const SizedBox(height: 16),
                    ...colors.map((c) => Card(
                          child: ListTile(
                            leading: CircleAvatar(backgroundColor: c['color'] as Color),
                            title: Text(c['label'] as String),
                            subtitle: Text('#${(c['color'] as Color).value.toRadixString(16).padLeft(8, '0').toUpperCase()}'),
                            trailing: IconButton(
                              icon: const Icon(Icons.color_lens),
                              onPressed: () => _pickColor(c['key'] as String, c['color'] as Color),
                            ),
                          ),
                        )),
                    const SizedBox(height: 32),
                    Card(
                      child: ListTile(
                        leading: Icon(Icons.navigation, color: colorScheme.primary),
                        title: const Text('Navigation Bar Example'),
                        subtitle: const Text('This is how the nav bar color looks.'),
                        tileColor: colorScheme.primary,
                        textColor: colorScheme.onPrimary,
                        iconColor: colorScheme.onPrimary,
                      ),
                    ),
                    Card(
                      child: ListTile(
                        leading: Icon(Icons.chat_bubble, color: colorScheme.secondary),
                        title: const Text('Accent Example'),
                        subtitle: const Text('This is how the accent color looks.'),
                        tileColor: colorScheme.secondary,
                        textColor: colorScheme.onSecondary,
                        iconColor: colorScheme.onSecondary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reset to Default'),
                      onPressed: _resetThemeColors,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
} 