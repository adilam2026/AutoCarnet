import 'package:flutter/material.dart';

/// Single source of truth for AutoCarnet's look & feel (Principe 1 & 10:
/// simple, consistent, easy to extend without touching every screen).
///
/// "Auto Premium Clair" identity (validated design concept, 2026 - concept A
/// of the design-review pass): a cool light-grey ground instead of the
/// earlier warm ivory, a vivid automotive blue as the primary colour instead
/// of a desaturated forest green, and a turquoise-green accent for secondary
/// emphasis - chosen to read as a real automotive/premium product rather
/// than a financial dashboard. Colours are declared explicitly (not
/// `ColorScheme.fromSeed`) so every tone is a deliberate choice rather than
/// an algorithmic derivation.
class AppTheme {
  AppTheme._();

  static const Color seed = Color(0xFF1652F0);

  static ThemeData light() => _base(_lightScheme);
  static ThemeData dark() => _base(_darkScheme);

  static const ColorScheme _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF1652F0),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFE7EDFF),
    onPrimaryContainer: Color(0xFF10286B),
    secondary: Color(0xFF0EA37A),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFDFF7EE),
    onSecondaryContainer: Color(0xFF0A3D2E),
    tertiary: Color(0xFF4F7E6C),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFDDEAE3),
    onTertiaryContainer: Color(0xFF17332A),
    error: Color(0xFFE14343),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFBDEDE),
    onErrorContainer: Color(0xFF5C1414),
    surface: Color(0xFFF3F5FA),
    onSurface: Color(0xFF12151C),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF8F9FC),
    surfaceContainer: Color(0xFFEEF1F7),
    surfaceContainerHigh: Color(0xFFE7EBF3),
    surfaceContainerHighest: Color(0xFFDFE4EE),
    onSurfaceVariant: Color(0xFF535C6C),
    outline: Color(0xFF9AA1B0),
    outlineVariant: Color(0xFFE1E5EE),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFF12151C),
    onInverseSurface: Color(0xFFF3F5FA),
    inversePrimary: Color(0xFF9DB8FF),
  );

  /// Dark companion of the same identity (automotive blue -> a lightened
  /// blue that stays legible on a dark ground; turquoise accent kept, just
  /// lightened the same way) rather than an unrelated palette - the two
  /// must read as one product.
  static const ColorScheme _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF7FA2FF),
    onPrimary: Color(0xFF0A1B4A),
    primaryContainer: Color(0xFF1D3170),
    onPrimaryContainer: Color(0xFFD6E1FF),
    secondary: Color(0xFF4FD9AC),
    onSecondary: Color(0xFF06301F),
    secondaryContainer: Color(0xFF114A38),
    onSecondaryContainer: Color(0xFFC7F2E1),
    tertiary: Color(0xFF8FB8A8),
    onTertiary: Color(0xFF12281F),
    tertiaryContainer: Color(0xFF24392F),
    onTertiaryContainer: Color(0xFFD3E7DD),
    error: Color(0xFFF0857D),
    onError: Color(0xFF4A0E0E),
    errorContainer: Color(0xFF63201C),
    onErrorContainer: Color(0xFFFBDAD5),
    surface: Color(0xFF10141C),
    onSurface: Color(0xFFE7E9F0),
    surfaceContainerLowest: Color(0xFF0A0D13),
    surfaceContainerLow: Color(0xFF161B25),
    surfaceContainer: Color(0xFF1B212C),
    surfaceContainerHigh: Color(0xFF232A37),
    surfaceContainerHighest: Color(0xFF2C3442),
    onSurfaceVariant: Color(0xFFABB2C2),
    outline: Color(0xFF6B7386),
    outlineVariant: Color(0xFF333B49),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFE7E9F0),
    onInverseSurface: Color(0xFF10141C),
    inversePrimary: Color(0xFF1652F0),
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
        indicatorColor: scheme.primaryContainer,
        height: 64,
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

  /// Two type roles, deliberately: Figtree for every UI/body role (the
  /// workhorse - labels, buttons, running text), Fraunces only for the
  /// headline/titleLarge roles that read as editorial moments (a greeting,
  /// a vehicle name, a screen's big heading) - never applied wholesale, or
  /// the app would feel like a magazine instead of a tool. See
  /// [AppTypography.mono] for the third role (odometer/stat figures).
  static TextTheme _textTheme(ColorScheme scheme) {
    const base = Typography.blackMountainView;
    return base
        .apply(
          fontFamily: AppFonts.body,
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
        )
        .copyWith(
          headlineLarge: const TextStyle(
              fontFamily: AppFonts.display, fontWeight: FontWeight.w600, letterSpacing: -0.3),
          headlineMedium: const TextStyle(
              fontFamily: AppFonts.display, fontWeight: FontWeight.w600, letterSpacing: -0.3),
          headlineSmall: const TextStyle(
              fontFamily: AppFonts.display, fontWeight: FontWeight.w500, letterSpacing: -0.2),
          titleLarge: const TextStyle(
              fontFamily: AppFonts.display, fontWeight: FontWeight.w500, letterSpacing: -0.1),
          titleMedium: const TextStyle(fontWeight: FontWeight.w600),
          titleSmall: const TextStyle(fontWeight: FontWeight.w600),
          labelLarge: const TextStyle(fontWeight: FontWeight.w600),
          bodyMedium: const TextStyle(height: 1.35),
          bodySmall: TextStyle(height: 1.3, color: scheme.onSurfaceVariant),
          labelSmall: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500),
        );
  }
}

/// Font family names - the app's three type roles (see [AppTheme._textTheme]
/// and [AppTypography.mono]).
class AppFonts {
  AppFonts._();
  static const String body = 'Figtree';
  static const String display = 'Fraunces';
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

/// Shared corner-radius scale - softened slightly for the "Premium clair"
/// identity (validated design concept, 2026): more visible curvature on
/// cards reads as considered rather than default-Material.
class AppRadius {
  AppRadius._();
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
}

/// Real, if subtle, elevation for the custom (non-`Card`) containers most
/// screens build by hand - a plain `Border.all` reads as flat/"bancaire"
/// (bloc design-review 2026: "peu de relief"). Two levels only: [card] for
/// ordinary surfaces, [raised] for anything that should visibly float above
/// the rest (the vehicle hero card, a primary CTA).
class AppElevation {
  AppElevation._();

  static List<BoxShadow> card(ColorScheme scheme) => [
        BoxShadow(color: scheme.shadow.withValues(alpha: 0.04), blurRadius: 2, offset: const Offset(0, 1)),
        BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.10), blurRadius: 24, offset: const Offset(0, 10), spreadRadius: -12),
      ];

  static List<BoxShadow> raised(ColorScheme scheme) => [
        BoxShadow(color: scheme.shadow.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 3)),
        BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.16), blurRadius: 40, offset: const Offset(0, 18), spreadRadius: -14),
      ];

  /// A colour-matched glow under a primary CTA, echoing the button's own
  /// colour rather than a neutral shadow - the "gros CTA premium" look.
  static List<BoxShadow> cta(Color color) => [
        BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 22, offset: const Offset(0, 10), spreadRadius: -8),
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
