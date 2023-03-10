import 'package:app/common/widgets/app_scaffold.dart';
import 'package:app/common/widgets/bottom_button.dart';
import 'package:flutter/material.dart';

class ScreenLayout extends StatelessWidget {
  final List<Widget> children;
  final String routeText;
  final void Function() onPressed;

  const ScreenLayout({
    super.key,
    required this.children,
    required this.onPressed,
    required this.routeText,
  });

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      body: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          ...children,
          BottomButton(
            text: routeText,
            onPressed: onPressed,
          ),
        ],
      ),
    );
  }
}
