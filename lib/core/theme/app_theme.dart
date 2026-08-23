import 'package:flutter/material.dart';

/// Single source of truth for AutoCarnet's look & feel (Principe 1 & 10:
/// simple, consistent, easy to extend without touching every screen).
///
/// "Premium sobre" identity (validated design concept, 2026 - V2 of the
/// design-review pass, superseding the earlier vivid-blue/turquoise
/// "Auto Premium Clair" concept the user rejected as too colourful/"fun"):
/// a single restrained petrol-blue brand colour used sparingly (CTAs, the
/// active nav state, small accents) rather than saturated gradients or a
/// different hue per vehicle; muted status colours (secondary=success,
/// tertiary=warning, error=danger) instead of loud ones; a cool near-white
/// ground and graphite text. Colours are declared explicitly (not
/// `ColorScheme.fromSeed`) so every tone is a deliberate choice rather than
/// an algorithmic derivation.
class AppTheme {
  AppTheme._();

  static const Color seed = Color(0xFF123B54);

  static ThemeData light() => _base(_lightScheme);
  static ThemeData dark() => _base(_darkScheme);

  static const ColorScheme _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF123B54),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFE7EEF1),
    onPrimaryContainer: Color(0xFF123B54),
    secondary: Color(0xFF2E8F63),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFE4F2EA),
    onSecondaryContainer: Color(0xFF1B5B3E),
    tertiary: Color(0xFFC07A1F),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFF7ECDA),
    onTertiaryContainer: Color(0xFF6E4712),
    error: Color(0xFFC7442F),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFF8E7E3),
    onErrorContainer: Color(0xFF6E2A1D),
    surface: Color(0xFFF5F6F7),
    onSurface: Color(0xFF14171A),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFFAFAFB),
    surfaceContainer: Color(0xFFF1F2F3),
    surfaceContainerHigh: Color(0xFFEAEBEC),
    surfaceContainerHighest: Color(0xFFE2E4E6),
    onSurfaceVariant: Color(0xFF6B7280),
    outline: Color(0xFF9AA1AC),
    outlineVariant: Color(0xFFE3E5E8),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFF14171A),
    onInverseSurface: Color(0xFFF5F6F7),
    inversePrimary: Color(0xFF9FC2D8),
  );

  /// Dark companion of the same identity (petrol blue -> a lightened
  /// blue-grey that stays legible on a dark ground; the muted status colours
  /// lightened the same way) rather than an unrelated palette - the two
  /// must read as one product.
  static const ColorScheme _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF8FB6CC),
    onPrimary: Color(0xFF0B2536),
    primaryContainer: Color(0xFF1D4258),
    onPrimaryContainer: Color(0xFFD7E7EE),
    secondary: Color(0xFF7FCBA2),
    onSecondary: Color(0xFF0A3521),
    secondaryContainer: Color(0xFF1E4E36),
    onSecondaryContainer: Color(0xFFCDEEDC),
    tertiary: Color(0xFFE2AA5C),
    onTertiary: Color(0xFF432C05),
    tertiaryContainer: Color(0xFF5C3E0F),
    onTertiaryContainer: Color(0xFFF7E1BE),
    error: Color(0xFFE49385),
    onError: Color(0xFF4A160D),
    errorContainer: Color(0xFF63271C),
    onErrorContainer: Color(0xFFF8DAD3),
    surface: Color(0xFF15181B),
    onSurface: Color(0xFFE6E7E9),
    surfaceContainerLowest: Color(0xFF0D0F11),
    surfaceContainerLow: Color(0xFF1A1D20),
    surfaceContainer: Color(0xFF1F2225),
    surfaceContainerHigh: Color(0xFF282B2F),
    surfaceContainerHighest: Color(0xFF313539),
    onSurfaceVariant: Color(0xFFA8AFB8),
    outline: Color(0xFF6C7278),
    outlineVariant: Color(0xFF34383C),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFE6E7E9),
    onInverseSurface: Color(0xFF15181B),
    inversePrimary: Color(0xFF123B54),
  );

  static ThemeData _base(ColorScheme scheme) {
    final isDark = scheme.brightness == Brightness.dark;
    final textTheme = _textTheme(scheme);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      splashFactory: InkSparkle.splashFactory,
      textTheme: textTheme,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        systemOverlayStyle: null,
      ),
      cardTheme: CardThemeData(
        elevation: isDark ? 0 : 2,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shadowColor: isDark ? Colors.transparent : scheme.shadow.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          elevation: 2,
          shadowColor: scheme.primary.withValues(alpha: 0.45),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          side: BorderSide(color: scheme.outlineVariant),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: scheme.onSurfaceVariant,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        highlightElevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        side: BorderSide.none,
        labelStyle: textTheme.labelMedium,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primary.withValues(alpha: 0.10),
        height: 60,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: states.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 22,
            color: states.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
        indicatorColor: scheme.primary,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: scheme.outlineVariant.withValues(alpha: 0.4),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.5),
        thickness: 1,
        space: AppSpacing.lg,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
        actionTextColor: scheme.inversePrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        insetPadding: const EdgeInsets.all(AppSpacing.md),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        modalElevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        circularTrackColor: scheme.primary.withValues(alpha: 0.15),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : scheme.outline,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.surfaceContainerHighest,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _AutoCarnetPageTransitionsBuilder(),
          TargetPlatform.iOS: _AutoCarnetPageTransitionsBuilder(),
        },
      ),
    );
  }

  /// A single sans-serif family (Figtree) for every role, hierarchy carried
  /// entirely by weight and size (V2 design-review pass: the earlier serif
  /// display face on greetings/vehicle names read as an artificial,
  /// "magazine" identity rather than a premium automotive product). See
  /// [AppTypography.mono] for the one other role (odometer/stat figures).
  static TextTheme _textTheme(ColorScheme scheme) {
    const base = Typography.blackMountainView;
    return base
        .apply(
          fontFamily: AppFonts.body,
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
        )
        .copyWith(
          headlineLarge: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.3),
          headlineMedium: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.3),
          headlineSmall: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.2),
          titleLarge: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: -0.1),
          titleMedium: const TextStyle(fontWeight: FontWeight.w600),
          titleSmall: const TextStyle(fontWeight: FontWeight.w600),
          labelLarge: const TextStyle(fontWeight: FontWeight.w600),
          bodyMedium: const TextStyle(height: 1.35),
          bodySmall: TextStyle(height: 1.3, color: scheme.onSurfaceVariant),
          labelSmall: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500),
        );
  }
}

/// Font family names - the app's two type roles (see [AppTheme._textTheme]
/// and [AppTypography.mono]).
class AppFonts {
  AppFonts._();
  static const String body = 'Figtree';
  static const String mono = 'IBM Plex Mono';
}

/// The third type role: tabular monospace figures for anything read like an
/// instrument-cluster readout - odometer, stat numbers, dates in a compact
/// card - never for running text. [FontFeature.tabularNums] keeps digits
/// aligned when they change (e.g. an animated counter).
class AppTypography {
  AppTypography._();

  static TextStyle mono(
    BuildContext context, {
    double? fontSize,
    FontWeight fontWeight = FontWeight.w600,
    Color? color,
  }) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return TextStyle(
      fontFamily: AppFonts.mono,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color ?? onSurface,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }
}

/// A gentle fade-through-with-lift transition used for every route so
/// navigation feels the same everywhere in the app.
class _AutoCarnetPageTransitionsBuilder extends PageTransitionsBuilder {
  const _AutoCarnetPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.03),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

/// Shared spacing scale so every screen breathes the same way.
class AppSpacing {
  AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

/// Shared corner-radius scale - deliberately tighter than the earlier
/// "Premium clair" concept (validated design concept, 2026, V2 pass): large
/// pill-like curvature everywhere was called out as reading "childish"
/// rather than premium. Small elements stay near-square, cards get a modest
/// curve, and only rare full-bleed sheets reach [xl].
class AppRadius {
  AppRadius._();
  static const double sm = 8;
  static const double md = 10;
  static const double lg = 12;
  static const double xl = 16;
}

/// Real, but genuinely subtle, elevation for the custom (non-`Card`)
/// containers most screens build by hand - a plain `Border.all` alone reads
/// as flat, but the earlier concept's shadows were too heavy (bloc
/// design-review 2026, V2 pass: "pas une grosse ombre derrière toutes les
/// cartes... quelque chose de subtil, à la iOS"). Two levels only: [card]
/// for ordinary surfaces (near-invisible, border does most of the work),
/// [raised] for anything that should read as a distinct floating surface
/// (a bottom sheet, a dialog).
class AppElevation {
  AppElevation._();

  static List<BoxShadow> card(ColorScheme scheme) => [
        BoxShadow(color: scheme.shadow.withValues(alpha: 0.04), blurRadius: 3, offset: const Offset(0, 1)),
      ];

  static List<BoxShadow> raised(ColorScheme scheme) => [
        BoxShadow(color: scheme.shadow.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 1)),
        BoxShadow(color: scheme.shadow.withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, 8), spreadRadius: -10),
      ];

  /// A colour-matched glow under a primary CTA, echoing the button's own
  /// colour rather than a neutral shadow - kept only for the rare CTA that
  /// should stand out (never applied everywhere).
  static List<BoxShadow> cta(Color color) => [
        BoxShadow(color: color.withValues(alpha: 0.24), blurRadius: 14, offset: const Offset(0, 6), spreadRadius: -6),
      ];
}

/// Shared motion durations/curves so animations feel consistent.
class AppMotion {
  AppMotion._();
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 400);
  static const Curve curve = Curves.easeOutCubic;
}
