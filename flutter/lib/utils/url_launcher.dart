import 'package:url_launcher/url_launcher.dart' as platform;

export 'package:url_launcher/url_launcher.dart' hide launchUrl;
export 'package:url_launcher/url_launcher_string.dart' hide launchUrlString;

bool isOfficialUrl(Uri url) {
  final host = url.host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
  return host == 'rustdesk.com' || host.endsWith('.rustdesk.com');
}

Future<bool> launchUrl(Uri url,
    {platform.LaunchMode mode = platform.LaunchMode.platformDefault}) async {
  if (isOfficialUrl(url)) return false;
  return platform.launchUrl(url, mode: mode);
}

Future<bool> launchUrlString(String url,
    {platform.LaunchMode mode = platform.LaunchMode.platformDefault}) {
  return launchUrl(Uri.parse(url), mode: mode);
}
