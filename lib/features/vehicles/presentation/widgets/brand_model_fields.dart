import 'package:flutter/material.dart';

import '../../domain/vehicle_reference_data.dart';

/// Brand picker: suggests from [carBrands] but always accepts free text -
/// no static list covers every make on the road (Principe 7).
class BrandField extends StatefulWidget {
  const BrandField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.validator,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String? Function(String?)? validator;

  @override
  State<BrandField> createState() => _BrandFieldState();
}

class _BrandFieldState extends State<BrandField> {
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      optionsBuilder: (value) {
        if (value.text.trim().isEmpty) return carBrands;
        final query = value.text.trim().toLowerCase();
        return carBrands.where((b) => b.toLowerCase().contains(query));
      },
      onSelected: widget.onChanged,
      fieldViewBuilder: (context, fieldController, focusNode, onSubmit) {
        return TextFormField(
          controller: fieldController,
          focusNode: focusNode,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Marque *'),
          validator: widget.validator,
          onChanged: widget.onChanged,
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return _OptionsList(options: options, onSelected: onSelected);
      },
    );
  }
}

/// Model picker: suggests models for the currently selected [brand] when
/// known, otherwise falls back to free text only.
class ModelField extends StatefulWidget {
  const ModelField({
    super.key,
    required this.controller,
    required this.brand,
    required this.onChanged,
    this.validator,
  });

  final TextEditingController controller;
  final String brand;
  final ValueChanged<String> onChanged;
  final String? Function(String?)? validator;

  @override
  State<ModelField> createState() => _ModelFieldState();
}

class _ModelFieldState extends State<ModelField> {
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      optionsBuilder: (value) {
        final models = carModelsByBrand[widget.brand] ?? const <String>[];
        if (models.isEmpty) return const Iterable<String>.empty();
        if (value.text.trim().isEmpty) return models;
        final query = value.text.trim().toLowerCase();
        return models.where((m) => m.toLowerCase().contains(query));
      },
      onSelected: widget.onChanged,
      fieldViewBuilder: (context, fieldController, focusNode, onSubmit) {
        return TextFormField(
          controller: fieldController,
          focusNode: focusNode,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Modèle *'),
          validator: widget.validator,
          onChanged: widget.onChanged,
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return _OptionsList(options: options, onSelected: onSelected);
      },
    );
  }
}

class _OptionsList extends StatelessWidget {
  const _OptionsList({required this.options, required this.onSelected});
  final Iterable<String> options;
  final AutocompleteOnSelected<String> onSelected;

  @override
  Widget build(BuildContext context) {
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
                title: Text(option),
                onTap: () => onSelected(option),
              );
            },
          ),
        ),
      ),
    );
  }
}
