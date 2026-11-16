-- Station design (habitat). Open and edit in the Shipyard (F2).
station {
	id = "zhuhai_tulou",
	name = "Zhuhai tulou",
	role = "habitat",
	services = { "market", "hangar", "repair" },
	color = { 0.86, 0.46, 0.34 },
	berths = {
		{ heading = -158, size = 110, x = -730, y = -302 },
		{ heading = -112, size = 110, x = -302, y = -730 },
		{ heading = -68, size = 110, x = 302, y = -730 },
		{ heading = 68, size = 110, x = 302, y = 730 },
		{ heading = 112, size = 110, x = -302, y = 730 },
		{ heading = 158, size = 110, x = -730, y = 302 },
	},
	turrets = {
		{ module = "gun_m_base", x = 590, y = 1022 },
		{ module = "gun_m_base", x = -1180, y = 0 },
		{ module = "gun_m_base", x = 590, y = -1022 },
	},
	parts = {
		{ name = "earth wall 1", shape = { -1240, 0, -1300, 0, -1284, -203.4, -1224.7, -194 }, shade = 0.85, color = { 0.78, 0.62, 0.46 } },
		{ name = "rooms 1", shape = { -980, 0, -1240, 0, -1224.7, -194, -967.9, -153.3 }, shade = 0.95, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 7, x = -1006.89, y = -79.24 },
			{ color = { 1, 0.42, 0.25 }, kind = "window", size = 10, x = -965.02, y = -75.95 },
		} },
		{ name = "roof ridge 1", shape = { -1102, 0, -1118, 0, -1104.2, -174.9, -1088.4, -172.4 }, shade = 1.35, tint = { 0.14, 0.12, -0.12 }, layer = "detail", collide = false },
		{ name = "earth wall 2", shape = { -1224.7, -194, -1284, -203.4, -1236.4, -401.7, -1179.3, -383.2 }, shade = 0.85, color = { 0.78, 0.62, 0.46 }, lights = {
			{ kind = "window", size = 5, x = -1234.91, y = -296.48 },
		} },
		{ name = "rooms 2", shape = { -967.9, -153.3, -1224.7, -194, -1179.3, -383.2, -932, -302.8 }, shade = 0.95, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 7, x = -982.09, y = -235.78 },
		} },
		{ name = "roof ridge 2", shape = { -1088.4, -172.4, -1104.2, -174.9, -1063.3, -345.5, -1048.1, -340.5 }, shade = 1.35, tint = { 0.14, 0.12, -0.12 }, layer = "detail", collide = false },
		{ name = "earth wall 3", shape = { -1179.3, -383.2, -1236.4, -401.7, -1158.3, -590.2, -1104.8, -562.9 }, shade = 0.85, color = { 0.78, 0.62, 0.46 } },
		{ name = "rooms 3", shape = { -932, -302.8, -1179.3, -383.2, -1104.8, -562.9, -873.2, -444.9 }, shade = 0.95, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 7, x = -933.12, y = -386.51 },
		} },
		{ name = "roof ridge 3", shape = { -1048.1, -340.5, -1063.3, -345.5, -996.1, -507.6, -981.9, -500.3 }, shade = 1.35, tint = { 0.14, 0.12, -0.12 }, layer = "detail", collide = false },
		{ name = "earth wall 4", shape = { -1104.8, -562.9, -1158.3, -590.2, -1051.7, -764.1, -1003.2, -728.9 }, shade = 0.85, color = { 0.78, 0.62, 0.46 }, lights = {
			{ kind = "window", size = 5, x = -1082.85, y = -663.57 },
		} },
		{ name = "rooms 4", shape = { -873.2, -444.9, -1104.8, -562.9, -1003.2, -728.9, -792.8, -576 }, shade = 0.95, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 7, x = -861.17, y = -527.72 },
		} },
		{ name = "roof ridge 4", shape = { -981.9, -500.3, -996.1, -507.6, -904.5, -657.1, -891.5, -647.7 }, shade = 1.35, tint = { 0.14, 0.12, -0.12 }, layer = "detail", collide = false },
		{ name = "earth wall 5", shape = { -1003.2, -728.9, -1051.7, -764.1, -919.2, -919.2, -876.8, -876.8 }, shade = 0.85, color = { 0.78, 0.62, 0.46 } },
		{ name = "rooms 5", shape = { -792.8, -576, -1003.2, -728.9, -876.8, -876.8, -693, -693 }, shade = 0.95, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 7, x = -768.01, y = -655.94 },
			{ color = { 1, 0.42, 0.25 }, kind = "window", size = 10, x = -736.07, y = -628.67 },
		} },
		{ name = "roof ridge 5", shape = { -891.5, -647.7, -904.5, -657.1, -790.5, -790.5, -779.2, -779.2 }, shade = 1.35, tint = { 0.14, 0.12, -0.12 }, layer = "detail", collide = false },
		{ name = "earth wall 6", shape = { -876.8, -876.8, -919.2, -919.2, -764.1, -1051.7, -728.9, -1003.2 }, shade = 0.85, color = { 0.78, 0.62, 0.46 }, lights = {
			{ kind = "window", size = 5, x = -824.8, y = -965.72 },
		} },
		{ name = "rooms 6", shape = { -693, -693, -876.8, -876.8, -728.9, -1003.2, -576, -792.8 }, shade = 0.95, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 7, x = -655.94, y = -768.01 },
		} },
		{ name = "roof ridge 6", shape = { -779.2, -779.2, -790.5, -790.5, -657.1, -904.5, -647.7, -891.5 }, shade = 1.35, tint = { 0.14, 0.12, -0.12 }, layer = "detail", collide = false },
		{ name = "earth wall 7", shape = { -728.9, -1003.2, -764.1, -1051.7, -590.2, -1158.3, -562.9, -1104.8 }, shade = 0.85, color = { 0.78, 0.62, 0.46 } },
		{ name = "rooms 7", shape = { -576, -792.8, -728.9, -1003.2, -562.9, -1104.8, -444.9, -873.2 }, shade = 0.95, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 7, x = -527.72, y = -861.17 },
		} },
		{ name = "roof ridge 7", shape = { -647.7, -891.5, -657.1, -904.5, -507.6, -996.1, -500.3, -981.9 }, shade = 1.35, tint = { 0.14, 0.12, -0.12 }, layer = "detail", collide = false },
		{ name = "earth wall 8", shape = { -562.9, -1104.8, -590.2, -1158.3, -401.7, -1236.4, -383.2, -1179.3 }, shade = 0.85, color = { 0.78, 0.62, 0.46 }, lights = {
			{ kind = "window", size = 5, x = -486.01, y = -1173.33 },
		} },
		{ name = "rooms 8", shape = { -444.9, -873.2, -562.9, -1104.8, -383.2, -1179.3, -302.8, -932 }, shade = 0.95, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 7, x = -386.51, y = -933.12 },
		} },
		{ name = "roof ridge 8", shape = { -500.3, -981.9, -507.6, -996.1, -345.5, -1063.3, -340.5, -1048.1 }, shade = 1.35, tint = { 0.14, 0.12, -0.12 }, layer = "detail", collide = false },
		{ name = "earth wall 9", shape = { -383.2, -1179.3, -401.7, -1236.4, -203.4, -1284, -194, -1224.7 }, shade = 0.85, color = { 0.78, 0.62, 0.46 } },
		{ name = "rooms 9", shape = { -302.8, -932, -383.2, -1179.3, -194, -1224.7, -153.3, -967.9 }, shade = 0.95, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 7, x = -235.78, y = -982.09 },
			{ color = { 1, 0.42, 0.25 }, kind = "window", size = 10, x = -225.98, y = -941.25 },
		} },
		{ name = "roof ridge 9", shape = { -340.5, -1048.1, -345.5, -1063.3, -174.9, -1104.2, -172.4, -1088.4 }, shade = 1.35, tint = { 0.14, 0.12, -0.12 }, layer = "detail", collide = false },
		{ name = "earth wall 10", shape = { -194, -1224.7, -203.4, -1284, 0, -1300, 0, -1240 }, shade = 0.85, color = { 0.78, 0.62, 0.46 }, lights = {
			{ kind = "window", size = 5, x = -99.64, y = -1266.09 },
		} },
		{ name = "rooms 10", shape = { -153.3, -967.9, -194, -1224.7, 0, -1240, 0, -980 }, shade = 0.95, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 7, x = -79.24, y = -1006.89 },
		} },
		{ name = "roof ridge 10", shape = { -172.4, -1088.4, -174.9, -1104.2, 0, -1118, 0, -1102 }, shade = 1.35, tint = { 0.14, 0.12, -0.12 }, layer = "detail", collide = false },
		{ name = "earth wall 11", shape = { 0, -1240, 0, -1300, 203.4, -1284, 194, -1224.7 }, shade = 0.85, color = { 0.78, 0.62, 0.46 } },
		{ name = "rooms 11", shape = { 0, -980, 0, -1240, 194, -1224.7, 153.3, -967.9 }, shade = 0.95, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 7, x = 79.24, y = -1006.89 },
		} },
		{ name = "roof ridge 11", shape = { 0, -1102, 0, -1118, 174.9, -1104.2, 172.4, -1088.4 }, shade = 1.35, tint = { 0.14, 0.12, -0.12 }, layer = "detail", collide = false },
		{ name = "earth wall 12", shape = { 194, -1224.7, 203.4, -1284, 401.7, -1236.4, 383.2, -1179.3 }, shade = 0.85, color = { 0.78, 0.62, 0.46 }, lights = {
			{ kind = "window", size = 5, x = 296.48, y = -1234.91 },
		} },
		{ name = "rooms 12", shape = { 153.3, -967.9, 194, -1224.7, 383.2, -1179.3, 302.8, -932 }, shade = 0.95, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 7, x = 235.78, y = -982.09 },
		} },
		{ name = "roof ridge 12", shape = { 172.4, -1088.4, 174.9, -1104.2, 345.5, -1063.3, 340.5, -1048.1 }, shade = 1.35, tint = { 0.14, 0.12, -0.12 }, layer = "detail", collide = false },
		{ name = "earth wall 13", shape = { 383.2, -1179.3, 401.7, -1236.4, 590.2, -1158.3, 562.9, -1104.8 }, shade = 0.85, color = { 0.78, 0.62, 0.46 } },
		{ name = "rooms 13", shape = { 302.8, -932, 383.2, -1179.3, 562.9, -1104.8, 444.9, -873.2 }, shade = 0.95, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 7, x = 386.51, y = -933.12 },
			{ color = { 1, 0.42, 0.25 }, kind = "window", size = 10, x = 370.44, y = -894.32 },
		} },
		{ name = "roof ridge 13", shape = { 340.5, -1048.1, 345.5, -1063.3, 507.6, -996.1, 500.3, -981.9 }, shade = 1.35, tint = { 0.14, 0.12, -0.12 }, layer = "detail", collide = false },
		{ name = "earth wall 14", shape = { 562.9, -1104.8, 590.2, -1158.3, 764.1, -1051.7, 728.9, -1003.2 }, shade = 0.85, color = { 0.78, 0.62, 0.46 }, lights = {
			{ kind = "window", size = 5, x = 663.57, y = -1082.85 },
		} },
		{ name = "rooms 14", shape = { 444.9, -873.2, 562.9, -1104.8, 728.9, -1003.2, 576, -792.8 }, shade = 0.95, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 7, x = 527.72, y = -861.17 },
		} },
		{ name = "roof ridge 14", shape = { 500.3, -981.9, 507.6, -996.1, 657.1, -904.5, 647.7, -891.5 }, shade = 1.35, tint = { 0.14, 0.12, -0.12 }, layer = "detail", collide = false },
		{ name = "earth wall 15", shape = { 728.9, -1003.2, 764.1, -1051.7, 919.2, -919.2, 876.8, -876.8 }, shade = 0.85, color = { 0.78, 0.62, 0.46 } },
		{ name = "rooms 15", shape = { 576, -792.8, 728.9, -1003.2, 876.8, -876.8, 693, -693 }, shade = 0.95, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 7, x = 655.94, y = -768.01 },
		} },
		{ name = "roof ridge 15", shape = { 647.7, -891.5, 657.1, -904.5, 790.5, -790.5, 779.2, -779.2 }, shade = 1.35, tint = { 0.14, 0.12, -0.12 }, layer = "detail", collide = false },
		{ name = "earth wall 16", shape = { 876.8, -876.8, 919.2, -919.2, 1051.7, -764.1, 1003.2, -728.9 }, shade = 0.85, color = { 0.78, 0.62, 0.46 }, lights = {
			{ kind = "window", size = 5, x = 965.72, y = -824.8 },
		} },
		{ name = "rooms 16", shape = { 693, -693, 876.8, -876.8, 1003.2, -728.9, 792.8, -576 }, shade = 0.95, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 7, x = 768.01, y = -655.94 },
		} },
		{ name = "roof ridge 16", shape = { 779.2, -779.2, 790.5, -790.5, 904.5, -657.1, 891.5, -647.7 }, shade = 1.35, tint = { 0.14, 0.12, -0.12 }, layer = "detail", collide = false },
		{ name = "earth wall 17", shape = { 1003.2, -728.9, 1051.7, -764.1, 1158.3, -590.2, 1104.8, -562.9 }, shade = 0.85, color = { 0.78, 0.62, 0.46 } },
		{ name = "rooms 17", shape = { 792.8, -576, 1003.2, -728.9, 1104.8, -562.9, 873.2, -444.9 }, shade = 0.95, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 7, x = 861.17, y = -527.72 },
			{ color = { 1, 0.42, 0.25 }, kind = "window", size = 10, x = 825.36, y = -505.78 },
		} },
		{ name = "roof ridge 17", shape = { 891.5, -647.7, 904.5, -657.1, 996.1, -507.6, 981.9, -500.3 }, shade = 1.35, tint = { 0.14, 0.12, -0.12 }, layer = "detail", collide = false },
		{ name = "earth wall 18", shape = { 1104.8, -562.9, 1158.3, -590.2, 1236.4, -401.7, 1179.3, -383.2 }, shade = 0.85, color = { 0.78, 0.62, 0.46 }, lights = {
			{ kind = "window", size = 5, x = 1173.33, y = -486.01 },
		} },
		{ name = "rooms 18", shape = { 873.2, -444.9, 1104.8, -562.9, 1179.3, -383.2, 932, -302.8 }, shade = 0.95, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 7, x = 933.12, y = -386.51 },
		} },
		{ name = "roof ridge 18", shape = { 981.9, -500.3, 996.1, -507.6, 1063.3, -345.5, 1048.1, -340.5 }, shade = 1.35, tint = { 0.14, 0.12, -0.12 }, layer = "detail", collide = false },
		{ name = "earth wall 23", shape = { 1179.3, 383.2, 1236.4, 401.7, 1158.3, 590.2, 1104.8, 562.9 }, shade = 0.85, color = { 0.78, 0.62, 0.46 } },
		{ name = "rooms 23", shape = { 932, 302.8, 1179.3, 383.2, 1104.8, 562.9, 873.2, 444.9 }, shade = 0.95, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 7, x = 933.12, y = 386.51 },
		} },
		{ name = "roof ridge 23", shape = { 1048.1, 340.5, 1063.3, 345.5, 996.1, 507.6, 981.9, 500.3 }, shade = 1.35, tint = { 0.14, 0.12, -0.12 }, layer = "detail", collide = false },
		{ name = "earth wall 24", shape = { 1104.8, 562.9, 1158.3, 590.2, 1051.7, 764.1, 1003.2, 728.9 }, shade = 0.85, color = { 0.78, 0.62, 0.46 }, lights = {
			{ kind = "window", size = 5, x = 1082.85, y = 663.57 },
		} },
		{ name = "rooms 24", shape = { 873.2, 444.9, 1104.8, 562.9, 1003.2, 728.9, 792.8, 576 }, shade = 0.95, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 7, x = 861.17, y = 527.72 },
		} },
		{ name = "roof ridge 24", shape = { 981.9, 500.3, 996.1, 507.6, 904.5, 657.1, 891.5, 647.7 }, shade = 1.35, tint = { 0.14, 0.12, -0.12 }, layer = "detail", collide = false },
		{ name = "earth wall 25", shape = { 1003.2, 728.9, 1051.7, 764.1, 919.2, 919.2, 876.8, 876.8 }, shade = 0.85, color = { 0.78, 0.62, 0.46 } },
		{ name = "rooms 25", shape = { 792.8, 576, 1003.2, 728.9, 876.8, 876.8, 693, 693 }, shade = 0.95, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 7, x = 768.01, y = 655.94 },
			{ color = { 1, 0.42, 0.25 }, kind = "window", size = 10, x = 736.07, y = 628.67 },
		} },
		{ name = "roof ridge 25", shape = { 891.5, 647.7, 904.5, 657.1, 790.5, 790.5, 779.2, 779.2 }, shade = 1.35, tint = { 0.14, 0.12, -0.12 }, layer = "detail", collide = false },
		{ name = "earth wall 26", shape = { 876.8, 876.8, 919.2, 919.2, 764.1, 1051.7, 728.9, 1003.2 }, shade = 0.85, color = { 0.78, 0.62, 0.46 }, lights = {
			{ kind = "window", size = 5, x = 824.8, y = 965.72 },
		} },
		{ name = "rooms 26", shape = { 693, 693, 876.8, 876.8, 728.9, 1003.2, 576, 792.8 }, shade = 0.95, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 7, x = 655.94, y = 768.01 },
		} },
		{ name = "roof ridge 26", shape = { 779.2, 779.2, 790.5, 790.5, 657.1, 904.5, 647.7, 891.5 }, shade = 1.35, tint = { 0.14, 0.12, -0.12 }, layer = "detail", collide = false },
		{ name = "earth wall 27", shape = { 728.9, 1003.2, 764.1, 1051.7, 590.2, 1158.3, 562.9, 1104.8 }, shade = 0.85, color = { 0.78, 0.62, 0.46 } },
		{ name = "rooms 27", shape = { 576, 792.8, 728.9, 1003.2, 562.9, 1104.8, 444.9, 873.2 }, shade = 0.95, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 7, x = 527.72, y = 861.17 },
		} },
		{ name = "roof ridge 27", shape = { 647.7, 891.5, 657.1, 904.5, 507.6, 996.1, 500.3, 981.9 }, shade = 1.35, tint = { 0.14, 0.12, -0.12 }, layer = "detail", collide = false },
		{ name = "earth wall 28", shape = { 562.9, 1104.8, 590.2, 1158.3, 401.7, 1236.4, 383.2, 1179.3 }, shade = 0.85, color = { 0.78, 0.62, 0.46 }, lights = {
			{ kind = "window", size = 5, x = 486.01, y = 1173.33 },
		} },
		{ name = "rooms 28", shape = { 444.9, 873.2, 562.9, 1104.8, 383.2, 1179.3, 302.8, 932 }, shade = 0.95, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 7, x = 386.51, y = 933.12 },
		} },
		{ name = "roof ridge 28", shape = { 500.3, 981.9, 507.6, 996.1, 345.5, 1063.3, 340.5, 1048.1 }, shade = 1.35, tint = { 0.14, 0.12, -0.12 }, layer = "detail", collide = false },
		{ name = "earth wall 29", shape = { 383.2, 1179.3, 401.7, 1236.4, 203.4, 1284, 194, 1224.7 }, shade = 0.85, color = { 0.78, 0.62, 0.46 } },
		{ name = "rooms 29", shape = { 302.8, 932, 383.2, 1179.3, 194, 1224.7, 153.3, 967.9 }, shade = 0.95, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 7, x = 235.78, y = 982.09 },
			{ color = { 1, 0.42, 0.25 }, kind = "window", size = 10, x = 225.98, y = 941.25 },
		} },
		{ name = "roof ridge 29", shape = { 340.5, 1048.1, 345.5, 1063.3, 174.9, 1104.2, 172.4, 1088.4 }, shade = 1.35, tint = { 0.14, 0.12, -0.12 }, layer = "detail", collide = false },
		{ name = "earth wall 30", shape = { 194, 1224.7, 203.4, 1284, 0, 1300, 0, 1240 }, shade = 0.85, color = { 0.78, 0.62, 0.46 }, lights = {
			{ kind = "window", size = 5, x = 99.64, y = 1266.09 },
		} },
		{ name = "rooms 30", shape = { 153.3, 967.9, 194, 1224.7, 0, 1240, 0, 980 }, shade = 0.95, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 7, x = 79.24, y = 1006.89 },
		} },
		{ name = "roof ridge 30", shape = { 172.4, 1088.4, 174.9, 1104.2, 0, 1118, 0, 1102 }, shade = 1.35, tint = { 0.14, 0.12, -0.12 }, layer = "detail", collide = false },
		{ name = "earth wall 31", shape = { 0, 1240, 0, 1300, -203.4, 1284, -194, 1224.7 }, shade = 0.85, color = { 0.78, 0.62, 0.46 } },
		{ name = "rooms 31", shape = { 0, 980, 0, 1240, -194, 1224.7, -153.3, 967.9 }, shade = 0.95, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 7, x = -79.24, y = 1006.89 },
		} },
		{ name = "roof ridge 31", shape = { 0, 1102, 0, 1118, -174.9, 1104.2, -172.4, 1088.4 }, shade = 1.35, tint = { 0.14, 0.12, -0.12 }, layer = "detail", collide = false },
		{ name = "earth wall 32", shape = { -194, 1224.7, -203.4, 1284, -401.7, 1236.4, -383.2, 1179.3 }, shade = 0.85, color = { 0.78, 0.62, 0.46 }, lights = {
			{ kind = "window", size = 5, x = -296.48, y = 1234.91 },
		} },
		{ name = "rooms 32", shape = { -153.3, 967.9, -194, 1224.7, -383.2, 1179.3, -302.8, 932 }, shade = 0.95, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 7, x = -235.78, y = 982.09 },
		} },
		{ name = "roof ridge 32", shape = { -172.4, 1088.4, -174.9, 1104.2, -345.5, 1063.3, -340.5, 1048.1 }, shade = 1.35, tint = { 0.14, 0.12, -0.12 }, layer = "detail", collide = false },
		{ name = "earth wall 33", shape = { -383.2, 1179.3, -401.7, 1236.4, -590.2, 1158.3, -562.9, 1104.8 }, shade = 0.85, color = { 0.78, 0.62, 0.46 } },
		{ name = "rooms 33", shape = { -302.8, 932, -383.2, 1179.3, -562.9, 1104.8, -444.9, 873.2 }, shade = 0.95, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 7, x = -386.51, y = 933.12 },
			{ color = { 1, 0.42, 0.25 }, kind = "window", size = 10, x = -370.44, y = 894.32 },
		} },
		{ name = "roof ridge 33", shape = { -340.5, 1048.1, -345.5, 1063.3, -507.6, 996.1, -500.3, 981.9 }, shade = 1.35, tint = { 0.14, 0.12, -0.12 }, layer = "detail", collide = false },
		{ name = "earth wall 34", shape = { -562.9, 1104.8, -590.2, 1158.3, -764.1, 1051.7, -728.9, 1003.2 }, shade = 0.85, color = { 0.78, 0.62, 0.46 }, lights = {
			{ kind = "window", size = 5, x = -663.57, y = 1082.85 },
		} },
		{ name = "rooms 34", shape = { -444.9, 873.2, -562.9, 1104.8, -728.9, 1003.2, -576, 792.8 }, shade = 0.95, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 7, x = -527.72, y = 861.17 },
		} },
		{ name = "roof ridge 34", shape = { -500.3, 981.9, -507.6, 996.1, -657.1, 904.5, -647.7, 891.5 }, shade = 1.35, tint = { 0.14, 0.12, -0.12 }, layer = "detail", collide = false },
		{ name = "earth wall 35", shape = { -728.9, 1003.2, -764.1, 1051.7, -919.2, 919.2, -876.8, 876.8 }, shade = 0.85, color = { 0.78, 0.62, 0.46 } },
		{ name = "rooms 35", shape = { -576, 792.8, -728.9, 1003.2, -876.8, 876.8, -693, 693 }, shade = 0.95, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 7, x = -655.94, y = 768.01 },
		} },
		{ name = "roof ridge 35", shape = { -647.7, 891.5, -657.1, 904.5, -790.5, 790.5, -779.2, 779.2 }, shade = 1.35, tint = { 0.14, 0.12, -0.12 }, layer = "detail", collide = false },
		{ name = "earth wall 36", shape = { -876.8, 876.8, -919.2, 919.2, -1051.7, 764.1, -1003.2, 728.9 }, shade = 0.85, color = { 0.78, 0.62, 0.46 }, lights = {
			{ kind = "window", size = 5, x = -965.72, y = 824.8 },
		} },
		{ name = "rooms 36", shape = { -693, 693, -876.8, 876.8, -1003.2, 728.9, -792.8, 576 }, shade = 0.95, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 7, x = -768.01, y = 655.94 },
		} },
		{ name = "roof ridge 36", shape = { -779.2, 779.2, -790.5, 790.5, -904.5, 657.1, -891.5, 647.7 }, shade = 1.35, tint = { 0.14, 0.12, -0.12 }, layer = "detail", collide = false },
		{ name = "earth wall 37", shape = { -1003.2, 728.9, -1051.7, 764.1, -1158.3, 590.2, -1104.8, 562.9 }, shade = 0.85, color = { 0.78, 0.62, 0.46 } },
		{ name = "rooms 37", shape = { -792.8, 576, -1003.2, 728.9, -1104.8, 562.9, -873.2, 444.9 }, shade = 0.95, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 7, x = -861.17, y = 527.72 },
			{ color = { 1, 0.42, 0.25 }, kind = "window", size = 10, x = -825.36, y = 505.78 },
		} },
		{ name = "roof ridge 37", shape = { -891.5, 647.7, -904.5, 657.1, -996.1, 507.6, -981.9, 500.3 }, shade = 1.35, tint = { 0.14, 0.12, -0.12 }, layer = "detail", collide = false },
		{ name = "earth wall 38", shape = { -1104.8, 562.9, -1158.3, 590.2, -1236.4, 401.7, -1179.3, 383.2 }, shade = 0.85, color = { 0.78, 0.62, 0.46 }, lights = {
			{ kind = "window", size = 5, x = -1173.33, y = 486.01 },
		} },
		{ name = "rooms 38", shape = { -873.2, 444.9, -1104.8, 562.9, -1179.3, 383.2, -932, 302.8 }, shade = 0.95, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 7, x = -933.12, y = 386.51 },
		} },
		{ name = "roof ridge 38", shape = { -981.9, 500.3, -996.1, 507.6, -1063.3, 345.5, -1048.1, 340.5 }, shade = 1.35, tint = { 0.14, 0.12, -0.12 }, layer = "detail", collide = false },
		{ name = "earth wall 39", shape = { -1179.3, 383.2, -1236.4, 401.7, -1284, 203.4, -1224.7, 194 }, shade = 0.85, color = { 0.78, 0.62, 0.46 } },
		{ name = "rooms 39", shape = { -932, 302.8, -1179.3, 383.2, -1224.7, 194, -967.9, 153.3 }, shade = 0.95, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 7, x = -982.09, y = 235.78 },
		} },
		{ name = "roof ridge 39", shape = { -1048.1, 340.5, -1063.3, 345.5, -1104.2, 174.9, -1088.4, 172.4 }, shade = 1.35, tint = { 0.14, 0.12, -0.12 }, layer = "detail", collide = false },
		{ name = "earth wall 40", shape = { -1224.7, 194, -1284, 203.4, -1300, 0, -1240, 0 }, shade = 0.85, color = { 0.78, 0.62, 0.46 }, lights = {
			{ kind = "window", size = 5, x = -1266.09, y = 99.64 },
		} },
		{ name = "rooms 40", shape = { -967.9, 153.3, -1224.7, 194, -1240, 0, -980, 0 }, shade = 0.95, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 7, x = -1006.89, y = 79.24 },
		} },
		{ name = "roof ridge 40", shape = { -1088.4, 172.4, -1104.2, 174.9, -1118, 0, -1102, 0 }, shade = 1.35, tint = { 0.14, 0.12, -0.12 }, layer = "detail", collide = false },
		{ name = "gatehouse", shape = { 940, -150, 1390, -150, 1390, 150, 940, 150 }, shade = 0.75, color = { 0.78, 0.62, 0.46 }, lights = {
			{ color = { 1, 0.35, 0.3 }, kind = "strobe", size = 5, x = 1380, y = -140, rate = 0.62 },
			{ color = { 1, 0.35, 0.3 }, kind = "strobe", size = 5, x = 1380, y = 140, rate = 0.62 },
		}, dock = true, dockHeading = 0 },
		{ name = "gatehouse roof eaves", shape = { 1121.7, -120, 1358.3, -120, 1404.4, -134.4, 1390, -88.3, 1390, 88.3, 1404.4, 134.4, 1358.3, 120, 1121.7, 120, 1075.6, 134.4, 1090, 88.3, 1090, -88.3, 1075.6, -134.4 }, shade = 1, tint = { 0.14, 0.12, -0.12 } },
		{ name = "gatehouse roof ridge", shape = { 1210, -8.4, 1270, -8.4, 1270, 8.4, 1210, 8.4 }, shade = 1.35, layer = "detail", collide = false },
		{ name = "gatehouse roof hip 1", shape = { 1086.4, -116.4, 1206.4, 3.6, 1213.6, -3.6, 1093.6, -123.6 }, shade = 1.35, layer = "detail", collide = false },
		{ name = "gatehouse roof hip 2", shape = { 1386.4, -123.6, 1266.4, -3.6, 1273.6, 3.6, 1393.6, -116.4 }, shade = 1.35, layer = "detail", collide = false },
		{ name = "gatehouse roof hip 3", shape = { 1393.6, 116.4, 1273.6, -3.6, 1266.4, 3.6, 1386.4, 123.6 }, shade = 1.35, layer = "detail", collide = false },
		{ name = "gatehouse roof hip 4", shape = { 1093.6, 123.6, 1213.6, 3.6, 1206.4, -3.6, 1086.4, 116.4 }, shade = 1.35, layer = "detail", collide = false },
		{ name = "gate jamb n", shape = { 942, -270.1, 1249.6, -358.3, 1249.6, -150, 942, -150 }, shade = 0.85, color = { 0.78, 0.62, 0.46 } },
		{ name = "gate jamb s", shape = { 942, 270.1, 1249.6, 358.3, 1249.6, 150, 942, 150 }, shade = 0.85, color = { 0.78, 0.62, 0.46 } },
		{ name = "inner hall 1", shape = { -500, 0, -600, 0, -579.6, -155.3, -483, -129.4 }, shade = 0.85, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 6, x = -515.55, y = -67.87 },
		} },
		{ name = "inner hall 2", shape = { -483, -129.4, -579.6, -155.3, -519.6, -300, -433, -250 }, shade = 0.85, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 6, x = -480.42, y = -199 },
		} },
		{ name = "inner hall 3", shape = { -433, -250, -519.6, -300, -424.3, -424.3, -353.6, -353.6 }, shade = 0.85, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 6, x = -412.54, y = -316.56 },
		} },
		{ name = "inner hall 4", shape = { -353.6, -353.6, -424.3, -424.3, -300, -519.6, -250, -433 }, shade = 0.85, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 6, x = -316.56, y = -412.54 },
		} },
		{ name = "inner hall 5", shape = { -250, -433, -300, -519.6, -155.3, -579.6, -129.4, -483 }, shade = 0.85, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 6, x = -199, y = -480.42 },
		} },
		{ name = "inner hall 6", shape = { -129.4, -483, -155.3, -579.6, 0, -600, 0, -500 }, shade = 0.85, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 6, x = -67.87, y = -515.55 },
		} },
		{ name = "inner hall 7", shape = { 0, -500, 0, -600, 155.3, -579.6, 129.4, -483 }, shade = 0.85, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 6, x = 67.87, y = -515.55 },
		} },
		{ name = "inner hall 8", shape = { 129.4, -483, 155.3, -579.6, 300, -519.6, 250, -433 }, shade = 0.85, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 6, x = 199, y = -480.42 },
		} },
		{ name = "inner hall 9", shape = { 250, -433, 300, -519.6, 424.3, -424.3, 353.6, -353.6 }, shade = 0.85, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 6, x = 316.56, y = -412.54 },
		} },
		{ name = "inner hall 10", shape = { 353.6, -353.6, 424.3, -424.3, 519.6, -300, 433, -250 }, shade = 0.85, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 6, x = 412.54, y = -316.56 },
		} },
		{ name = "inner hall 11", shape = { 433, -250, 519.6, -300, 579.6, -155.3, 483, -129.4 }, shade = 0.85, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 6, x = 480.42, y = -199 },
		} },
		{ name = "inner hall 14", shape = { 483, 129.4, 579.6, 155.3, 519.6, 300, 433, 250 }, shade = 0.85, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 6, x = 480.42, y = 199 },
		} },
		{ name = "inner hall 15", shape = { 433, 250, 519.6, 300, 424.3, 424.3, 353.6, 353.6 }, shade = 0.85, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 6, x = 412.54, y = 316.56 },
		} },
		{ name = "inner hall 16", shape = { 353.6, 353.6, 424.3, 424.3, 300, 519.6, 250, 433 }, shade = 0.85, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 6, x = 316.56, y = 412.54 },
		} },
		{ name = "inner hall 17", shape = { 250, 433, 300, 519.6, 155.3, 579.6, 129.4, 483 }, shade = 0.85, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 6, x = 199, y = 480.42 },
		} },
		{ name = "inner hall 18", shape = { 129.4, 483, 155.3, 579.6, 0, 600, 0, 500 }, shade = 0.85, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 6, x = 67.87, y = 515.55 },
		} },
		{ name = "inner hall 19", shape = { 0, 500, 0, 600, -155.3, 579.6, -129.4, 483 }, shade = 0.85, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 6, x = -67.87, y = 515.55 },
		} },
		{ name = "inner hall 20", shape = { -129.4, 483, -155.3, 579.6, -300, 519.6, -250, 433 }, shade = 0.85, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 6, x = -199, y = 480.42 },
		} },
		{ name = "inner hall 21", shape = { -250, 433, -300, 519.6, -424.3, 424.3, -353.6, 353.6 }, shade = 0.85, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 6, x = -316.56, y = 412.54 },
		} },
		{ name = "inner hall 22", shape = { -353.6, 353.6, -424.3, 424.3, -519.6, 300, -433, 250 }, shade = 0.85, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 6, x = -412.54, y = 316.56 },
		} },
		{ name = "inner hall 23", shape = { -433, 250, -519.6, 300, -579.6, 155.3, -483, 129.4 }, shade = 0.85, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 6, x = -480.42, y = 199 },
		} },
		{ name = "inner hall 24", shape = { -483, 129.4, -579.6, 155.3, -600, 0, -500, 0 }, shade = 0.85, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 6, x = -515.55, y = 67.87 },
		} },
		{ name = "ancestral hall eaves", shape = { -210.4, -140, 50.4, -140, 108, -158, 90, -100.4, 90, 100.4, 108, 158, 50.4, 140, -210.4, 140, -268, 158, -250, 100.4, -250, -100.4, -268, -158 }, shade = 1, tint = { 0.14, 0.12, -0.12 }, lights = {
			{ kind = "window", size = 6, x = -200, y = -110 },
			{ kind = "window", size = 6, x = -140, y = -110 },
			{ kind = "window", size = 6, x = -80, y = -110 },
			{ kind = "window", size = 6, x = -20, y = -110 },
			{ kind = "window", size = 6, x = 40, y = -110 },
			{ kind = "window", size = 6, x = -200, y = 110 },
			{ kind = "window", size = 6, x = -140, y = 110 },
			{ kind = "window", size = 6, x = -80, y = 110 },
			{ kind = "window", size = 6, x = -20, y = 110 },
			{ kind = "window", size = 6, x = 40, y = 110 },
		} },
		{ name = "ancestral hall upper eaves", shape = { -170.7, -86.8, 10.7, -86.8, 56.8, -101.2, 42.4, -55.1, 42.4, 55.1, 56.8, 101.2, 10.7, 86.8, -170.7, 86.8, -216.8, 101.2, -202.4, 55.1, -202.4, -55.1, -216.8, -101.2 }, shade = 1.12, tint = { 0.14, 0.12, -0.12 } },
		{ name = "ancestral hall ridge", shape = { -115.6, -6.1, -44.4, -6.1, -44.4, 6.1, -115.6, 6.1 }, shade = 1.35, layer = "detail", collide = false },
		{ name = "ancestral hall hip 1", shape = { -205, -84.2, -118.2, 2.6, -113, -2.6, -199.8, -89.4 }, shade = 1.35, layer = "detail", collide = false },
		{ name = "ancestral hall hip 2", shape = { 39.8, -89.4, -47, -2.6, -41.8, 2.6, 45, -84.2 }, shade = 1.35, layer = "detail", collide = false },
		{ name = "ancestral hall hip 3", shape = { 45, 84.2, -41.8, -2.6, -47, 2.6, 39.8, 89.4 }, shade = 1.35, layer = "detail", collide = false },
		{ name = "ancestral hall hip 4", shape = { -199.8, 89.4, -113, 2.6, -118.2, -2.6, -205, 84.2 }, shade = 1.35, layer = "detail", collide = false },
		{ name = "court well", shape = { 274, 0, 269.4, 17, 257, 29.4, 240, 34, 223, 29.4, 210.6, 17, 206, 0, 210.6, -17, 223, -29.4, 240, -34, 257, -29.4, 269.4, -17 }, shade = 0.8, color = { 0.45, 0.78, 0.86 }, lights = {
			{ color = { 1, 0.8, 0.4 }, kind = "nav", size = 4, x = 240, y = 0 },
		} },
	},
}
