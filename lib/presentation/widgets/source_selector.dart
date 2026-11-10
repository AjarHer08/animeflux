/// Source selector — segment button untuk pilih sumber anime (3).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';

class SourceSelector extends ConsumerWidget {
  final SourceId value;
  final ValueChanged<SourceId> onChanged;
  final bool compact;

  const SourceSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    if (compact) {
      return SegmentedButton<SourceId>(
        style: SegmentedButton.styleFrom(
          backgroundColor: scheme.surfaceContainer,
          selectedBackgroundColor: scheme.primaryContainer,
          selectedForegroundColor: scheme.onPrimaryContainer,
        ),
        segments: SourceId.values
            .map((s) => ButtonSegment(value: s, label: Text(s.label)))
            .toList(),
        selected: {value},
        onSelectionChanged: (s) => onChanged(s.first),
      );
    }

    return Wrap(
      spacing: 8,
      children: SourceId.values.map((s) {
        final active = s == value;
        return FilterChip(
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _iconFor(s),
                size: 14,
                color: active ? scheme.onPrimaryContainer : scheme.primary,
              ),
              const SizedBox(width: 6),
              Text(s.label),
            ],
          ),
          selected: active,
          onSelected: (_) => onChanged(s),
          selectedColor: scheme.primaryContainer,
          labelStyle: TextStyle(
            color: active ? scheme.onPrimaryContainer : scheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
          backgroundColor: scheme.surfaceContainer,
          side: BorderSide(color: scheme.outlineVariant),
          showCheckmark: false,
        );
      }).toList(),
    );
  }

  IconData _iconFor(SourceId s) {
    switch (s) {
      case SourceId.otakudesu:
        return Icons.tv;
      case SourceId.hidoristream:
        return Icons.stream;
      case SourceId.lendrive:
        return Icons.download_for_offline;
    }
  }
}
