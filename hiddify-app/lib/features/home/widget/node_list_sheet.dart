import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/features/auth/data/auth_i18n.dart';
import 'package:hiddify/features/auth/data/auth_service.dart';
import 'package:hiddify/features/auth/widget/plans_page.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/home/widget/node_list_card.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/proxy/active/ip_widget.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Show node list as a full-screen page.
Future<void> showNodeListSheet(BuildContext context) async {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const NodeListPage()),
  );
}

/// Extract country from node tag display name.
String _extractCountry(String tagDisplay) {
  final match = RegExp(r'^[\p{So}\p{Cn}\s]*([\u4e00-\u9fff]+)', unicode: true).firstMatch(tagDisplay);
  if (match != null) return match.group(1)!;
  for (final c in ['日本', '新加坡', '香港', '台湾', '美国', '韩国', '英国', '德国', '法国', '澳大利亚']) {
    if (tagDisplay.contains(c)) return c;
  }
  return '其他';
}

/// Check if a node is a free/shared node
bool _isFreeNode(String tagDisplay) {
  return tagDisplay.contains('免费') || tagDisplay.contains('保底') ||
         tagDisplay.contains('共享') || tagDisplay.contains('体验');
}

/// Full-screen node list page.
class NodeListPage extends HookConsumerWidget {
  const NodeListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = AuthI18n.t;
    final connectionStatus = ref.watch(
      connectionNotifierProvider.select((v) => v.valueOrNull ?? const Disconnected()),
    );
    final isConnected = connectionStatus == const Connected();
    final proxiesAsync = ref.watch(proxiesOverviewNotifierProvider);
    final activeProxy = ref.watch(activeProxyNotifierProvider).valueOrNull;
    final activeProfile = ref.watch(activeProfileProvider).valueOrNull;

    final canPop = Navigator.of(context).canPop();

    // Check if user is expired (no active subscription)
    final isExpired = useState(false);

    // Show loading until expiry check completes
    final expiryChecked = useState(false);
    useEffect(() {
      () async {
        try {
          final prefs = await SharedPreferences.getInstance();
          final auth = AuthService(prefs);
          if (!auth.isLoggedIn) { expiryChecked.value = true; return; }
          final status = await auth.getTrialStatus();
          if (status != null) {
            // paid 或 free 都不算过期，只有 expired 才锁节点
            if (status['status'] == 'expired') {
              isExpired.value = true;
            }
            // paid 和 free 用户都可以用节点
            expiryChecked.value = true;
            return;
          }
          // 兜底：检查 userInfo 的 tier
          final userInfo = await auth.getUserInfo();
          if (userInfo != null) {
            final tier = userInfo['tier'] as String? ?? 'free';
            if (tier == 'vip' || tier == 'svip') {
              // VIP/SVIP 永远不过期
              isExpired.value = false;
            }
          }
        } catch (_) {}
        expiryChecked.value = true;
      }();
      return null;
    }, []);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(s['nodeList'] ?? '节点列表', style: theme.textTheme.titleMedium),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: !isConnected
          ? _ShowcaseNodeList(
              onConnect: () async {
                if (isExpired.value) {
                  showPlansSheet(context);
                  return;
                }
                ref.read(connectionNotifierProvider.notifier).toggleConnection();
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }
              },
              isExpired: isExpired.value,
              expiryChecked: expiryChecked.value,
            )
          : _ConnectedNodeList(
              proxiesAsync: proxiesAsync,
              activeProxy: activeProxy,
              isExpired: isExpired.value,
            ),
      ),
    );
  }
}

/// Fallback node list when API is unreachable (e.g. behind GFW without VPN).
const _fallbackNodes = <Map<String, dynamic>>[
  {'name': '香港', 'cc': 'hk', 'tag': '共享', 'tier': 'paid', 'locked': true},
  {'name': '台湾', 'cc': 'tw', 'tag': '共享', 'tier': 'paid', 'locked': true},
  {'name': '日本', 'cc': 'jp', 'tag': '共享', 'tier': 'paid', 'locked': true},
  {'name': '新加坡', 'cc': 'sg', 'tag': '共享', 'tier': 'paid', 'locked': true},
  {'name': '美国', 'cc': 'us', 'tag': '共享', 'tier': 'paid', 'locked': true},
  {'name': '韩国', 'cc': 'kr', 'tag': '共享', 'tier': 'paid', 'locked': true},
  {'name': '香港专线', 'cc': 'hk', 'tag': '专属', 'tier': 'paid', 'locked': true},
  {'name': '台湾专线', 'cc': 'tw', 'tag': '专属', 'tier': 'paid', 'locked': true},
  {'name': '日本专线', 'cc': 'jp', 'tag': '专属', 'tier': 'paid', 'locked': true},
  {'name': '新加坡专线', 'cc': 'sg', 'tag': '专属', 'tier': 'paid', 'locked': true},
  {'name': '美国专线', 'cc': 'us', 'tag': '专属', 'tier': 'paid', 'locked': true},
  {'name': '韩国专线', 'cc': 'kr', 'tag': '专属', 'tier': 'paid', 'locked': true},
  {'name': '德国高速', 'cc': 'de', 'tag': '专属', 'tier': 'paid', 'locked': true},
  {'name': '英国高速', 'cc': 'gb', 'tag': '专属', 'tier': 'paid', 'locked': true},
  {'name': '法国高速', 'cc': 'fr', 'tag': '专属', 'tier': 'paid', 'locked': true},
  {'name': '澳大利亚高速', 'cc': 'au', 'tag': '专属', 'tier': 'paid', 'locked': true},
  {'name': '加拿大高速', 'cc': 'ca', 'tag': '专属', 'tier': 'paid', 'locked': true},
  {'name': '荷兰高速', 'cc': 'nl', 'tag': '专属', 'tier': 'paid', 'locked': true},
  {'name': '印度高速', 'cc': 'in', 'tag': '专属', 'tier': 'paid', 'locked': true},
  {'name': '巴西高速', 'cc': 'br', 'tag': '专属', 'tier': 'paid', 'locked': true},
  {'name': '土耳其高速', 'cc': 'tr', 'tag': '专属', 'tier': 'paid', 'locked': true},
  {'name': '俄罗斯高速', 'cc': 'ru', 'tag': '专属', 'tier': 'paid', 'locked': true},
  {'name': '阿根廷高速', 'cc': 'ar', 'tag': '专属', 'tier': 'paid', 'locked': true},
  {'name': '爱尔兰高速', 'cc': 'ie', 'tag': '专属', 'tier': 'paid', 'locked': true},
  {'name': '阿联酋高速', 'cc': 'ae', 'tag': '专属', 'tier': 'paid', 'locked': true},
  {'name': '澳门高速', 'cc': 'mo', 'tag': '专属', 'tier': 'paid', 'locked': true},
];

/// Showcase node list — shown when VPN is disconnected.
/// When expired: all nodes shown in one unified list with lock style.
class _ShowcaseNodeList extends HookWidget {
  final VoidCallback onConnect;
  final bool isExpired;
  final bool expiryChecked;
  const _ShowcaseNodeList({required this.onConnect, required this.isExpired, this.expiryChecked = true});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = AuthI18n.t;
    final nodes = useState<List<Map<String, dynamic>>>([]);
    final isLoading = useState(true);

    useEffect(() {
      () async {
        final prefs = await SharedPreferences.getInstance();
        final auth = AuthService(prefs);
        final fetched = await auth.getShowcaseNodes();
        nodes.value = fetched.isNotEmpty ? fetched : List<Map<String, dynamic>>.from(_fallbackNodes);
        isLoading.value = false;
      }();
      return null;
    }, []);

    if (isLoading.value || !expiryChecked) {
      return const Center(child: CircularProgressIndicator());
    }

    if (nodes.value.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(s['connectFirst']!, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onConnect,
              icon: const Icon(Icons.flash_on_rounded, size: 18),
              label: Text(s['oneClickConnect']!),
            ),
          ],
        ),
      );
    }

    if (isExpired) {
      // Expired: merge all nodes into one unified list, all locked
      return ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _RadioNodeTile(
            leading: Icon(Icons.public_rounded, size: 28, color: theme.colorScheme.primary),
            title: '自动匹配最快网络',
            subtitle: null,
            isSelected: true,
            onTap: onConnect,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _SectionHeader(label: s['paidRegion']!, count: nodes.value.length, color: Colors.orange, locked: true, onRefresh: () async { final prefs = await SharedPreferences.getInstance(); final auth = AuthService(prefs); final fetched = await auth.getShowcaseNodes(forceRefresh: true); if (fetched.isNotEmpty) nodes.value = fetched; }),
          ...nodes.value.map((n) => _RadioNodeTile(
            leading: IPCountryFlag(countryCode: n['cc'] as String? ?? '', organization: '', size: 28),
            title: '${n['name']}|${n['tag']}',
            subtitle: s['paidRegion'],
            isSelected: false,
            locked: true,
            onTap: () => showPlansSheet(context),
          )),
        ],
      );
    }

    // Not expired: show free / paid separately
    final freeNodes = nodes.value.where((n) => n['tier'] == 'free').toList();
    final paidNodes = nodes.value.where((n) => n['tier'] == 'paid').toList();

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _RadioNodeTile(
          leading: Icon(Icons.public_rounded, size: 28, color: theme.colorScheme.primary),
          title: '自动匹配最快网络',
          subtitle: null,
          isSelected: true,
          onTap: onConnect,
        ),
        const Divider(height: 1, indent: 16, endIndent: 16),
        if (freeNodes.isNotEmpty) ...[
          _SectionHeader(label: s['freeRegion']!, count: freeNodes.length, color: Colors.green),
          ...freeNodes.map((n) => _RadioNodeTile(
            leading: IPCountryFlag(countryCode: n['cc'] as String? ?? '', organization: '', size: 28),
            title: '${n['name']}|${n['tag']}',
            subtitle: s['freeRegion'],
            isSelected: false,
            onTap: onConnect,
          )),
        ],
        if (paidNodes.isNotEmpty) ...[
          _SectionHeader(label: s['paidRegion']!, count: paidNodes.length, color: Colors.orange, locked: true, onRefresh: () async { final prefs = await SharedPreferences.getInstance(); final auth = AuthService(prefs); final fetched = await auth.getShowcaseNodes(forceRefresh: true); if (fetched.isNotEmpty) nodes.value = fetched; }),
          ...paidNodes.map((n) => _RadioNodeTile(
            leading: IPCountryFlag(countryCode: n['cc'] as String? ?? '', organization: '', size: 28),
            title: '${n['name']}|${n['tag']}',
            subtitle: s['paidRegion'],
            isSelected: false,
            locked: true,
            onTap: () => showPlansSheet(context),
          )),
        ],
      ],
    );
  }
}

/// Connected node list — real proxy data grouped by country with radio selection.
/// Merges showcase paid nodes (locked) so the full node catalog is always visible.
/// When expired: all nodes shown with lock style, tapping opens plans.
class _ConnectedNodeList extends HookConsumerWidget {
  final AsyncValue<OutboundGroup?> proxiesAsync;
  final OutboundInfo? activeProxy;
  final bool isExpired;

  const _ConnectedNodeList({required this.proxiesAsync, required this.activeProxy, required this.isExpired});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = AuthI18n.t;

    // Fetch showcase nodes to merge paid ones into the list
    final showcaseNodes = useState<List<Map<String, dynamic>>>([]);
    useEffect(() {
      () async {
        final prefs = await SharedPreferences.getInstance();
        final auth = AuthService(prefs);
        showcaseNodes.value = await auth.getShowcaseNodes();
      }();
      return null;
    }, []);

    return proxiesAsync.when(
      data: (group) {
        if (group == null || group.items.isEmpty) {
          // Even with no real proxies, show showcase nodes
          if (showcaseNodes.value.isEmpty) {
            return const Center(child: Text('暂无节点'));
          }
        }
        final realNodes = (group?.items ?? []).where((n) => !n.isGroup && n.tag.isNotEmpty).toList();

        // Group real nodes by country
        final grouped = <String, List<OutboundInfo>>{};
        for (final n in realNodes) {
          final country = _extractCountry(n.tagDisplay);
          grouped.putIfAbsent(country, () => []).add(n);
        }

        // Determine which countries have free (体验) real nodes
        final freeCountries = <String>{};
        for (final entry in grouped.entries) {
          if (entry.value.any((n) => _isFreeNode(n.tagDisplay))) {
            freeCountries.add(entry.key);
          }
        }

        // Collect showcase paid nodes whose country is NOT already in real nodes
        final realCountries = grouped.keys.toSet();
        final extraPaidNodes = <Map<String, dynamic>>[];
        for (final sn in showcaseNodes.value) {
          final tier = sn['tier'] as String? ?? '';
          if (tier == 'paid') {
            // Always add paid showcase nodes — they show as locked
            extraPaidNodes.add(sn);
          } else if (tier == 'free') {
            // Add free showcase nodes only if that country has no real nodes
            final name = sn['name'] as String? ?? '';
            if (!realCountries.any((c) => name.contains(c))) {
              extraPaidNodes.add(sn);
            }
          }
        }

        // Group extra paid nodes by a simple label
        final extraGrouped = <String, List<Map<String, dynamic>>>{};
        for (final n in extraPaidNodes) {
          final name = n['name'] as String? ?? '';
          // Extract country from showcase name
          String country = '其他';
          for (final c in ['香港', '台湾', '日本', '新加坡', '美国', '韩国', '英国', '德国', '法国', '澳大利亚', '加拿大', '荷兰', '印度', '巴西', '土耳其', '俄罗斯', '阿根廷', '爱尔兰', '阿联酋', '澳门']) {
            if (name.contains(c)) { country = c; break; }
          }
          extraGrouped.putIfAbsent(country, () => []).add(n);
        }

        // Build sorted country list: free real nodes first, then paid real, then extra showcase
        final sortedRealCountries = grouped.keys.toList()
          ..sort((a, b) {
            final aFree = freeCountries.contains(a);
            final bFree = freeCountries.contains(b);
            if (aFree && !bFree) return -1;
            if (!aFree && bFree) return 1;
            return a.compareTo(b);
          });

        // Extra countries not already in real nodes
        final extraCountries = extraGrouped.keys.where((c) => !realCountries.contains(c)).toList()..sort();

        final activeTag = activeProxy?.tag ?? '';

        // When expired: all nodes are locked
        if (isExpired) {
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              // Real nodes (all locked when expired)
              ...sortedRealCountries.expand((country) {
                final countryNodes = grouped[country]!;
                return [
                  _SectionHeader(label: country, count: countryNodes.length, color: Colors.orange, locked: true),
                  ...countryNodes.map((node) {
                    final delay = node.urlTestDelay;
                    final hasDelay = delay > 0 && delay < 65000;
                    final cc = NodeListCard.inferCountryCode(node.tagDisplay, node.ipinfo.countryCode);
                    return _RadioNodeTile(
                      leading: IPCountryFlag(countryCode: cc, organization: node.ipinfo.org, size: 28),
                      title: NodeListCard.cleanTag(node.tagDisplay),
                      subtitle: hasDelay ? '${delay}ms · ${node.type}' : node.type,
                      subtitleColor: hasDelay ? _delayColor(delay) : null,
                      isSelected: false,
                      locked: true,
                      onTap: () => showPlansSheet(context),
                    );
                  }),
                ];
              }),
              // Extra showcase paid nodes (locked)
              if (extraCountries.isNotEmpty) ...[
                _SectionHeader(label: s['paidRegion']!, count: extraPaidNodes.length, color: Colors.orange, locked: true),
                ...extraCountries.expand((country) {
                  final nodes = extraGrouped[country]!;
                  return nodes.map((n) => _RadioNodeTile(
                    leading: IPCountryFlag(countryCode: n['cc'] as String? ?? '', organization: '', size: 28),
                    title: '${n['name']}|${n['tag']}',
                    subtitle: s['paidRegion'],
                    isSelected: false,
                    locked: true,
                    onTap: () => showPlansSheet(context),
                  ));
                }),
              ],
            ],
          );
        }

        // Not expired: free nodes selectable, paid nodes locked
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            // Real proxy nodes grouped by country
            ...sortedRealCountries.expand((country) {
              final countryNodes = grouped[country]!;
              final isFree = freeCountries.contains(country);
              return [
                _SectionHeader(
                  label: country,
                  count: countryNodes.length,
                  color: isFree ? Colors.green : Colors.orange,
                  locked: !isFree,
                ),
                ...countryNodes.map((node) {
                  final isSelected = node.tag == activeTag;
                  final delay = node.urlTestDelay;
                  final hasDelay = delay > 0 && delay < 65000;
                  final cc = NodeListCard.inferCountryCode(node.tagDisplay, node.ipinfo.countryCode);
                  return _RadioNodeTile(
                    leading: IPCountryFlag(countryCode: cc, organization: node.ipinfo.org, size: 28),
                    title: NodeListCard.cleanTag(node.tagDisplay),
                    subtitle: hasDelay ? '${delay}ms · ${node.type}' : node.type,
                    subtitleColor: hasDelay ? _delayColor(delay) : null,
                    isSelected: isSelected,
                    locked: !isFree,
                    onTap: () async {
                      if (!isFree) {
                        showPlansSheet(context);
                        return;
                      }
                      if (!isSelected && group != null) {
                        await ref.read(proxiesOverviewNotifierProvider.notifier)
                            .changeProxy(group.tag, node.tag);
                      }
                    },
                  );
                }),
              ];
            }),
            // Extra showcase paid nodes (countries not in real proxies)
            if (extraCountries.isNotEmpty) ...[
              _SectionHeader(label: s['paidRegion']!, count: extraPaidNodes.length, color: Colors.orange, locked: true),
              ...extraCountries.expand((country) {
                final nodes = extraGrouped[country]!;
                return nodes.map((n) => _RadioNodeTile(
                  leading: IPCountryFlag(countryCode: n['cc'] as String? ?? '', organization: '', size: 28),
                  title: '${n['name']}|${n['tag']}',
                  subtitle: s['paidRegion'],
                  isSelected: false,
                  locked: true,
                  onTap: () => showPlansSheet(context),
                ));
              }),
            ],
          ],
        );
      },
      error: (_, __) => const Center(child: Text('加载失败')),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }

  static Color _delayColor(int delay) {
    if (delay <= 0 || delay > 65000) return Colors.grey;
    if (delay < 800) return Colors.green;
    if (delay < 1500) return Colors.orange;
    return Colors.red;
  }
}

/// Section header — "付费解锁 🔒 26"
class _SectionHeader extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final bool locked;
  final VoidCallback? onRefresh;

  const _SectionHeader({
    required this.label,
    required this.count,
    required this.color,
    this.locked = false,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Text(label, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (locked) ...[
                  Icon(Icons.lock_rounded, size: 10, color: color),
                  const SizedBox(width: 2),
                ],
                Text('$count', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const Spacer(),
          if (onRefresh != null)
            GestureDetector(
              onTap: onRefresh,
              child: Icon(Icons.refresh_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

/// Radio-style node tile.
class _RadioNodeTile extends StatelessWidget {
  final Widget leading;
  final String title;
  final String? subtitle;
  final Color? subtitleColor;
  final bool isSelected;
  final bool locked;
  final VoidCallback onTap;

  const _RadioNodeTile({
    required this.leading,
    required this.title,
    this.subtitle,
    this.subtitleColor,
    required this.isSelected,
    this.locked = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: isSelected ? primaryColor.withOpacity(0.06) : null,
        child: Row(
          children: [
            SizedBox(width: 36, height: 28, child: Center(child: leading)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: locked ? theme.colorScheme.onSurfaceVariant : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: subtitleColor ?? theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            if (locked)
              const Icon(Icons.lock_rounded, size: 16, color: Colors.orange)
            else
              _RadioDot(isSelected: isSelected, color: primaryColor),
          ],
        ),
      ),
    );
  }
}

/// Custom radio dot.
class _RadioDot extends StatelessWidget {
  final bool isSelected;
  final Color color;

  const _RadioDot({required this.isSelected, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected ? color : Colors.grey.shade400,
          width: 2,
        ),
      ),
      child: isSelected
          ? Center(
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                ),
              ),
            )
          : null,
    );
  }
}
