/// App-wide constants for storage paths and file naming.
///
/// Centralised here so the data layer and gallery always agree on the
/// directory name, filename format, and image encoding without importing
/// each other.
abstract final class AppConstants {
  /// Sub-directory created inside the app's documents directory.
  static const String drawingsFolder = 'doodlingz_drawings';

  /// PNG is lossless — no quality degradation on save or re-open for editing.
  static const String fileExtension = 'png';

  /// Prefix prepended to every saved drawing filename.
  static const String filePrefix = 'drawing_';

  /// Timestamp pattern appended after the prefix.
  /// Produces filenames like: drawing_20260612_143205_342.png
  /// The millisecond component avoids collisions on rapid saves.
  static const String timestampPattern = 'yyyyMMdd_HHmmss_SSS';

  /// Full filename for a given timestamp string.
  static String fileName(String timestamp) =>
      '$filePrefix$timestamp.$fileExtension';
}
