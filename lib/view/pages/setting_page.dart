import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:locsand/src/core_protocols.dart';
import 'package:locsand/src/data/session_data.dart';
import 'package:locsand/src/helpers/receive_folder.dart';
import 'package:locsand/src/helpers/settings_store.dart';
import 'package:locsand/src/helpers/theme_mode.dart';
import 'package:locsand/view/components/card_style.dart';
import 'package:locsand/view/components/floating_app_bar.dart';
import 'package:locsand/view/components/show_dialog.dart';

class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {

  String? _folder;
  bool _discovery = true;

  @override
  void initState() {
    super.initState();
    _loadFolder();
    SettingsStore().get('discovery').then((v) {
      if (mounted) setState(() => _discovery = v != 'off');
    });
  }

  Future<void> _toggleDiscovery(bool on) async {
    setState(() => _discovery = on);
    await setAutoDiscovery(on);
  }

  Future<void> _clearHistory() async {
    if (!await confirmClearAllHistory(context)) return;
    await SessionData().clearAllChatHistory();
    if (mounted) toast(context, 'Chat history cleared');
  }

  Future<void> _loadFolder() async {
    final dir = await receiveDirectory();
    if (mounted) setState(() => _folder = dir.path);
  }

  Future<void> _changeFolder() async {
    if (await pickReceiveFolder() != null) await _loadFolder();
  }

  Future<void> _resetFolder() async {
    await SettingsStore().set('receiveDir', null);
    await _loadFolder();
  }

  Future<void> _editName() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(initial: SessionData().userName ?? ''),
    );
    if (name == null || name.isEmpty || name == SessionData().userName) return;
    await renameUser(name);
    if (!mounted) return;
    setState(() {});
    toast(context, 'Name changed');
  }

  void _copyId() {
    final id = SessionData().userId;
    if (id == null) return;
    Clipboard.setData(ClipboardData(text: id));
    toast(context, 'Device ID copied');
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionData();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const FloatingAppBar(title: 'Settings', showBack: true),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: FloatingAppBar.maxWidth),
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      FloatingAppBar.sidePadding(context),
                      0,
                      FloatingAppBar.sidePadding(context),
                      24,
                    ),
                    children: [
                      _Section(title: 'User', children: [
                        ListTile(
                          leading: const Icon(Icons.person_outline),
                          title: const Text('Name'),
                          subtitle: Text(session.userName ?? ''),
                          trailing: const Icon(Icons.edit_outlined, size: 20),
                          onTap: _editName,
                        ),
                      ]),
                      _Section(title: 'Appearance', children: [
                        const ListTile(
                          leading: Icon(Icons.palette_outlined),
                          title: Text('Theme'),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: ValueListenableBuilder<ThemeMode>(
                            valueListenable: themeMode,
                            builder: (context, mode, _) => SizedBox(
                              width: double.infinity,
                              child: SegmentedButton<ThemeMode>(
                                showSelectedIcon: false,
                                segments: const [
                                  ButtonSegment(
                                    value: ThemeMode.system,
                                    label: Text('System'),
                                  ),
                                  ButtonSegment(
                                    value: ThemeMode.light,
                                    label: Text('Light'),
                                  ),
                                  ButtonSegment(
                                    value: ThemeMode.dark,
                                    label: Text('Dark'),
                                  ),
                                ],
                                selected: {mode},
                                onSelectionChanged: (s) => setThemeMode(s.first),
                              ),
                            ),
                          ),
                        ),
                      ]),
                      _Section(title: 'Network', children: [
                        SwitchListTile(
                          secondary: const Icon(Icons.wifi_tethering),
                          title: const Text('Auto discovery'),
                          subtitle: Text(
                            discoveryAllowed
                                ? 'Announce this device and search for others on the network (UDP)'
                                : 'Unavailable: disabled in config or TCP server failed',
                          ),
                          value: _discovery && discoveryAllowed,
                          onChanged: discoveryAllowed ? _toggleDiscovery : null,
                        ),
                      ]),
                      _Section(title: 'Files', children: [
                        ListTile(
                          leading: const Icon(Icons.folder_outlined),
                          title: const Text('Received files'),
                          subtitle: Text(_folder ?? '…'),
                          onTap: _changeFolder,
                          trailing: IconButton(
                            icon: const Icon(Icons.restore),
                            tooltip: 'Use default folder',
                            onPressed: _resetFolder,
                          ),
                        ),
                      ]),
                      _Section(title: 'Data', children: [
                        ListTile(
                          leading: const Icon(Icons.delete_sweep_outlined),
                          title: const Text('Clear all chat history'),
                          subtitle: const Text('Deletes saved conversations and stops saving'),
                          onTap: _clearHistory,
                        ),
                      ]),
                      _Section(title: 'Other', children: [
                        ListTile(
                          leading: const Icon(Icons.fingerprint),
                          title: const Text('Device ID'),
                          subtitle: Text(
                            session.userId ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.copy, size: 20),
                          onTap: _copyId,
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Material(
          color: cardColor(context),
          borderRadius: BorderRadius.circular(cardRadius),
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.initial});

  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Your name'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 32,
        textCapitalization: TextCapitalization.words,
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
