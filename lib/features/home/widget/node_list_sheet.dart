import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

Color _delayColor(int delay) {
  if (delay <= 0 || delay > 65000) return Colors.grey;
  if (delay < 800) return Colors.green;
  if (delay < 1500) return Colors.orange;
  return Colors.red;
}

/// Full-screen node list page (pushed via Navigator, has back button).
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

    final isExpired = useState(false);
    final userTier = useState<String>('free');
    final expiryChecked = useState(false);

    useEffect(() {
      () async {
        try {
          final prefs = await SharedPreferences.getInstance();
          final auth = AuthService(prefs);
          if (!auth.isLoggedIn) { expiryChecked.value = true; return; }
          final ct = auth.cachedTier;
          if (ct == 'vip' || ct == 'svip') {
            userTier.value = ct;
          }
          final userInfo = await auth.getUserInfo();
          if (userInfo != null) {
            final tier = userInfo['tier'] as String? ?? 'free';
            userTier.value = tier;
            if (tier == 'vip' || tier == 'svip') {
              isExpired.value = false;
              expiryChecked.value = true;
              return;
            }
          }
          final status = await auth.getTrialStatus();
          if (status != null) {
            if (status['status'] == 'expired') isExpired.value = true;
            if (status['status'] == 'paid' && userTier.value == 'free') userTier.value = 'vip';
            expiryChecked.value = true;
            return;
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
        child: !expiryChecked.value
          ? const Center(child: CircularProgressIndicator())
          : _ConnectedNodeList(
              proxiesAsync: proxiesAsync,
              activeProxy: activeProxy,
              isExpired: isExpired.value,
              userTier: userTier.value,
              isConnected: isConnected,
            ),
      ),
    );
  }
}

/// Node list tab page (used as a NavigationRail tab on desktop, no back button).
class NodeListTabPage extends HookConsumerWidget {
  const NodeListTabPage({super.key});

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

    final isExpired = useState(false);
    final userTier = useState<String>('free');
    final expiryChecked = useState(false);

    useEffect(() {
      () async {
        try {
          final prefs = await SharedPreferences.getInstance();
          final auth = AuthService(prefs);
          if (!auth.isLoggedIn) { expiryChecked.value = true; return; }
          final ct = auth.cachedTier;
          if (ct == 'vip' || ct == 'svip') {
            userTier.value = ct;
          }
          final userInfo = await auth.getUserInfo();
          if (userInfo != null) {
            final tier = userInfo['tier'] as String? ?? 'free';
            userTier.value = tier;
            if (tier == 'vip' || tier == 'svip') {
              isExpired.value = false;
              expiryChecked.value = true;
              return;
            }
          }
          final status = await auth.getTrialStatus();
          if (status != null) {
            if (status['status'] == 'expired') isExpired.value = true;
            if (status['status'] == 'paid' && userTier.value == 'free') userTier.value = 'vip';
            expiryChecked.value = true;
            return;
          }
        } catch (_) {}
        expiryChecked.value = true;
      }();
      return null;
    }, []);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(s['nodeList'] ?? '节点列表', style: theme.textTheme.titleMedium),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: !expiryChecked.value
          ? const Center(child: CircularProgressIndicator())
          : _ConnectedNodeList(
              proxiesAsync: proxiesAsync,
              activeProxy: activeProxy,
              isExpired: isExpired.value,
              userTier: userTier.value,
              isConnected: isConnected,
            ),
      ),
    );
  }
}

/// Fallback node list when API is unreachable.
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

/// Connected node list — real proxy data, Shadowrocket-style.
/// Swipe left/right for actions, double-tap to connect, selected dot on left.
class _ConnectedNodeList extends HookConsumerWidget {
  final AsyncValue<OutboundGroup?> proxiesAsync;
  final OutboundInfo? activeProxy;
  final bool isExpired;
  final String userTier;
  final bool isConnected;

  const _ConnectedNodeList({
    required this.proxiesAsync,
    required this.activeProxy,
    required this.isExpired,
    this.userTier = 'free',
    this.isConnected = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = AuthI18n.t;

    final showcaseNodes = useState<List<Map<String, dynamic>>>([]);
    // Guard: only auto-connect once per page lifecycle
    final hasAutoConnected = useState(false);

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
        final realNodes = (group?.items ?? []).where((n) => !n.isGroup && n.tag.isNotEmpty).toList();

        if (realNodes.isEmpty) {
          // Auto-connect once if not connected — nodes will appear after connection
          if (!isConnected && !hasAutoConnected.value) {
            hasAutoConnected.value = true;
            Future.microtask(() {
              ref.read(connectionNotifierProvider.notifier).toggleConnection();
            });
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(s['connectFirst'] ?? '正在连接，请稍候...'),
                ],
              ),
            );
          }
          // Already tried auto-connect or currently connecting — just show loading
          if (!isConnected) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(s['connectFirst'] ?? '正在连接，请稍候...'),
                ],
              ),
            );
          }
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(s['connectFirst'] ?? '正在加载节点...'),
              ],
            ),
          );
        }

        // Successfully got nodes — reset the guard so re-entering the page can auto-connect again
        if (hasAutoConnected.value) hasAutoConnected.value = false;

        // Group by country
        final grouped = <String, List<OutboundInfo>>{};
        for (final n in realNodes) {
          grouped.putIfAbsent(_extractCountry(n.tagDisplay), () => []).add(n);
        }
        final freeCountries = <String>{};
        for (final e in grouped.entries) {
          if (e.value.any((n) => _isFreeNode(n.tagDisplay))) freeCountries.add(e.key);
        }

        // Extra showcase nodes — REMOVED: only show real nodes

        final sortedCountries = grouped.keys.toList()
          ..sort((a, b) {
            final af = freeCountries.contains(a), bf = freeCountries.contains(b);
            if (af && !bf) return -1;
            if (!af && bf) return 1;
            return a.compareTo(b);
          });
        final activeTag = activeProxy?.tag ?? '';

        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            ...sortedCountries.expand((country) {
              final countryNodes = grouped[country]!;
              return [
                _SectionHeader(
                  label: country,
                  count: countryNodes.length,
                  color: Colors.green,
                  locked: false,
                ),
                ...countryNodes.map((node) {
                  final selected = node.tag == activeTag;
                  final delay = node.urlTestDelay;
                  final cc = NodeListCard.inferCountryCode(node.tagDisplay, node.ipinfo.countryCode);
                  return _SwipeNodeTile(
                    key: ValueKey(node.tag),
                    flagWidget: IPCountryFlag(countryCode: cc, organization: node.ipinfo.org, size: 28),
                    title: NodeListCard.cleanTag(node.tagDisplay),
                    subtitle: '${node.type}',
                    delay: delay,
                    isSelected: selected,
                    locked: false,
                    onDoubleTap: () async {
                      if (!selected && group != null) {
                        await ref.read(proxiesOverviewNotifierProvider.notifier)
                            .changeProxy(group.tag, node.tag);
                      }
                    },
                    onTest: () async {
                      if (group != null) {
                        await ref.read(proxiesOverviewNotifierProvider.notifier)
                            .urlTest(group.tag);
                      }
                    },
                    onCopy: () {
                      Clipboard.setData(ClipboardData(text: node.tag));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('已复制: ${node.tag}'), duration: const Duration(seconds: 1)),
                      );
                    },
                    onInfo: () => _showNodeInfo(context, node),
                  );
                }),
              ];
            }),
          ],
        );
      },
      error: (_, __) {
        // Auto-connect once on error (sing-box not running)
        if (!isConnected && !hasAutoConnected.value) {
          hasAutoConnected.value = true;
          Future.microtask(() {
            ref.read(connectionNotifierProvider.notifier).toggleConnection();
          });
        }
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(s['connectFirst'] ?? '正在连接，请稍候...'),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shadowrocket-style swipeable node tile
// Left swipe → "测试" + "复制"  |  Double-tap → connect  |  Selected dot on left
// ─────────────────────────────────────────────────────────────────────────────
class _SwipeNodeTile extends StatefulWidget {
  final Widget flagWidget;
  final String title;
  final String subtitle;
  final int delay;
  final bool isSelected;
  final bool locked;
  final VoidCallback onDoubleTap;
  final VoidCallback? onTest;
  final VoidCallback? onCopy;
  final VoidCallback? onInfo;

  const _SwipeNodeTile({
    super.key,
    required this.flagWidget,
    required this.title,
    required this.subtitle,
    required this.delay,
    required this.isSelected,
    this.locked = false,
    required this.onDoubleTap,
    this.onTest,
    this.onCopy,
    this.onInfo,
  });

  @override
  State<_SwipeNodeTile> createState() => _SwipeNodeTileState();
}

class _SwipeNodeTileState extends State<_SwipeNodeTile> with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late Animation<Offset> _slideAnim;
  bool _showActions = false;
  static const _actionWidth = 140.0; // total width of action buttons

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _slideAnim = Tween<Offset>(begin: Offset.zero, end: const Offset(-140, 0))
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _open() {
    if (_showActions) return;
    setState(() => _showActions = true);
    _animCtrl.forward();
  }

  void _close() {
    if (!_showActions) return;
    _animCtrl.reverse().then((_) {
      if (mounted) setState(() => _showActions = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final delay = widget.delay;
    final hasDelay = delay > 0 && delay < 65000;
    final isTimeout = delay >= 65000;

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (widget.locked) return;
        final v = details.primaryVelocity ?? 0;
        if (v < -200) {
          _open(); // swipe left → show actions
        } else if (v > 200) {
          _close(); // swipe right → hide actions
        }
      },
      onDoubleTap: () {
        _close();
        widget.onDoubleTap();
      },
      onTap: () {
        if (_showActions) _close();
      },
      child: SizedBox(
        height: 60,
        child: Stack(
          children: [
            // Action buttons behind (right side)
            if (_showActions)
              Positioned.fill(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _ActionButton(
                      label: '测试',
                      color: Colors.green,
                      onTap: () { _close(); widget.onTest?.call(); },
                    ),
                    _ActionButton(
                      label: '复制',
                      color: Colors.grey.shade400,
                      onTap: () { _close(); widget.onCopy?.call(); },
                    ),
                  ],
                ),
              ),
            // Foreground tile
            AnimatedBuilder(
              animation: _slideAnim,
              builder: (_, child) => Transform.translate(
                offset: _slideAnim.value,
                child: child,
              ),
              child: Container(
                height: 60,
                color: widget.isSelected
                    ? theme.colorScheme.primary.withOpacity(0.06)
                    : theme.scaffoldBackgroundColor,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    // Selected dot (Shadowrocket style)
                    SizedBox(
                      width: 14,
                      child: widget.locked
                          ? const SizedBox.shrink()
                          : Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: widget.isSelected
                                    ? Colors.green
                                    : Colors.transparent,
                                border: widget.isSelected
                                    ? null
                                    : Border.all(color: Colors.grey.shade300, width: 1),
                              ),
                            ),
                    ),
                    const SizedBox(width: 8),
                    // Country flag
                    SizedBox(width: 32, height: 28, child: Center(child: widget.flagWidget)),
                    const SizedBox(width: 10),
                    // Title + subtitle
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.normal,
                              color: widget.locked ? theme.colorScheme.onSurfaceVariant : null,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (widget.subtitle.isNotEmpty)
                            Text(
                              widget.subtitle,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Delay label
                    if (widget.locked)
                      const Icon(Icons.lock_rounded, size: 16, color: Colors.orange)
                    else ...[
                      if (hasDelay)
                        Text(
                          '${delay}ms',
                          style: TextStyle(
                            color: _delayColor(delay),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        )
                      else if (isTimeout)
                        Text('超时', style: TextStyle(color: Colors.red.shade300, fontSize: 12))
                      else
                        Text('--', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                      // Info button (ⓘ)
                      if (widget.onInfo != null)
                        GestureDetector(
                          onTap: widget.onInfo,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Icon(
                              Icons.info_outline_rounded,
                              size: 20,
                              color: theme.colorScheme.primary.withOpacity(0.7),
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Swipe action button (测试 / 复制).
class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 70,
        height: 60,
        color: color,
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// Show node detail info bottom sheet.
void _showNodeInfo(BuildContext context, OutboundInfo node) {
  final theme = Theme.of(context);
  final delay = node.urlTestDelay;
  final hasDelay = delay > 0 && delay < 65000;
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(NodeListCard.cleanTag(node.tagDisplay),
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _InfoRow('协议', node.type),
          if (hasDelay) _InfoRow('延迟', '${delay}ms'),
          if (node.ipinfo.countryCode.isNotEmpty) _InfoRow('国家', node.ipinfo.countryCode.toUpperCase()),
          if (node.ipinfo.org.isNotEmpty) _InfoRow('组织', node.ipinfo.org),
          _InfoRow('标签', node.tag),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

/// Section header.
class _SectionHeader extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final bool locked;

  const _SectionHeader({
    required this.label,
    required this.count,
    required this.color,
    this.locked = false,
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
        ],
      ),
    );
  }
}

/// Fallback when no real proxy data (disconnected / error).
class _ShowcaseFallback extends HookWidget {
  final List<Map<String, dynamic>> showcaseNodes;
  final bool isExpired;
  final String userTier;
  final bool isConnected;
  final VoidCallback onConnect;

  const _ShowcaseFallback({
    required this.showcaseNodes,
    required this.isExpired,
    required this.userTier,
    required this.isConnected,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = AuthI18n.t;

    final nodes = useState<List<Map<String, dynamic>>>(showcaseNodes);
    final apiFailed = useState(false);

    useEffect(() {
      if (showcaseNodes.isNotEmpty) { nodes.value = showcaseNodes; return null; }
      () async {
        final prefs = await SharedPreferences.getInstance();
        final auth = AuthService(prefs);
        final fetched = await auth.getShowcaseNodes();
        if (fetched.isNotEmpty) {
          nodes.value = fetched;
        } else {
          apiFailed.value = true;
          final isPaid = userTier == 'vip' || userTier == 'svip';
          nodes.value = _fallbackNodes.map((n) {
            final m = Map<String, dynamic>.from(n);
            if (isPaid) m['locked'] = false;
            return m;
          }).toList();
        }
      }();
      return null;
    }, [showcaseNodes]);

    if (nodes.value.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(s['connectFirst'] ?? '请先连接', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onConnect,
              icon: const Icon(Icons.flash_on_rounded, size: 18),
              label: Text(s['oneClickConnect'] ?? '一键连接'),
            ),
          ],
        ),
      );
    }

    final isPaidUser = userTier == 'vip' || userTier == 'svip';

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (!isConnected)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: FilledButton.icon(
              onPressed: onConnect,
              icon: const Icon(Icons.flash_on_rounded, size: 18),
              label: Text(s['oneClickConnect'] ?? '一键连接'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
            ),
          ),
        if (!isConnected) const SizedBox(height: 4),
        if (apiFailed.value)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.wifi_off_rounded, size: 16, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  s['networkErrorDesc'] ?? '未连接VPN，显示预览节点',
                  style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                )),
              ],
            ),
          ),
        ...nodes.value.map((n) {
          final locked = isExpired || (!isPaidUser && n['tier'] == 'paid');
          return _SwipeNodeTile(
            flagWidget: IPCountryFlag(countryCode: n['cc'] as String? ?? '', organization: '', size: 28),
            title: '${n['name']}|${n['tag']}',
            subtitle: locked ? (s['paidRegion'] ?? '') : '',
            delay: 0,
            isSelected: false,
            locked: locked,
            onDoubleTap: locked ? () => showPlansSheet(context) : onConnect,
            onTest: null,
            onCopy: null,
            onInfo: null,
          );
        }),
      ],
    );
  }
}
