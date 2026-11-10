/// Card anime untuk grid — pakai cached_network_image dengan shimmer.
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/anime.dart';

class AnimeCard extends ConsumerWidget {
  final Anime anime;
  final VoidCallback? onTap;
  final double? aspectRatio;

  const AnimeCard({super.key, required this.anime, this.onTap, this.aspectRatio});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final mq = MediaQuery.sizeOf(context);
    final cardWidth = (mq.width - 32 - 16) / 2;
    return Material(
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: cardWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: aspectRatio ?? 2 / 3,
                child: anime.cover == null || anime.cover!.isEmpty
                    ? Container(
                        color: scheme.surfaceContainerHighest,
                        child: Icon(Icons.movie, color: scheme.primary, size: 48),
                      )
                    : CachedNetworkImage(
                        imageUrl: anime.cover!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => ShimmerBox(
                          width: cardWidth,
                          height: cardWidth * 1.5,
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: scheme.surfaceContainerHighest,
                          child: Icon(Icons.broken_image, color: scheme.primary),
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      anime.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    if (anime.status != null || anime.episodeCount != null)
                      Row(
                        children: [
                          if (anime.status != null)
                            Flexible(
                              child: Text(
                                anime.status!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          if (anime.status != null && anime.episodeCount != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: Text('•', style: TextStyle(color: scheme.outline, fontSize: 11)),
                            ),
                          if (anime.episodeCount != null)
                            Text(
                              'EP ${anime.episodeCount}',
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.outline,
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ShimmerBox extends StatelessWidget {
  final double width;
  final double height;
  const ShimmerBox({super.key, required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.grey.shade800,
            Colors.grey.shade700,
            Colors.grey.shade800,
          ],
        ),
      ),
    );
  }
}
