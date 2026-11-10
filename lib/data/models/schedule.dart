/// Model Schedule — jadwal rilisan per hari.
library;

import 'package:equatable/equatable.dart';

import '../../core/constants.dart';

class ScheduleEntry extends Equatable {
  final SourceId source;
  final String day;
  final String animeTitle;
  final String? animeUrl;
  final String? time;

  const ScheduleEntry({
    required this.source,
    required this.day,
    required this.animeTitle,
    this.animeUrl,
    this.time,
  });

  @override
  List<Object?> get props => [source, day, animeTitle, animeUrl];
}

class DaySchedule extends Equatable {
  final String day;
  final List<ScheduleEntry> entries;

  const DaySchedule({required this.day, required this.entries});

  @override
  List<Object?> get props => [day];
}
