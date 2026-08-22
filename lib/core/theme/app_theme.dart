import 'package:flutter/material.dart';

/// Single source of truth for AutoCarnet's look & feel (Principe 1 & 10:
/// simple, consistent, easy to extend without touching every screen).
///
/// "Premium clair" identity (validated design concept, 2026): a warm ivory
/// ground instead of a generic Material grey/white, a deep forest green
/// (evolved from the original seed green) instead of an auto-generated M3
/// tonal palette, and a brass/copper accent for secondary emphasis - an
/// automotive-trim colour, not a bank-app blue. Colours are declared
/// explicitly (not `ColorScheme.fromSeed`) so every tone is a deliberate
/// choice rather than an algorithmic derivation.
class AppTheme {
  AppTheme._();

  static const Color seed = Color(0xFF234533);

  static ThemeData light() => _base(_lightScheme);
  static ThemeData dark() => _base(_darkScheme);

  static const ColorScheme _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF234533),
    onPrimary: Color(0xFFF4F6F0),
    primaryContainer: Color(0xFFDFE8DC),
    onPrimaryContainer: Color(0xFF13251A),
    secondary: Color(0xFFA97A3F),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFF3E6CF),
    onSecondaryContainer: Color(0xFF4A3216),
    tertiary: Color(0xFF4B6B57),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFDCE6DA),
    onTertiaryContainer: Color(0xFF13251A),
    error: Color(0xFFA14B3E),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFF4DFDA),
    onErrorContainer: Color(0xFF3F150F),
    surface: Color(0xFFF6F4EE),
    onSurface: Color(0xFF1B2620),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFFAF8F2),
    surfaceContainer: Color(0xFFF1EEE5),
    surfaceContainerHigh: Color(0xFFEAE6DA),
    surfaceContainerHighest: Color(0xFFE4DED0),
    onSurfaceVariant: Color(0xFF5C6B5F),
    outline: Color(0xFF8A9184),
    outlineVariant: Color(0xFFE4DED0),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFF1B2620),
    onInverseSurface: Color(0xFFF4F6F0),
    inversePrimary: Color(0xFF9FCBAA),
  );

  /// Dark companion of the same identity (deep green -> a lighter, dark-
  /// legible green; ivory -> graphite; same brass accent) rather than an
  /// unrelated palette - the two must read as one product.
  static const ColorScheme _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF8FCBA0),
    onPrimary: Color(0xFF0E1A12),
    primaryContainer: Color(0xFF25392B),
    onPrimaryContainer: Color(0xFFCFE6D5),
    secondary: Color(0xFFE2A75B),
    onSecondary: Color(0xFF2E2008),
    secondaryContainer: Color(0xFF3A2F1D),
    onSecondaryContainer: Color(0xFFF3DDB8),
    tertiary: Color(0xFF9BC2AC),
    onTertiary: Color(0xFF0E1A12),
    tertiaryContainer: Color(0xFF26332A),
    onTertiaryContainer: Color(0xFFCFE6D5),
    error: Color(0xFFE0876F),
    onError: Color(0xFF3C160E),
    errorContainer: Color(0xFF4D2118),
    onErrorContainer: Color(0xFFF6D3C8),
    surface: Color(0xFF14181A),
    onSurface: Color(0xFFEDE7DA),
    surfaceContainerLowest: Color(0xFF0E1111),
    surfaceContainerLow: Color(0xFF181C1D),
    surfaceContainer: Color(0xFF1D2224),
    surfaceContainerHigh: Color(0xFF262B2C),
    surfaceContainerHighest: Color(0xFF323836),
    onSurfaceVariant: Color(0xFFA3A99E),
    outline: Color(0xFF6C7269),
    outlineVariant: Color(0xFF32372F),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFEDE7DA),
    onInverseSurface: Color(0xFF14181A),
    inversePrimary: Color(0xFF234533),
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
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shadowColor: isDark ? Colors.transparent : scheme.shadow.withValues(alpha: 0.10),
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

/// Shared motion durations/curves so animations feel consistent.
class AppMotion {
  AppMotion._();
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 400);
  static const Curve curve = Curves.easeOutCubic;
}
