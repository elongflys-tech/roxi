import 'dart:math';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/proxy/widget/proxy_tile.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ProxiesOverviewPage extends ConsumerWidget with PresLogger {
  const ProxiesOverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;

    final proxies = ref.watch(proxiesOverviewNotifierProvider);
    final sortBy = ref.watch(proxiesSortNotifierProvider);
    final connectionStatus = ref.watch(
      connectionNotifierProvider.select((v) => v.valueOrNull ?? const Disconnected()),
    );
    final isConnected = connectionStatus == const Connected();
    final isConnecting = connectionStatus == const Connecting();

    Widget buildEmptyState() {
      final theme = Theme.of(context);
      if (isConnecting) {
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              Gap(16),
              Text('正在连接，请稍候...'),
            ],
          ),
        );
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.public_rounded, size: 48, color: theme.colorScheme.primary.withOpacity(0.4)),
            const Gap(16),
            Text('暂无节点数据', style: theme.textTheme.bodyMedium),
            const Gap(16),
            FilledButton.icon(
              onPressed: () => ref.read(connectionNotifierProvider.notifier).toggleConnection(),
              icon: const Icon(Icons.power_settings_new_rounded, size: 18),
              label: const Text('一键连接'),
            ),
          ],
        ),
      );
    }

    Widget buildGrid(OutboundGroup group) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final crossAxisCount = PlatformUtils.isMobile && width < 600 ? 1 : max(1, (width / 268).floor());
          return GridView.builder(
            padding: const EdgeInsets.only(bottom: 86),
            itemCount: group.items.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisExtent: 72,
            ),
            itemBuilder: (context, index) {
              final proxy = group.items[index];
              return ProxyTile(
                proxy,
                selected: group.selected == proxy.tag,
                onTap: () {
                  if (!isConnected) {
                    ref.read(connectionNotifierProvider.notifier).toggleConnection();
                    return;
                  }
                  ref.read(proxiesOverviewNotifierProvider.notifier).changeProxy(group.tag, proxy.tag);
                },
              );
            },
          );
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: Navigator.of(context).canPop(),
        title: Text(t.pages.proxies.title),
        actions: [
          PopupMenuButton<ProxiesSort>(
            initialValue: sortBy,
            onSelected: ref.read(proxiesSortNotifierProvider.notifier).update,
            icon: const Icon(FluentIcons.arrow_sort_24_regular),
            tooltip: t.pages.proxies.sort,
            itemBuilder: (context) {
              return [...ProxiesSort.values.map((e) => PopupMenuItem(value: e, child: Text(e.present(t))))];
            },
          ),
          const Gap(8),
        ],
      ),
      floatingActionButton: isConnected
          ? FloatingActionButton(
              onPressed: () async {
                ref.read(proxiesOverviewNotifierProvider.notifier).unfreezeSort();
                await ref.read(proxiesOverviewNotifierProvider.notifier).urlTest("select");
              },
              tooltip: t.pages.proxies.testDelay,
              child: const Icon(FluentIcons.flash_24_filled),
            )
          : null,
      body: proxies.when(
        data: (group) => group != null && group.items.isNotEmpty
            ? buildGrid(group)
            : buildEmptyState(),
        error: (error, stackTrace) => buildEmptyState(),
        loading: () => buildEmptyState(),
      ),
    );
  }
}
