import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/address.dart';
import 'address_providers.dart';

/// Which saved address is currently selected for checkout.
class AddressSelectionState extends Equatable {
  const AddressSelectionState({this.selectedId});

  final String? selectedId;

  AddressSelectionState copyWith({String? selectedId}) =>
      AddressSelectionState(selectedId: selectedId ?? this.selectedId);

  @override
  List<Object?> get props => [selectedId];
}

/// Tracks the selected delivery address. Initialised to the default address.
class AddressSelectionController extends Notifier<AddressSelectionState> {
  @override
  AddressSelectionState build() => AddressSelectionState(
        selectedId: ref.read(defaultAddressProvider)?.id,
      );

  void select(String id) => state = AddressSelectionState(selectedId: id);
}

final addressSelectionProvider =
    NotifierProvider<AddressSelectionController, AddressSelectionState>(
        AddressSelectionController.new);

/// The resolved selected [Address] (falls back to default, then first).
final selectedAddressProvider = Provider<Address?>((ref) {
  final list = ref.watch(addressesProvider);
  if (list.isEmpty) return null;
  final id = ref.watch(addressSelectionProvider).selectedId;
  for (final a in list) {
    if (a.id == id) return a;
  }
  for (final a in list) {
    if (a.isDefault) return a;
  }
  return list.first;
});
