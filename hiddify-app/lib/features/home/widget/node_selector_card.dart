import 'package:flutter/material.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/home/widget/node_list_card.dart';
import 'package:hiddify/features/home/widget/node_list_sheet.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/proxy/active/ip_widget.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class NodeSelectorCard extends HookConsumerWidget {
  const NodeSelectorCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final connectionStatus = ref.watch(
      connectionNotifierProvider.select((v) => v.valueOrNull ?? const Disconnected()),
    );
    final isConnected = connectionStatus == const Connected();
    final activeProxy = ref.watch(activeProxyNotifierProvider).valueOrNull;

    final String title;
    final String subtitle;
    final Widget leading;

    if (isConnected && activeProxy != null) {
      final cc = NodeListCard.inferCountryCode(
        activeProxy.tagDisplay,
        activeProxy.ipinfo.countryCode,
      );
      title = NodeListCard.cleanTag(activeProxy.tagDisplay);
      final delay = activeProxy.urlTestDelay;
      subtitle = (delay > 0 && delay < 65000) ? '${delay}ms' : '';
      leading = IPCountryFlag(countryCode: cc, organization: activeProxy.ipinfo.org, size: 24);
    } else {
      title = '选择节点';
      subtitle = '自动匹配最快网络';
      leading = Icon(Icons.public_rounded, size: 24, color: theme.colorScheme.primary);
    }

    return GestureDetector(
      onTap: () => showNodeListSheet(context),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 32),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
