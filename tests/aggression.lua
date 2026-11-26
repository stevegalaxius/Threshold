return function()
	local A = require("src.aggression")
	local T = require("src.tuning")
	local u = {clock=10}
	assert(not A.find(u,"attacker","victim","earth",10) and not u.aggression,
		"an idle lookup allocated an incident store")
	local first=A.record(u,"attacker","victim","earth",10,"gun","earth/trade_buoy_a")
	first.reportedAt=10
	first.dispatched=true
	for i=1,500 do
		assert(A.record(u,"attacker","victim","earth",10+i/1000,"laser")==first)
	end
	assert(#u.aggression.slots==1 and first.lastAt==10.5 and first.cause=="laser"
		and first.firstAt==10 and first.node=="earth/trade_buoy_a" and first.dispatched,
		"repeated hits grew the record or reset dispatch")
	assert(not A.record(u,"attacker","victim","earth",10.25,"combat") and first.lastAt==10.5,
		"a late offline round rewound a newer incident")
	local other=A.record(u,"attacker","victim","mars",11,"combat")
	assert(A.find(u,"attacker","victim","earth",11)==first and other~=first,
		"the same actors in another jurisdiction overwrote an incident")
	u.clock=11
	local snapshot=A.snapshot(u)
	local restored={aggression=snapshot,clock=u.clock}
	local saved=A.find(restored,"attacker","victim","earth",11)
	assert(saved and saved~=first and saved.reportedAt==10 and saved.dispatched,
		"restoring the saved ring lost the incident or dispatch history")
	for i=1,A.capacity+8 do A.record(u,"attacker "..i,"victim","earth",11,"gun") end
	assert(#u.aggression.slots==A.capacity and not A.find(u,"attacker","victim","earth",11)
		and A.find(u,"attacker "..(A.capacity+8),"victim","earth",11),
		"ring overflow left stale index entries or exceeded its capacity")
	u.clock=11+T.aggressionWindow
	assert(not A.find(u,"attacker "..(A.capacity+8),"victim","earth",u.clock) and not A.snapshot(u),
		"expired incidents remained visible or took space in the save")
	local record={id="old",lastRaid={victim="civilian",area="earth",clock=11,alerted=true}}
	A.migrate(restored,record)
	assert(not record.lastRaid and A.find(restored,"old","civilian","earth",11).dispatched,
		"legacy raid report was not migrated")
	print("ok  aggression incidents: coalescing, bounded storage, expiry, migration and save lookup")
end
