// P2-3: stub re-export — SharedDualRackSection is the canonical implementation.
// All existing call sites use `RackSection` which is aliased below.
//
// Commit 8: SharedDualRackSection is now typed to DualRackDelegate (interface),
// not StockEntryItemFormController (concrete class). The typedef is preserved
// so callers in StockEntryFormController._openItemSheet compile without change.
import 'package:multimax/app/shared/item_sheet/widgets/shared_dual_rack_section.dart';
export 'package:multimax/app/shared/item_sheet/widgets/shared_dual_rack_section.dart';
typedef RackSection = SharedDualRackSection;
