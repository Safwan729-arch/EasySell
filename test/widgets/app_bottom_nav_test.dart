import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ai_shopkeeper/core/config/theme.dart';
import 'package:ai_shopkeeper/core/widgets/app_bottom_nav.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('tapping a destination reports its branch index', (tester) async {
    int? tappedBranch;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          bottomNavigationBar: AppBottomNav(
            items: const [
              AppNavItem(
                icon: Icons.home_rounded,
                label: 'Home',
                branchIndex: 0,
              ),
              AppNavItem(
                icon: Icons.inventory_2_outlined,
                label: 'Items',
                branchIndex: 1,
              ),
              AppNavItem(
                icon: Icons.bar_chart_rounded,
                label: 'Reports',
                branchIndex: 2,
              ),
              AppNavItem(
                icon: Icons.access_time_rounded,
                label: 'History',
                branchIndex: 3,
              ),
            ],
            currentIndex: 0,
            onTap: (i) => tappedBranch = i,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Reports'));
    expect(tappedBranch, 2);
  });
}
