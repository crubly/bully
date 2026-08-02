import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/desktop_window.dart';
import '../../core/media/media_cache.dart';
import '../../core/network/bandwidth_tracker.dart';
import '../../theme/bully_theme.dart';

class DataUsageScreen extends StatefulWidget {
  final bool embedded;
  const DataUsageScreen({super.key, this.embedded = false});

  @override
  State<DataUsageScreen> createState() => _DataUsageScreenState();
}

class _DataUsageScreenState extends State<DataUsageScreen> {
  bool _autoSave = MediaCache.autoSaveEnabled;
  int _autoDeleteDays = MediaCache.autoDeleteAfterDays;
  int _cacheBytes = 0;
  String _savePath = '';

  @override
  void initState() {
    super.initState();
    MediaCache.currentCacheSizeBytes().then((v) {
      if (mounted) setState(() => _cacheBytes = v);
    });
    MediaCache.effectiveSaveDirectoryPath().then((v) {
      if (mounted) setState(() => _savePath = v);
    });
  }

  Future<void> _pickSaveDirectory() async {
    final path = await FilePicker.getDirectoryPath();
    if (path == null) return;
    await MediaCache.setSaveDirectoryPath(path);
    if (mounted) setState(() => _savePath = path);
  }

  Future<void> _resetSaveDirectory() async {
    await MediaCache.setSaveDirectoryPath(null);
    final path = await MediaCache.effectiveSaveDirectoryPath();
    if (mounted) setState(() => _savePath = path);
  }

  String _fmtBytes(int bytes) {
    if (bytes < 1024) return '$bytes Б';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} КБ';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} ГБ';
  }

  Widget _body(BuildContext context) {
    return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Интернет-трафик', style: TextStyle(color: BullyPalette.of(context).textMuted, fontSize: 12)),
          ),
          ListTile(
            title: Text('Сегодня', style: TextStyle(color: BullyPalette.of(context).textNormal)),
            trailing: Text(_fmtBytes(BandwidthTracker.totalOverLastDays(1)), style: TextStyle(color: BullyPalette.of(context).textMuted)),
          ),
          ListTile(
            title: Text('7 дней', style: TextStyle(color: BullyPalette.of(context).textNormal)),
            trailing: Text(_fmtBytes(BandwidthTracker.totalOverLastDays(7)), style: TextStyle(color: BullyPalette.of(context).textMuted)),
          ),
          ListTile(
            title: Text('30 дней', style: TextStyle(color: BullyPalette.of(context).textNormal)),
            trailing: Text(_fmtBytes(BandwidthTracker.totalOverLastDays(30)), style: TextStyle(color: BullyPalette.of(context).textMuted)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(
              'Трафик держится примерно постоянным независимо от активности — это защита от анализа трафика '
              '(роутер/провайдер не должен видеть момент отправки сообщения). Локальная синхронизация между '
              'вашими устройствами сюда не входит — это трафик локальной сети, а не интернета.',
              style: TextStyle(color: BullyPalette.of(context).textMuted, fontSize: 12),
            ),
          ),
          Divider(color: BullyPalette.of(context).bgTertiary),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('Медиафайлы', style: TextStyle(color: BullyPalette.of(context).textMuted, fontSize: 12)),
          ),
          SwitchListTile(
            title: Text('Автосохранение фото/видео', style: TextStyle(color: BullyPalette.of(context).textNormal)),
            subtitle: Text('Сохранять полученные медиа в галерею устройства', style: TextStyle(color: BullyPalette.of(context).textMuted)),
            value: _autoSave,
            onChanged: (v) async {
              await MediaCache.setAutoSaveEnabled(v);
              setState(() => _autoSave = v);
            },
          ),
          ListTile(
            title: Text('Автоудаление из кэша приложения', style: TextStyle(color: BullyPalette.of(context).textNormal)),
            subtitle: Text(
              _autoDeleteDays <= 0 ? 'Никогда' : 'Через $_autoDeleteDays дн.',
              style: TextStyle(color: BullyPalette.of(context).textMuted),
            ),
            trailing: DropdownButton<int>(
              value: _autoDeleteDays,
              dropdownColor: BullyPalette.of(context).bgSecondary,
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
            child: Text('Кэш медиа на этом устройстве: ${_fmtBytes(_cacheBytes)}', style: TextStyle(color: BullyPalette.of(context).textMuted, fontSize: 12)),
          ),
          if (DesktopWindow.isDesktop) ...[
            Divider(color: BullyPalette.of(context).bgTertiary),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('Папка для сохранения', style: TextStyle(color: BullyPalette.of(context).textMuted, fontSize: 12)),
            ),
            ListTile(
              title: Text(_savePath, style: TextStyle(color: BullyPalette.of(context).textNormal), overflow: TextOverflow.ellipsis),
              subtitle: Text('Куда сохранять скачанные медиафайлы', style: TextStyle(color: BullyPalette.of(context).textMuted)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(icon: const Icon(Icons.folder_open), tooltip: 'Выбрать папку', onPressed: _pickSaveDirectory),
                  IconButton(icon: const Icon(Icons.restart_alt), tooltip: 'Сбросить по умолчанию', onPressed: _resetSaveDirectory),
                ],
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              'Если автосохранение включено, файл копируется в системную галерею/загрузки устройства — '
              'оттуда приложение удалить его уже не может, удалять нужно вручную средствами ОС. '
              'Автоудаление касается только внутреннего кэша самого приложения.',
              style: TextStyle(color: BullyPalette.of(context).textMuted, fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ),
        ],
      );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) return _body(context);
    return Scaffold(
      backgroundColor: BullyPalette.of(context).bgPrimary,
      appBar: AppBar(backgroundColor: BullyPalette.of(context).bgPrimary, title: const Text('Данные и память')),
      body: _body(context),
    );
  }
}
