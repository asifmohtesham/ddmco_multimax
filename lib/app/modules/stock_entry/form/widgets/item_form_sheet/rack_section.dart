// P2-3: stub re-export — SharedDualRackSection is the canonical implementation.
// All existing call sites use `RackSection` which is aliased below.
export 'package:multimax/app/shared/item_sheet/widgets/shared_dual_rack_section.dart';
typedef RackSection = SharedDualRackSection;
