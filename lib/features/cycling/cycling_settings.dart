import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'platform/ride_platform.dart';

class CyclingSettings extends ConsumerStatefulWidget {
  const CyclingSettings({super.key});
  @override
  ConsumerState<CyclingSettings> createState() => _CyclingSettingsState();
}

class _CyclingSettingsState extends ConsumerState<CyclingSettings> {
  Map<String, dynamic>? settings;
  String? error;
  bool saving = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final value = await ref.read(ridePlatformProvider).settings();
      if (mounted) setState(() => settings = value);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> save() async {
    setState(() => saving = true);
    try {
      await ref.read(ridePlatformProvider).saveSettings(settings!);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Cycling settings')),
    body: settings == null
        ? Center(
            child: error == null
                ? const CircularProgressIndicator()
                : Text(error!),
          )
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              DropdownButtonFormField<String>(
                initialValue: settings!['interval'] as String? ?? 'off',
                decoration: const InputDecoration(labelText: 'Spoken updates'),
                items: const [
                  DropdownMenuItem(value: 'off', child: Text('Disabled')),
                  DropdownMenuItem(value: 'mile', child: Text('Every 1 mile')),
                  DropdownMenuItem(
                    value: 'halfMile',
                    child: Text('Every 0.5 mile'),
                  ),
                  DropdownMenuItem(
                    value: '5min',
                    child: Text('Every 5 minutes'),
                  ),
                  DropdownMenuItem(
                    value: '10min',
                    child: Text('Every 10 minutes'),
                  ),
                ],
                onChanged: saving
                    ? null
                    : (value) => setState(() => settings!['interval'] = value),
              ),
              for (final pair in const [
                ('distance', 'Distance'),
                ('duration', 'Duration'),
                ('average', 'Average speed'),
                ('speed', 'Current speed'),
              ])
                CheckboxListTile(
                  title: Text(pair.$2),
                  value: (settings!['measurements'] as List).contains(pair.$1),
                  onChanged: saving
                      ? null
                      : (on) => setState(() {
                          final selected = List<String>.from(
                            settings!['measurements'] as List,
                          );
                          if (on == true) {
                            selected.add(pair.$1);
                          } else {
                            selected.remove(pair.$1);
                          }
                          settings!['measurements'] = selected;
                        }),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: saving ? null : save,
                child: const Text('Save'),
              ),
              if (error != null) Text(error!),
              const Divider(height: 32),
              const Text(
                'Ride data stays on this device. Map images load from OpenStreetMap and need internet; GPS recording does not. Only viewed tiles are cached; offline region downloads are not supported.',
              ),
              TextButton(
                onPressed: () => ref.read(ridePlatformProvider).attribution(),
                child: const Text('OpenStreetMap attribution'),
              ),
              TextButton(
                onPressed: () =>
                    ref.read(ridePlatformProvider).openSettings('battery'),
                child: const Text('Battery settings'),
              ),
              TextButton(
                onPressed: () =>
                    ref.read(ridePlatformProvider).openSettings('app'),
                child: const Text('Location and notification permissions'),
              ),
              const Text(
                'For screen-off recording, keep the ride notification enabled. Battery restrictions, force-stop, or device shutdown can interrupt capture; interrupted rides reopen paused at their last saved checkpoint.',
              ),
            ],
          ),
  );
}
