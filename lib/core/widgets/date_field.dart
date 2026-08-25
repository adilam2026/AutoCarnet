import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// "JJ/MM/AAAA", zero-padded - the one and only date format ever shown to
/// the user (mission 2026, point 1: "il ne faut surtout pas afficher
/// mm/dd/yyyy"). Every screen previously built this ad-hoc, without
/// leading zeros (`'${d.day}/${d.month}/${d.year}'`, e.g. "5/3/2026") -
/// this is the single shared source of truth every date display now goes
/// through instead.
String formatDdMmYyyy(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/'
    '${d.month.toString().padLeft(2, '0')}/'
    '${d.year.toString().padLeft(4, '0')}';

/// Strict "JJ/MM/AAAA" parse: real calendar validity (day-in-month,
/// leap years via the "day 0 of next month" trick), not just a
/// digit-shape check - an invalid date (31/02/2026, month 13...) must
/// never silently become "the closest valid date AutoCarnet could guess",
/// it must simply fail to parse (mission point 1: "validation finale").
DateTime? parseDdMmYyyy(String text) {
  final match = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(text.trim());
  if (match == null) return null;
  final day = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final year = int.parse(match.group(3)!);
  if (month < 1 || month > 12) return null;
  if (year < 1900 || year > 2100) return null;
  final daysInMonth = DateTime(year, month + 1, 0).day;
  if (day < 1 || day > daysInMonth) return null;
  return DateTime(year, month, day);
}

/// Auto-inserts the two "/" separators as the user types digits
/// (mission point 1: "l'utilisateur ne doit pas avoir à taper les slashs
/// lui-même") - "12" becomes "12/", "1208" becomes "12/08/", etc. Also
/// undoes itself cleanly on backspace: deleting the character right
/// before an auto-inserted "/" removes that digit too, instead of the
/// separator being silently re-inserted and backspace appearing stuck.
class DateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var raw = newValue.text;
    final isTrailingSingleCharDeletion = newValue.text.length ==
            oldValue.text.length - 1 &&
        oldValue.text.isNotEmpty &&
        oldValue.text.endsWith('/') &&
        newValue.text == oldValue.text.substring(0, oldValue.text.length - 1);
    if (isTrailingSingleCharDeletion) {
      raw = raw.substring(0, raw.length - 1);
    }

    var digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > 8) digits = digits.substring(0, 8);

    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      buffer.write(digits[i]);
      if (i == 1 || i == 3) buffer.write('/');
    }
    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// A real "JJ/MM/AAAA" typing mask (mission 2026, point 1) with a calendar
/// icon alongside for anyone who still prefers picking a date - every
/// manual date entry in the app goes through this one widget instead of
/// each screen reinventing its own picker button and its own (unpadded,
/// inconsistent) display format.
///
/// [onChanged] fires with a real [DateTime] as soon as the typed text is a
/// complete, calendar-valid date, or with `null` when the field is
/// cleared entirely - a partially-typed or structurally invalid date
/// (handled by [validator] at submit time, mission point 1: "validation
/// finale") never overwrites whatever value the caller last committed, so
/// mid-typing can never corrupt state a caller is holding onto.
class AppDateField extends StatefulWidget {
  const AppDateField({
    super.key,
    required this.label,
    this.initialDate,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
    this.requiredField = false,
  });

  final String label;
  final DateTime? initialDate;
  final ValueChanged<DateTime?> onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final bool requiredField;

  @override
  State<AppDateField> createState() => AppDateFieldState();
}

class AppDateFieldState extends State<AppDateField> {
  late final TextEditingController _controller;
  DateTime? _lastNotified;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialDate == null ? '' : formatDdMmYyyy(widget.initialDate!),
    );
    _lastNotified = widget.initialDate;
  }

  @override
  void didUpdateWidget(covariant AppDateField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only re-sync the displayed text when the CALLER moved the value to
    // something this field itself didn't just report (e.g. an
    // auto-suggested échéance recomputed elsewhere) - never while the
    // field's own typing is what's driving the value.
    if (widget.initialDate != _lastNotified) {
      _lastNotified = widget.initialDate;
      _controller.text =
          widget.initialDate == null ? '' : formatDdMmYyyy(widget.initialDate!);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged(String text) {
    if (text.isEmpty) {
      _lastNotified = null;
      widget.onChanged(null);
      return;
    }
    if (text.length == 10) {
      final parsed = parseDdMmYyyy(text);
      if (parsed != null) {
        _lastNotified = parsed;
        widget.onChanged(parsed);
      }
    }
  }

  Future<void> _pick() async {
    final picked = await showDatePicker(
      context: context,
      initialDate:
          parseDdMmYyyy(_controller.text) ?? widget.initialDate ?? DateTime.now(),
      firstDate: widget.firstDate ?? DateTime(1990),
      lastDate: widget.lastDate ?? DateTime(2100),
    );
    if (picked != null) {
      setState(() => _controller.text = formatDdMmYyyy(picked));
      _lastNotified = picked;
      widget.onChanged(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        DateInputFormatter(),
      ],
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: 'JJ/MM/AAAA',
        suffixIcon: IconButton(
          tooltip: 'Choisir dans le calendrier',
          icon: const Icon(Icons.calendar_today_outlined, size: 19),
          onPressed: _pick,
        ),
      ),
      onChanged: _onTextChanged,
      validator: (v) {
        final text = (v ?? '').trim();
        if (text.isEmpty) {
          return widget.requiredField ? 'Date requise' : null;
        }
        if (parseDdMmYyyy(text) == null) return 'Date invalide (JJ/MM/AAAA)';
        return null;
      },
    );
  }
}
