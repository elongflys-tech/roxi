import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/features/auth/data/auth_i18n.dart';
import 'package:hiddify/features/auth/data/auth_service.dart';
import 'package:hiddify/features/auth/widget/plans_page.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/proxy/active/ip_widget.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Collapsible node list card for the home page.
class NodeListCard extends HookConsumerWidget {
  const NodeListCard({super.key});

  /// Clean internal labels from node display name.
  /// 良心云共享节点: "|免费" → "|共享"
  /// 自有保底节点: "|保底" → "|体验"
  static String cleanTag(String tag) {
    var cleaned = tag
        .replaceAll('|保底', '|体验')
        .replaceAll('保底', '体验')
        .replaceAll('|免费', '|共享')
        .replaceAll('|fallback', '|体验')
        .trim();
    // If after cleaning it's just a bare country name, append "|体验"
    if (RegExp(r'^[\p{So}\p{Cn}\s]*[\u4e00-\u9fff]+$', unicode: true).hasMatch(cleaned)) {
      final country = RegExp(r'[\u4e00-\u9fff]+').firstMatch(cleaned)?.group(0) ?? '';
      cleaned = '$country|体验';
    }
    return cleaned;
  }

  /// Infer country code from tag display name when countryCode is empty.
  static String inferCountryCode(String tagDisplay, String? countryCode) {
    if (countryCode != null && countryCode.isNotEmpty) return countryCode;
    const map = {
      '新加坡': 'sg', '日本': 'jp', '香港': 'hk', '台湾': 'tw',
      '美国': 'us', '韩国': 'kr', '英国': 'gb', '德国': 'de',
      '法国': 'fr', '澳大利亚': 'au', '加拿大': 'ca', '印度': 'in',
      '荷兰': 'nl', '俄罗斯': 'ru', '巴西': 'br', '土耳其': 'tr',
      'Singapore': 'sg', 'Japan': 'jp', 'Hong Kong': 'hk',
      'Taiwan': 'tw', 'US': 'us', 'Korea': 'kr', 'UK': 'gb',
      'Germany': 'de', 'France': 'fr', 'Australia': 'au',
    };
    for (final entry in map.entries) {
      if (tagDisplay.contains(entry.key)) return entry.value;
    }
    return '';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final expanded = useState(false);

    final connectionStatus = ref.watch(
      connectionNotifierProvider.select((v) => v.valueOrNull ?? const Disconnected()),
    );
    final isConnected = connectionStatus == const Connected();
    final activeProxy = ref.watch(activeProxyNotifierProvider).valueOrNull;
    final proxiesAsync = ref.watch(proxiesOverviewNotifierProvider);
    final activeProfile = ref.watch(activeProfileProvider).valueOrNull;

    // Showcase nodes for disconnected state
    final showcaseNodes = useState<List<Map<String, dynamic>>>([]);
    useEffect(() {
      if (!isConnected) {
        () async {
          final prefs = await SharedPreferences.getInstance();
          final auth = AuthService(prefs);
          showcaseNodes.value = await auth.getShowcaseNodes();
        }();
      }
      return null;
    }, [isConnected]);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: theme.colorScheme.surfaceContainer,
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () {
              expanded.value = !expanded.value;
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  if (activeProxy != null)
                    IPCountryFlag(
                      countryCode: NodeListCard.inferCountryCode(activeProxy.tagDisplay, activeProxy.ipinfo.countryCode),
                      organization: activeProxy.ipinfo.org,
                      size: 28,
                    )
                  else
                    Icon(Icons.public_rounded, size: 28, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isConnected
                              ? NodeListCard.cleanTag(activeProxy?.tagDisplay ?? '选择节点中...')
                              : AuthI18n.t['tapToConnect']!,
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (!isConnected)
                          Text(
                            AuthI18n.t['autoSelectFastest']!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          )
                        else if (activeProxy != null && activeProxy.urlTestDelay > 0 && activeProxy.urlTestDelay < 65000)
                          Text(
                            '${activeProxy.urlTestDelay}ms · ${activeProxy.type}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: _delayColor(activeProxy.urlTestDelay),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Refresh subscription button
                  if (activeProfile != null && activeProfile is RemoteProfileEntity)
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      onPressed: () {
                        ref.read(proxiesOverviewNotifierProvider.notifier).unfreezeSort();
                        ref.read(updateProfileNotifierProvider(activeProfile.id).notifier)
                            .updateProfile(activeProfile as RemoteProfileEntity);
                      },
                      tooltip: '刷新订阅',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    ),
                  // URL test button
                  if (isConnected)
                    IconButton(
                    icon: const Icon(Icons.flash_on_rounded, size: 20),
                    onPressed: () async {
                      ref.read(proxiesOverviewNotifierProvider.notifier).unfreezeSort();
                      await ref.read(proxiesOverviewNotifierProvider.notifier).urlTest("select");
                    },
                    tooltip: '测速',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                  Icon(
                    expanded.value ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          // Expanded node list — prefer real (offline-parsed/cached) data,
          // fall back to showcase nodes, then show empty state.
          if (expanded.value)
            proxiesAsync.when(
              data: (group) {
                final realNodes = (group?.items ?? [])
                    .where((n) => !n.isGroup && n.tag.isNotEmpty)
                    .toList();

                // Have real nodes (from offline parsing, cache, or live) — show them
                if (realNodes.isNotEmpty) {
                  // Prefer optimistic selection (instant) over activeProxy (delayed).
                  final activeTag = (group?.selected.isNotEmpty == true)
                      ? group!.selected
                      : (activeProxy?.tag ?? '');
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Divider(height: 1),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 280),
                        child: ListView.builder(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: realNodes.length,
                          itemBuilder: (ctx, i) {
                            final node = realNodes[i];
                            final isSelected = node.tag == activeTag;
                            return _NodeRow(
                              node: node,
                              isSelected: isSelected,
                              onTap: () {
                                if (!isConnected) {
                                  ref.read(connectionNotifierProvider.notifier).toggleConnection();
                                  return;
                                }
                                ref.read(proxiesOverviewNotifierProvider.notifier)
                                    .changeProxy(group!.tag, node.tag);
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  );
                }

                // No real nodes — show showcase nodes if available
                if (showcaseNodes.value.isNotEmpty) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Divider(height: 1),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 300),
                        child: ListView.builder(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: showcaseNodes.value.length,
                          itemBuilder: (ctx, i) {
                            final n = showcaseNodes.value[i];
                            final locked = n['locked'] as bool? ?? false;
                            return _ShowcaseRow(
                              name: n['name'] as String? ?? '',
                              cc: n['cc'] as String? ?? '',
                              tag: n['tag'] as String? ?? '',
                              locked: locked,
                              onTap: locked
                                  ? () => showPlansSheet(context)
                                  : () => ref.read(connectionNotifierProvider.notifier).toggleConnection(),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                }

                // Nothing at all
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('暂无节点', style: theme.textTheme.bodySmall),
                );
              },
              error: (_, __) {
                // Error state — show showcase nodes if available
                if (showcaseNodes.value.isNotEmpty) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Divider(height: 1),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 300),
                        child: ListView.builder(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: showcaseNodes.value.length,
                          itemBuilder: (ctx, i) {
                            final n = showcaseNodes.value[i];
                            final locked = n['locked'] as bool? ?? false;
                            return _ShowcaseRow(
                              name: n['name'] as String? ?? '',
                              cc: n['cc'] as String? ?? '',
                              tag: n['tag'] as String? ?? '',
                              locked: locked,
                              onTap: locked
                                  ? () => showPlansSheet(context)
                                  : () => ref.read(connectionNotifierProvider.notifier).toggleConnection(),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                }
                return const SizedBox.shrink();
              },
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
              ),
            ),
        ],
      ),
    );
  }

  static Color _delayColor(int delay) {
    if (delay <= 0 || delay > 65000) return Colors.grey;
    if (delay < 800) return Colors.green;
    if (delay < 1500) return Colors.orange;
    return Colors.red;
  }
}

class _NodeRow extends StatelessWidget {
  final OutboundInfo node;
  final bool isSelected;
  final VoidCallback onTap;

  const _NodeRow({required this.node, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final delay = node.urlTestDelay;
    final hasDelay = delay > 0 && delay < 65000;
    final isTimeout = delay >= 65000;
    final displayName = NodeListCard.cleanTag(node.tagDisplay);
    final cc = NodeListCard.inferCountryCode(node.tagDisplay, node.ipinfo.countryCode);

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: isSelected ? theme.colorScheme.primaryContainer.withOpacity(0.4) : null,
        child: Row(
          children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? Colors.green : Colors.transparent,
              ),
            ),
            const SizedBox(width: 6),
            IPCountryFlag(
              countryCode: cc,
              organization: node.ipinfo.org,
              size: 24,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                displayName,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (hasDelay)
              Text(
                '${delay}ms',
                style: TextStyle(
                  color: NodeListCard._delayColor(delay),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              )
            else
              Text('--', style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _ShowcaseRow extends StatelessWidget {
  final String name;
  final String cc;
  final String tag;
  final bool locked;
  final VoidCallback onTap;

  const _ShowcaseRow({
    required this.name,
    required this.cc,
    required this.tag,
    required this.locked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            IPCountryFlag(countryCode: cc, organization: '', size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$name|$tag',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: locked ? theme.colorScheme.onSurfaceVariant : null,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (locked)
              const Icon(Icons.lock_rounded, size: 14, color: Colors.orange)
            else
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey.shade400, width: 1.5),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
