import 'package:equatable/equatable.dart';

import '../../../app/constants/api_constants.dart';
import '../../../core/network/api_client.dart';

/// A CMS content page (About / Contact / Careers / Terms / Privacy) served
/// from the backend's public `/content/pages/{slug}` endpoint.
class ContentPage extends Equatable {
  const ContentPage({
    required this.slug,
    required this.title,
    required this.body,
  });

  final String slug;
  final String title;
  final String body;

  @override
  List<Object?> get props => [slug, title, body];
}

/// Backend CMS API: `/content/pages/{slug}` (public — no auth header).
class ContentRemoteDataSource {
  ContentRemoteDataSource(this._client);
  final ApiClient _client;

  Map<String, dynamic> _obj(dynamic raw) {
    final data = raw is Map && raw['data'] is Map ? raw['data'] : raw;
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<ContentPage> getPage(String slug) async {
    final res = await _client.get<dynamic>(
      ApiConstants.contentPage(slug),
      options: ApiClient.noAuth(),
    );
    final j = _obj(res.data);
    return ContentPage(
      slug: (j['slug'] ?? slug).toString(),
      title: (j['title'] ?? '').toString(),
      body: (j['body'] ?? '').toString(),
    );
  }
}
