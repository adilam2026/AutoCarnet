import '../../../core/database/database.dart';

/// Shared French label for [VehicleFinishLevel], used by both the creation
/// and edit screens so the wording never drifts between the two.
String finishLevelLabel(VehicleFinishLevel level) => switch (level) {
      VehicleFinishLevel.entryLevel => 'Entrée de gamme',
      VehicleFinishLevel.midRange => 'Milieu de gamme',
      VehicleFinishLevel.highEnd => 'Haut de gamme',
      VehicleFinishLevel.fullOptions => 'Full options / Toutes options',
    };
