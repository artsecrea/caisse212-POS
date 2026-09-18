import 'dart:math';
import 'package:flutter/material.dart';

const double kBreakpointCompact = 900.0;
const double kBreakpointMedium = 1200.0;

/// Width of the order panel.
///
/// Fixed widths above the compact breakpoint, where there is plenty of room.
/// Below ~700px a fixed 260 was taking 43% of a 600px screen and starving the
/// product grid, so the panel becomes proportional down to a 200px floor — the
/// narrowest that still fits a quantity, a name and a price on one line.
double orderPanelWidth(double screenWidth) {
  if (screenWidth < 700) {
    return (screenWidth * 0.36).clamp(200.0, 260.0);
  }
  if (screenWidth < kBreakpointCompact) return 260.0;
  if (screenWidth < kBreakpointMedium) return 320.0;
  return 400.0;
}

double actionButtonSize(double screenWidth) {
  if (screenWidth < kBreakpointCompact) return 68.0;
  if (screenWidth < kBreakpointMedium) return 84.0;
  return 105.0;
}

double actionBarHeight(double screenWidth) => actionButtonSize(screenWidth) + 20.0;

/// Clamps [preferred] dialog width to 92% of screen width so dialogs never overflow.
double dialogWidth(BuildContext context, double preferred) =>
    min(preferred, MediaQuery.sizeOf(context).width * 0.92);
