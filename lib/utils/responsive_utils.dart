import 'dart:math';
import 'package:flutter/material.dart';

const double kBreakpointCompact = 900.0;
const double kBreakpointMedium = 1200.0;

double orderPanelWidth(double screenWidth) {
  if (screenWidth < kBreakpointCompact) return 260.0;
  if (screenWidth < kBreakpointMedium) return 320.0;
  return 400.0;
}

double actionButtonSize(double screenWidth) {
  if (screenWidth < kBreakpointCompact) return 80.0;
  if (screenWidth < kBreakpointMedium) return 100.0;
  return 130.0;
}

double actionBarHeight(double screenWidth) => actionButtonSize(screenWidth) + 20.0;

/// Clamps [preferred] dialog width to 92% of screen width so dialogs never overflow.
double dialogWidth(BuildContext context, double preferred) =>
    min(preferred, MediaQuery.sizeOf(context).width * 0.92);
