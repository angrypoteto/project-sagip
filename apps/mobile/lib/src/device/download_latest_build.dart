import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sagip_shared/sagip_shared.dart';

import '../app_version.dart';

/// Reads `latest.json` beside the APK on the download site (`{"build": 7}`).
/// Each deploy writes it together with the APK, so it always names the build
/// people will get.
class DownloadLatestBuild implements LatestBuildRepository {
  DownloadLatestBuild({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  static const _timeout = Duration(seconds: 10);

  @override
  Future<int?> fetch() async {
    try {
      final response = await _client
          .get(Uri.parse(appLatestUrl))
          .timeout(_timeout);
      if (response.statusCode != 200) return null;
      final json = jsonDecode(response.body);
      if (json is! Map) return null;
      return (json['build'] as num?)?.toInt();
    } on Object {
      return null;
    }
  }
}
