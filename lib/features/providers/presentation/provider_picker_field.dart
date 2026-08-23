import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../account/data/account_repository.dart';
import '../data/provider_repository.dart';

/// Reusable autocomplete used by documents, maintenance, expenses and fuel
/// forms so a provider is only ever typed once and reused everywhere after
/// (Principe 3) - a single coherent selector for every module (mission
/// point 5: "ne pas créer une UX différente pour chaque module"), not a
/// bespoke dropdown per screen.
class ProviderPickerField extends ConsumerStatefulWidget {
  const ProviderPickerField({
    super.key,
    required this.onSelected,
    this.onTextChanged,
    this.initialName,
    this.label = 'Prestataire',
    this.category,
    this.presetSuggestions = const [],
  });

  final ValueChanged<ServiceProvider?> onSelected;
  /// Raw text currently typed, kept in sync even when it doesn't match an
  /// existing suggestion - callers need this at save time so a genuinely
  /// new provider still gets remembered (bloc: "mémoriser les garages /
  /// prestataires saisis").
  final ValueChanged<String>? onTextChanged;
  final String? initialName;
  final String label;

  /// Narrows suggestions to this category (e.g. only stations-service for
  /// the fuel form) and tags a brand-new provider created from this field
  /// with it - see [resolveOrCreateProvider]. An uncategorised existing
  /// provider is never hidden by this, only used to bias results.
  final ServiceProviderCategory? category;

  /// A short list of well-known names offered even before the user types
  /// anything (mission point 4/5: the preconfigured Moroccan insurers for
  /// the "Assurance" category) - tapping one behaves exactly like typing
  /// it, including "Autre" simply not being in the list (free typing
  /// already covers it).
  final List<String> presetSuggestions;

  @override
  ConsumerState<ProviderPickerField> createState() =>
      _ProviderPickerFieldState();
}

class _ProviderPickerFieldState extends ConsumerState<ProviderPickerField> {
  ServiceProvider? _selected;

  @override
  Widget build(BuildContext context) {
    return Autocomplete<Object>(
      initialValue: TextEditingValue(text: widget.initialName ?? ''),
      displayStringForOption: (o) => o is ServiceProvider ? o.name : o as String,
      optionsBuilder: (value) async {
        final query = value.text.trim();
        if (query.isEmpty) {
          return widget.presetSuggestions;
        }
        final currentUserId = ref.read(accountRepositoryProvider).currentUser?.id;
        final matches = await ref.read(providerRepositoryProvider).search(
              query,
              currentUserId: currentUserId,
              category: widget.category,
            );
        // Presets that match what's typed stay visible too, even if they
        // aren't (yet) a real saved provider.
        final matchingPresets = widget.presetSuggestions.where(
            (s) => s.toLowerCase().contains(query.toLowerCase()) &&
                !matches.any((m) => m.name.toLowerCase() == s.toLowerCase()));
        return [...matches, ...matchingPresets];
      },
      onSelected: (o) {
        if (o is ServiceProvider) {
          _selected = o;
          widget.onSelected(o);
        } else {
          // A tapped preset that isn't a saved provider yet - treated
          // exactly like freely typed text (resolveOrCreateProvider will
          // create it, tagged with widget.category).
          _selected = null;
          widget.onSelected(null);
          widget.onTextChanged?.call(o as String);
        }
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
                  if (option is ServiceProvider) {
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.storefront_outlined, size: 20),
                      title: Text(option.name),
                      subtitle: option.city != null ? Text(option.city!) : null,
                      onTap: () => onSelected(option),
                    );
                  }
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.add_circle_outline, size: 20),
                    title: Text(option as String),
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
/// separate "manage providers" screen just to log an operation. A newly
/// created provider is tagged with [category] (mission point 6:
/// "apprentissage des prestataires" - even a quick, inline creation still
/// ends up correctly typed for next time).
Future<String?> resolveOrCreateProvider(
  WidgetRef ref, {
  required ServiceProvider? selected,
  required String typedText,
  ServiceProviderCategory? category,
}) async {
  if (selected != null) return selected.id;
  final text = typedText.trim();
  if (text.isEmpty) return null;
  final repo = ref.read(providerRepositoryProvider);
  final currentUserId = ref.read(accountRepositoryProvider).currentUser?.id;
  // A strong match ("Audi Casa" vs "Garage Audi Casablanca") reuses the
  // existing référentiel entry instead of spawning a near-duplicate one.
  final duplicate = await repo.findLikelyDuplicate(text, currentUserId: currentUserId);
  if (duplicate != null) return duplicate.id;
  return repo.createProvider(name: text, category: category, currentUserId: currentUserId);
}
