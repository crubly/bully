import 'package:flutter/material.dart';

import '../../core/media/media_cache.dart';
import '../../core/network/bandwidth_tracker.dart';
import '../../theme/discord_theme.dart';

class DataUsageScreen extends StatefulWidget {
  const DataUsageScreen({super.key});

  @override
  State<DataUsageScreen> createState() => _DataUsageScreenState();
}

class _DataUsageScreenState extends State<DataUsageScreen> {
  bool _autoSave = MediaCache.autoSaveEnabled;
  int _autoDeleteDays = MediaCache.autoDeleteAfterDays;
  int _cacheBytes = 0;

  @override
  void initState() {
    super.initState();
    MediaCache.currentCacheSizeBytes().then((v) {
      if (mounted) setState(() => _cacheBytes = v);
    });
  }

  String _fmtBytes(int bytes) {
    if (bytes < 1024) return '$bytes Б';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} КБ';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} ГБ';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DiscordColors.bgPrimary,
      appBar: AppBar(backgroundColor: DiscordColors.bgPrimary, title: const Text('Данные и память')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Интернет-трафик', style: TextStyle(color: DiscordColors.textMuted, fontSize: 12)),
          ),
          ListTile(
            title: const Text('Сегодня', style: TextStyle(color: DiscordColors.textNormal)),
            trailing: Text(_fmtBytes(BandwidthTracker.totalOverLastDays(1)), style: const TextStyle(color: DiscordColors.textMuted)),
          ),
          ListTile(
            title: const Text('7 дней', style: TextStyle(color: DiscordColors.textNormal)),
            trailing: Text(_fmtBytes(BandwidthTracker.totalOverLastDays(7)), style: const TextStyle(color: DiscordColors.textMuted)),
          ),
          ListTile(
            title: const Text('30 дней', style: TextStyle(color: DiscordColors.textNormal)),
            trailing: Text(_fmtBytes(BandwidthTracker.totalOverLastDays(30)), style: const TextStyle(color: DiscordColors.textMuted)),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(
              'Трафик держится примерно постоянным независимо от активности — это защита от анализа трафика '
              '(роутер/провайдер не должен видеть момент отправки сообщения). Локальная синхронизация между '
              'вашими устройствами сюда не входит — это трафик локальной сети, а не интернета.',
              style: TextStyle(color: DiscordColors.textMuted, fontSize: 12),
            ),
          ),
          const Divider(color: DiscordColors.bgTertiary),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('Медиафайлы', style: TextStyle(color: DiscordColors.textMuted, fontSize: 12)),
          ),
          SwitchListTile(
            title: const Text('Автосохранение фото/видео', style: TextStyle(color: DiscordColors.textNormal)),
            subtitle: const Text('Сохранять полученные медиа в галерею устройства', style: TextStyle(color: DiscordColors.textMuted)),
            value: _autoSave,
            onChanged: (v) async {
              await MediaCache.setAutoSaveEnabled(v);
              setState(() => _autoSave = v);
            },
          ),
          ListTile(
            title: const Text('Автоудаление из кэша приложения', style: TextStyle(color: DiscordColors.textNormal)),
            subtitle: Text(
              _autoDeleteDays <= 0 ? 'Никогда' : 'Через $_autoDeleteDays дн.',
              style: const TextStyle(color: DiscordColors.textMuted),
            ),
            trailing: DropdownButton<int>(
              value: _autoDeleteDays,
              dropdownColor: DiscordColors.bgSecondary,
              items: const [0, 1, 3, 7, 14, 30]
                  .map((d) => DropdownMenuItem(value: d, child: Text(d == 0 ? 'Никогда' : '$d дн.')))
                  .toList(),
              onChanged: (v) async {
                if (v == null) return;
                await MediaCache.setAutoDeleteAfterDays(v);
                setState(() => _autoDeleteDays = v);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text('Кэш медиа на этом устройстве: ${_fmtBytes(_cacheBytes)}', style: const TextStyle(color: DiscordColors.textMuted, fontSize: 12)),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              'Если автосохранение включено, файл копируется в системную галерею/загрузки устройства — '
              'оттуда приложение удалить его уже не может, удалять нужно вручную средствами ОС. '
              'Автоудаление касается только внутреннего кэша самого приложения.',
              style: TextStyle(color: DiscordColors.textMuted, fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ),
        ],
      ),
    );
  }
}
