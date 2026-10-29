import 'package:flutter/material.dart';
import 'package:record/record.dart';

import 'app_scope.dart';
import 'theme.dart';

/// Lets the user pick which microphone to record from. "Padrão do sistema"
/// follows the default recording device set in the OS sound settings.
Future<void> showMicPicker(BuildContext context) {
  final scope = AppScope.of(context);
  return showDialog<void>(
    context: context,
    builder: (context) => FutureBuilder<List<InputDevice>>(
      future: scope.recorder.inputDevices(),
      builder: (context, snapshot) {
        final settings = scope.store.settings;
        final devices = snapshot.data ?? const <InputDevice>[];
        Future<void> choose(String? id, String? label) async {
          await scope.store.setInputDevice(id: id, label: label);
          if (context.mounted) Navigator.pop(context);
        }

        return SimpleDialog(
          title: const Text('Microfone'),
          children: [
            _Option(
              icon: Icons.settings_voice_outlined,
              label: 'Padrão do sistema',
              subtitle: 'O microfone escolhido nas configurações de som',
              selected: settings.inputDeviceId == null,
              onTap: () => choose(null, null),
            ),
            if (snapshot.connectionState != ConnectionState.done)
              const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
            else if (snapshot.hasError)
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 8),
                child: Text('Não foi possível listar os microfones.', style: TextStyle(color: VL.error)),
              )
            else
              for (final d in devices)
                _Option(
                  icon: _iconFor(d.type),
                  label: d.label.isEmpty ? 'Microfone' : d.label,
                  selected: settings.inputDeviceId == d.id,
                  onTap: () => choose(d.id, d.label),
                ),
            if (settings.inputDeviceId != null &&
                snapshot.connectionState == ConnectionState.done &&
                !devices.any((d) => d.id == settings.inputDeviceId))
              _Option(
                icon: Icons.mic_off_outlined,
                label: settings.inputDeviceLabel ?? 'Microfone escolhido',
                subtitle: 'Desconectado: será usado o padrão do sistema',
                selected: true,
                onTap: () => choose(settings.inputDeviceId, settings.inputDeviceLabel),
              ),
          ],
        );
      },
    ),
  );
}

IconData _iconFor(InputDeviceType type) => switch (type) {
      InputDeviceType.bluetoothSco || InputDeviceType.bluetoothA2dp || InputDeviceType.bluetoothLe =>
        Icons.bluetooth_audio,
      InputDeviceType.wiredHeadset => Icons.headset_mic_outlined,
      InputDeviceType.usb => Icons.usb,
      _ => Icons.mic_none_outlined,
    };

class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SimpleDialogOption(
        onPressed: onTap,
        child: Row(children: [
          Icon(icon, size: 20, color: VL.textDim),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, overflow: TextOverflow.ellipsis),
              if (subtitle != null)
                Text(subtitle!, style: const TextStyle(color: VL.textFaint, fontSize: 12)),
            ]),
          ),
          if (selected) const Icon(Icons.check, size: 18, color: VL.success),
        ]),
      );
}
