import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../data/provider_repository.dart';

/// Reusable autocomplete used by documents, maintenance, expenses and fuel
/// forms so a provider is only ever typed once and reused everywhere after
/// (Principe 3).
class ProviderPickerField extends ConsumerStatefulWidget {
  const ProviderPickerField({
    super.key,
    required this.onSelected,
    this.onTextChanged,
    this.initialName,
    this.label = 'Prestataire',
  });

  final ValueChanged<ServiceProvider?> onSelected;
  /// Raw text currently typed, kept in sync even when it doesn't match an
  /// existing suggestion - callers need this at save time so a genuinely
  /// new provider still gets remembered (bloc: "mémoriser les garages /
  /// prestataires saisis").
  final ValueChanged<String>? onTextChanged;
  final String? initialName;
  final String label;

  @override
  ConsumerState<ProviderPickerField> createState() =>
      _ProviderPickerFieldState();
}

class _ProviderPickerFieldState extends ConsumerState<ProviderPickerField> {
  ServiceProvider? _selected;

  @override
  Widget build(BuildContext context) {
    return Autocomplete<ServiceProvider>(
      initialValue: TextEditingValue(text: widget.initialName ?? ''),
      displayStringForOption: (p) => p.name,
      optionsBuilder: (value) async {
        if (value.text.trim().isEmpty) return const [];
        return ref.read(providerRepositoryProvider).search(value.text.trim());
      },
      onSelected: (p) {
        _selected = p;
        widget.onSelected(p);
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(labelText: widget.label),
          onChanged: (text) {
            if (_selected != null && text != _selected!.name) {
              _selected = null;
              widget.onSelected(null);
            }
            widget.onTextChanged?.call(text);
          },
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, maxWidth: 360),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  return ListTile(
                    dense: true,
                    title: Text(option.name),
                    subtitle: option.city != null ? Text(option.city!) : null,
                    onTap: () => onSelected(option),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Resolves free text typed in [ProviderPickerField] into an existing
/// provider id, or silently creates one - the user never has to open a
/// separate "manage providers" screen just to log an operation.
Future<String?> resolveOrCreateProvider(
  WidgetRef ref, {
  required ServiceProvider? selected,
  required String typedText,
}) async {
  if (selected != null) return selected.id;
  final text = typedText.trim();
  if (text.isEmpty) return null;
  final repo = ref.read(providerRepositoryProvider);
  // A strong match ("Audi Casa" vs "Garage Audi Casablanca") reuses the
  // existing référentiel entry instead of spawning a near-duplicate one.
  final duplicate = await repo.findLikelyDuplicate(text);
  if (duplicate != null) return duplicate.id;
  return repo.createProvider(name: text);
}
