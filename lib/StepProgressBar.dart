import 'package:flutter/material.dart';

/// Shows a horizontal progress bar split into [totalSteps] segments,
/// with the first [currentStep] segments highlighted in [activeColor].
class StepProgressBar extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  final Color activeColor;
  final Color inactiveColor;
  final double height;
  final double spacing;

  const StepProgressBar({
    Key? key,
    required this.currentStep,
    required this.totalSteps,
    this.activeColor = Colors.black,
    this.inactiveColor = const Color(0xFFEEEEEE),
    this.height = 4.0,
    this.spacing = 4.0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    assert(currentStep <= totalSteps && currentStep >= 0);
    return Row(
      children: List.generate(totalSteps, (index) {
        final isActive = index < currentStep;
        return Expanded(
          child: Container(
            height: height,
            margin: EdgeInsets.symmetric(horizontal: spacing / 2),
            decoration: BoxDecoration(
              color: isActive ? activeColor : inactiveColor,
              borderRadius: BorderRadius.circular(height / 2),
            ),
          ),
        );
      }),
    );
  }
}
