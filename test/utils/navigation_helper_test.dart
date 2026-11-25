import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musly/utils/navigation_helper.dart';

class _Page extends StatelessWidget {
  const _Page();

  @override
  Widget build(BuildContext context) => const Text('page');
}

void main() {
  late BuildContext home;

  Widget app(Key key) => MaterialApp(
        key: key,
        home: Builder(builder: (context) {
          home = context;
          return const Text('home');
        }),
      );

  // RD: the page is remembered as open until its route is popped, so one removed with the screens around it (a
  // server switch rebuilds them) is refused for good: the settings button does nothing until a restart.
  testWidgets('a page removed without a pop can be opened again',
      (tester) async {
    await tester.pumpWidget(app(const ValueKey(1)));
    NavigationHelper.push(home, const _Page());
    await tester.pumpAndSettle();
    expect(find.byType(_Page), findsOneWidget);

    await tester.pumpWidget(app(const ValueKey(2)));
    await tester.pumpAndSettle();
    expect(find.byType(_Page), findsNothing);
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)));

    NavigationHelper.push(home, const _Page());
    await tester.pumpAndSettle();

    expect(find.byType(_Page), findsOneWidget);
  });

  // RD: the same page pushed again while it is on top (a double tap) opens a second copy over the first.
  testWidgets('a page already on top is not opened again', (tester) async {
    await tester.pumpWidget(app(const ValueKey(3)));
    NavigationHelper.push(home, const _Page());
    await tester.pumpAndSettle();
    // Past the real-time guard against a quick second tap, so the page itself is what refuses it.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)));

    NavigationHelper.push(home, const _Page());
    await tester.pumpAndSettle();

    expect(find.byType(_Page, skipOffstage: false), findsOneWidget);
  });
}
