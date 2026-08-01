import 'dart:typed_data';
import 'dart:ui' as ui;

/// Guards every avatar (own upload and every peer's incoming one) against
/// malformed/malicious image payloads before it's ever stored, displayed,
/// or forwarded to someone else. A bare file-extension or MIME-type check
/// isn't enough — a hostile peer could send arbitrary bytes labeled as an
/// image specifically to attack an image decoder (yours, or the next
/// contact's if we blindly re-share/relay it). Actually decoding it with
/// the platform image codec is the real validation: if it doesn't decode,
/// or decodes to something absurd, it's rejected outright.
class ImageValidator {
  static const maxDimension = 4096;
  static const minDimension = 1;

  /// Returns null if valid, or a human-readable rejection reason.
  static Future<String?> validate(Uint8List bytes) async {
    if (bytes.isEmpty) return 'Пустой файл';
    if (bytes.length > 2 * 1024 * 1024) return 'Файл больше 2 МБ';

    ui.Codec codec;
    try {
      codec = await ui.instantiateImageCodec(bytes);
    } catch (_) {
      return 'Это не похоже на настоящее изображение';
    }

    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;
      if (image.width < minDimension || image.height < minDimension) {
        return 'Изображение повреждено';
      }
      if (image.width > maxDimension || image.height > maxDimension) {
        return 'Слишком большое разрешение (максимум $maxDimension×$maxDimension)';
      }
      return null;
    } catch (_) {
      return 'Не удалось декодировать изображение';
    } finally {
      codec.dispose();
    }
  }
}
