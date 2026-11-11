# Mars industry

- Heaven-Ladder (`station:mars_3`): basic industry. Presses 2,400 empty canisters/hour, rolls 120 steel plates/hour, and makes two hull frames/hour. The primary anchor participates in industrial freight; access anchors do not duplicate facilities.
- Zhongke Intelligent Manufacturing (`station:mars_2`): ammunition production, sharing 24 processing units/hour. Missiles and torpedoes also consume imported electronics; future weapon/module manufacturing belongs here.
- Red Furnace (`station:mars_1`): ship dealership. Consumes frames delivered by ordinary freight, with no local frame/plate/canister/ammunition production.

These rates consolidate the preceding two-station totals. Existing repairs and storefronts are retained.

A frame-supplied dealership declares `frameSupply=true`. Empty sales slots set its frame inventory target, based on the largest hull it sells; inbound shipments count through the normal economy order rules. Full lots request no additional frames. Frame consumption respects freight reservations and records economic usage. Non-manufacturing dealerships retain their timed replenishment.

Hull frames start only at installations whose type declares `openingOutputs={hull_frame=2}`. This is an opening stock allowance, not periodic replenishment. The ordinary recipe output cap and required steel still govern ongoing production.
