/// Formats acceptés pour les photos, vidéos et fichiers (produits, boutiques, annonces, messagerie).
/// JPEG/JPG, PNG, WebP, GIF : affichés partout. AVIF : accepté ; l'affichage dépend de l'appareil (navigateurs récents, Android récent).
class MediaFormats {
  static const imageMimes = <String, String>{
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'jfif': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'avif': 'image/avif',
    'gif': 'image/gif',
  };
  static const videoMimes = <String, String>{'mp4': 'video/mp4', 'webm': 'video/webm', 'mov': 'video/quicktime'};
  static const docMimes = <String, String>{
    'pdf': 'application/pdf',
    'txt': 'text/plain',
    'doc': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'mp3': 'audio/mpeg',
    'm4a': 'audio/mp4',
    'aac': 'audio/aac',
  };

  static const imageHelp = 'JPEG/JPG, PNG, WebP, AVIF ou GIF';

  static String ext(String name) => name.contains('.') ? name.split('.').last.toLowerCase() : '';
  static String? image(String name) => imageMimes[ext(name)];
  static String? video(String name) => videoMimes[ext(name)];
  static String? doc(String name) => docMimes[ext(name)];

  static String size(int bytes) {
    if (bytes < 1024) return '$bytes o';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} Ko';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} Mo';
  }
}
