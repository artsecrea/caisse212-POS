import 'package:flutter/material.dart';

/// App-wide design system.
///
/// Light and dark themes are produced by the SAME [_build] function so the two
/// stay structurally identical ("alike") — only the [ColorScheme] differs.
/// Tune spacing, radii, and component styling here once and every page inherits
/// it. Screens should read colors from `Theme.of(context).colorScheme` and use
/// the shared button/card styling rather than hardcoding values.
class AppTheme {
  AppTheme._();

  /// Brand seed — a slightly richer blue than `Colors.blue` for better contrast
  /// on both surfaces. Everything else is derived from it by [ColorScheme].
  static const Color seed = Color(0xFF2563EB);

  // ── Shape scale ─────────────────────────────────────────────────────────
  //
  // Squared off: a till reads as a dense grid of hard panels, and rounded
  // corners on tightly-packed tiles waste the few pixels between them.
  //
  // The four slots are kept even though they are all 0 today, for two reasons:
  // they carry the SEMANTIC level of each surface, so a later change of mind is
  // four numbers here rather than another sweep of the widget tree; and they
  // keep the call sites self-documenting about what kind of surface they are.
  //
  // Screens must use [brSm]/[brMd]/[brLg]/[brXl] (or the raw radius consts)
  // instead of `BorderRadius.circular(n)` — hardcoded radii are exactly how the
  // app ended up with 14 different corner sizes.
  static const double radiusSm = 0; // chips, small controls, badges
  static const double radiusMd = 0; // buttons, inputs, tiles
  static const double radiusLg = 0; // cards, panels, sheets
  static const double radiusXl = 0; // dialogs

  static const BorderRadius brSm = BorderRadius.all(Radius.circular(radiusSm));
  static const BorderRadius brMd = BorderRadius.all(Radius.circular(radiusMd));
  static const BorderRadius brLg = BorderRadius.all(Radius.circular(radiusLg));
  static const BorderRadius brXl = BorderRadius.all(Radius.circular(radiusXl));

  /// Top-only variants, for a header sitting on top of a panel.
  static const BorderRadius brTopSm =
      BorderRadius.vertical(top: Radius.circular(radiusSm));
  static const BorderRadius brTopMd =
      BorderRadius.vertical(top: Radius.circular(radiusMd));

  static final BorderRadius _brSm = brSm;
  static final BorderRadius _brMd = brMd;
  static final BorderRadius _brLg = brLg;
  static final BorderRadius _brXl = brXl;

  // Touch-friendly control height for a POS running on large screens.
  static const double controlHeight = 52;

  // ── Branded bars ────────────────────────────────────────────────────────
  //
  // The top bar paints itself with a brand colour and puts WHITE on top of it.
  // That only works if the background is dark, and a dark [ColorScheme]'s
  // `primary` is a PALE blue — white on it is unreadable. So the bar gets its
  // own colour pair instead of borrowing `primary`:
  //
  //   light → the brand blue itself
  //   dark  → a raised neutral with a hint of the brand tint, so the bar still
  //           reads as "ours" while staying dark enough for white text.
  //
  // Use these (with [onBar]) for any surface that hardcodes white foregrounds.
  static Color bar(ColorScheme s) => s.brightness == Brightness.dark
      ? Color.lerp(s.surfaceContainerHigh, s.primary, 0.12)!
      : s.primary;

  /// The secondary strip under [bar] — deliberately a step darker so the two
  /// rows separate without a divider.
  static Color barAlt(ColorScheme s) => s.brightness == Brightness.dark
      ? Color.lerp(s.surfaceContainer, s.primary, 0.10)!
      : Color.lerp(s.primary, const Color(0xFF000000), 0.22)!;

  /// Foreground for [bar] / [barAlt]. White in both themes by construction.
  static const Color onBar = Color(0xFFFFFFFF);

  // ── Tinted informational panels ─────────────────────────────────────────
  //
  // "This total is a warning", "this order is held", "this row is paid". The
  // app expressed these as a pale `Colors.orange[50]` fill with a
  // `Colors.orange[800]` label — a pair that is self-consistent but paints a
  // bright block onto a dark screen, which reads as a hole punched in the UI.
  //
  // So the hue survives and the LIGHTNESS follows the theme: light mode keeps
  // the pale wash, dark mode blends the same hue into a raised surface.
  // Always use the three together — a mismatched pair is how the problem
  // started.
  static Color tintFill(BuildContext context, MaterialColor hue) {
    final s = Theme.of(context).colorScheme;
    return s.brightness == Brightness.dark
        ? Color.alphaBlend(hue.withValues(alpha: 0.20), s.surfaceContainerHigh)
        : hue.shade50;
  }

  static Color tintBorder(BuildContext context, MaterialColor hue) =>
      Theme.of(context).brightness == Brightness.dark
          ? hue.shade700
          : hue.shade200;

  /// Label / icon colour for a [tintFill] panel.
  static Color tintOn(BuildContext context, MaterialColor hue) =>
      Theme.of(context).brightness == Brightness.dark
          ? hue.shade200
          : hue.shade800;

  static ThemeData lightTheme() => _build(Brightness.light);
  static ThemeData darkTheme() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    final isDark = brightness == Brightness.dark;

    // Hairline used for cards / inputs / dividers so surfaces read as crisp,
    // flat panels instead of relying on heavy drop shadows.
    final hairline = scheme.outlineVariant.withValues(alpha: isDark ? 0.6 : 0.9);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,

      // ── Legacy ThemeData slots ─────────────────────────────────────────
      //
      // These are NOT cosmetic. Flutter derives them from the scheme in a way
      // that is actively wrong for this app, and ~90 call sites read them:
      //
      //  * `primaryColor` defaults to `scheme.surface` in a DARK theme (a
      //    Material 2 hangover — dark app bars used to be surface-coloured).
      //    Every `Theme.of(context).primaryColor` used as an accent — the
      //    selected settings tab, category chips, dialog icons — therefore
      //    painted the background colour onto the background and vanished.
      //  * `cardColor` defaults to `scheme.surface`, i.e. exactly
      //    `scaffoldBackgroundColor`, so panels that set it had zero contrast
      //    and survived on drop shadows alone — which dark themes swallow.
      //  * `dividerColor` defaults to the full-strength `outline`, far heavier
      //    than the hairline the rest of the design system uses.
      primaryColor: scheme.primary,
      primaryColorLight: scheme.primaryContainer,
      primaryColorDark: barAlt(scheme),
      cardColor: scheme.surfaceContainerLow,
      dividerColor: hairline,
      canvasColor: scheme.surface,
      // Comfortable (not compact) — good target sizes for touch POS use.
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,

      // ── App bar ────────────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        centerTitle: false,
        toolbarHeight: 64,
        elevation: 0,
        scrolledUnderElevation: 2,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: scheme.shadow.withValues(alpha: 0.15),
        foregroundColor: scheme.onSurface,
        iconTheme: IconThemeData(size: 24, color: scheme.onSurface),
        actionsIconTheme: IconThemeData(size: 24, color: scheme.onSurfaceVariant),
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),

      // ── Cards ──────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: _brLg,
          side: BorderSide(color: hairline),
        ),
      ),

      // ── Buttons ────────────────────────────────────────────────────────
      filledButtonTheme: FilledButtonThemeData(style: _mainButtonStyle(scheme)),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: scheme.onSurface.withValues(alpha: 0.12),
          minimumSize: const Size(64, controlHeight),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: _brMd),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          minimumSize: const Size(64, controlHeight),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          side: BorderSide(color: scheme.outline.withValues(alpha: 0.6)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: _brMd),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: _brSm),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: scheme.onSurfaceVariant,
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(borderRadius: _brSm),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          textStyle: WidgetStatePropertyAll(
            const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          side: WidgetStatePropertyAll(
            BorderSide(color: scheme.outline.withValues(alpha: 0.5)),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: _brMd),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 2,
        highlightElevation: 4,
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        shape: RoundedRectangleBorder(borderRadius: _brLg),
      ),

      // ── Inputs ─────────────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: isDark ? 0.5 : 0.7),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
        prefixIconColor: scheme.onSurfaceVariant,
        suffixIconColor: scheme.onSurfaceVariant,
        border: OutlineInputBorder(borderRadius: _brMd, borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
          borderRadius: _brMd,
          borderSide: BorderSide(color: hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: _brMd,
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: _brMd,
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: _brMd,
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
      ),

      // ── Selection controls ─────────────────────────────────────────────
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? scheme.onPrimary : scheme.outline),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
            ? scheme.primary
            : scheme.surfaceContainerHighest),
        trackOutlineColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? Colors.transparent : scheme.outline),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: BorderSide(color: scheme.outline, width: 1.6),
      ),

      // ── Chips ──────────────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        selectedColor: scheme.secondaryContainer,
        side: BorderSide(color: hairline),
        labelStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: scheme.onSurfaceVariant,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: _brSm),
      ),

      // ── Lists / tiles ──────────────────────────────────────────────────
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: _brMd),
        titleTextStyle: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
        subtitleTextStyle: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
      ),

      // ── Tabs / navigation ──────────────────────────────────────────────
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        indicator: BoxDecoration(
          borderRadius: _brMd,
          color: scheme.primaryContainer.withValues(alpha: 0.5),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        selectedIconTheme: IconThemeData(color: scheme.onPrimaryContainer),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle: TextStyle(
          color: scheme.primary,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: TextStyle(color: scheme.onSurfaceVariant),
      ),

      // ── Surfaces / overlays ────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: _brXl),
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
        contentTextStyle: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusXl)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: _brMd),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: _brSm,
        ),
        textStyle: TextStyle(color: scheme.onInverseSurface, fontSize: 12),
      ),
      dividerTheme: DividerThemeData(
        color: hairline,
        thickness: 1,
        space: 1,
      ),
      // Fallback for a raw SnackBar; the app's own toasts come from
      // SnackBarHelper.toast and look the same, plus an accent and icon.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            isDark ? scheme.surfaceContainerHighest : scheme.surface,
        contentTextStyle: TextStyle(color: scheme.onSurface, fontSize: 14),
        actionTextColor: scheme.primary,
        elevation: 6,
        insetPadding: const EdgeInsets.all(16),
        dismissDirection: DismissDirection.horizontal,
        showCloseIcon: true,
        closeIconColor: scheme.onSurfaceVariant,
        shape: RoundedRectangleBorder(
          borderRadius: _brMd,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        circularTrackColor: Colors.transparent,
      ),
    );
  }

  /// Primary "call to action" button style (Filled). Exposed so screens can
  /// apply the same weight to bespoke buttons and action bars.
  static ButtonStyle _mainButtonStyle(ColorScheme scheme) {
    return FilledButton.styleFrom(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      disabledBackgroundColor: scheme.onSurface.withValues(alpha: 0.12),
      disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.38),
      minimumSize: const Size(64, controlHeight),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      shape: RoundedRectangleBorder(borderRadius: _brMd),
    );
  }
}
