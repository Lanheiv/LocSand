import 'package:flutter/material.dart';
import 'package:locsand/view/components/card_style.dart';

class NearbyPeerCard extends StatelessWidget {
  const NearbyPeerCard({
    super.key,
    required this.name,
    required this.address,
    required this.connected,
    required this.saved,
    required this.onTap,
  });

  final String name;
  final String address;
  final bool connected;
  final bool saved;
  final VoidCallback onTap;

  static const double width = 180;
  static const double height = 136;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: cardColor(context),
        borderRadius: BorderRadius.circular(cardRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: scheme.primaryContainer,
                      foregroundColor: scheme.onPrimaryContainer,
                      child: const Icon(Icons.devices_rounded, size: 22),
                    ),
                    const Spacer(),
                    if (saved)
                      const Icon(Icons.bookmark_rounded, size: 22, color: Colors.amber),
                  ],
                ),
                const Spacer(),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    StatusDot(active: connected),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
