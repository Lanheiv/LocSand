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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    const radius = BorderRadius.only(
      topLeft: Radius.circular(20),
      topRight: Radius.circular(44),
      bottomLeft: Radius.circular(20),
      bottomRight: Radius.circular(20),
    );

    return Material(
      color: cardColor(context),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.devices_rounded,
                      size: 22,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const Spacer(),
                  if (saved)
                    Icon(Icons.bookmark_rounded, size: 22, color: Colors.amber),
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
                  Icon(
                    Icons.circle,
                    size: 8,
                    color: connected ? Colors.green : Colors.grey,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      saved ? 'Saved · $address' : address,
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
    );
  }
}