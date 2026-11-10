/// Model Genre.
library;

import 'package:equatable/equatable.dart';

class Genre extends Equatable {
  final String name;
  final String? slug;
  final String? url;

  const Genre({required this.name, this.slug, this.url});

  Map<String, dynamic> toJson() => {'name': name, 'slug': slug, 'url': url};

  factory Genre.fromJson(Map<String, dynamic> json) => Genre(
        name: json['name'] as String,
        slug: json['slug'] as String?,
        url: json['url'] as String?,
      );

  @override
  List<Object?> get props => [name];
}
