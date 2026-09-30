import 'package:flutter/material.dart';

import 'package:locsand/src/helpers/receive_folder.dart';
import 'package:locsand/src/helpers/settings_store.dart';
import 'package:locsand/view/components/floating_app_bar.dart';

class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  String? _folder;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dir = await receiveDirectory();
    if (mounted) setState(() => _folder = dir.path);
  }

  Future<void> _change() async {
    if (await pickReceiveFolder() != null) await _load();
  }

  Future<void> _reset() async {
    await SettingsStore().setReceiveDir(null);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
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
                    padding: EdgeInsets.symmetric(
                      horizontal: FloatingAppBar.sidePadding(context),
                    ),
                    children: [
                      ListTile(
                        leading: const Icon(Icons.folder_outlined),
                        title: const Text('Received files'),
                        subtitle: Text(_folder ?? '…'),
                        onTap: _change,
                        trailing: IconButton(
                          icon: const Icon(Icons.restore),
                          tooltip: 'Use default folder',
                          onPressed: _reset,
                        ),
                      ),
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
