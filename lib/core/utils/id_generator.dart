import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Single place that mints entity identifiers so they are never reused
/// (RG-DATA-006) and stay consistent across every module.
String newId() => _uuid.v4();
