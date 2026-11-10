/// Model sumber anime — menampung metadata sumber dan URL dasar.
library;

import 'package:equatable/equatable.dart';

import '../../core/constants.dart';

class AnimeSource extends Equatable {
  final SourceId id;
  final String baseUrl;

  const AnimeSource({required this.id, required this.baseUrl});

  factory AnimeSource.fromId(SourceId id) => AnimeSource(id: id, baseUrl: id.baseUrl);

  String get label => id.label;

  @override
  List<Object?> get props => [id, baseUrl];
}
