import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'server_status_badge.dart';

/// Pengganti ParallaxScrollView: header berlogo yang ikut ter-scroll.
class SwavinaScaffold extends StatelessWidget {
  const SwavinaScaffold({super.key, required this.child, this.onRefresh});

  final Widget child;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    final scroll = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverAppBar(
          automaticallyImplyLeading: false,
          expandedHeight: 178,
          backgroundColor: c.headerBg,
          flexibleSpace: FlexibleSpaceBar(
            collapseMode: CollapseMode.parallax,
            background: Container(
              color: c.headerBg,
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: Image.asset(
                      'assets/images/logo_swavina.png',
                      width: 290,
                      height: 178,
                      fit: BoxFit.contain,
                      alignment: Alignment.bottomLeft,
                    ),
                  ),
                  const SafeArea(
                    child: Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: EdgeInsets.all(10),
                        child: ServerStatusBadge(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(child: child),
      ],
    );

    return Scaffold(
      backgroundColor: c.pageBg,
      body: onRefresh == null
          ? scroll
          : RefreshIndicator(onRefresh: onRefresh!, child: scroll),
    );
  }
}
