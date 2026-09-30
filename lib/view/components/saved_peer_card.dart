import 'package:flutter/material.dart';
import 'package:locsand/view/components/card_style.dart';

class SavedPeerCard extends StatelessWidget {
  const SavedPeerCard({
    super.key,
    required this.name,
    required this.subtitle,
    required this.connected,
    required this.onTap,
    required this.onForget,
  });

  final String name;
  final String subtitle;
  final bool connected;
  final VoidCallback onTap;
  final VoidCallback onForget;

  static const double width = 172;
  static const double height = 176;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final initial = name.isEmpty ? '?' : name[0].toUpperCase();

    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: cardColor(context),
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: scheme.primaryContainer,
                      foregroundColor: scheme.onPrimaryContainer,
                      child: Text(
                        initial,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const Spacer(),
                    PopupMenuButton<String>(
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.more_vert, size: 20),
                      onSelected: (value) {
                        if (value == 'forget') onForget();
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'forget', child: Text('Forget')),
                      ],
                    ),
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
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.circle,
                      size: 8,
                      color: connected ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      connected ? 'Connected' : 'Offline',
                      style: theme.textTheme.bodySmall,
                    ),
                    const Spacer(),
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                      child: const Icon(Icons.chat_bubble_outline, size: 16),
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