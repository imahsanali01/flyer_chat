import 'package:package_info_plus/package_info_plus.dart';

Future<String> getAppVersionString() async {
  final info = await PackageInfo.fromPlatform();
  return 'v ${info.version} (build ${info.buildNumber})';
} 