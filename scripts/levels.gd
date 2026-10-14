extends RefCounted
## The VR missions, easiest first. Each one introduces something new.
##
## "map": one character = one 48px tile; every row the same width (max 24x12).
##   #        wall                    .        floor
##   P        player start (one)      G        goal (one)
##   > < ^ v  wall camera looking that way, sweeping back and forth
##   @        turret on a pillar, spinning a full circle
##   - |      laser tripwire tiles; a run of them becomes one beam,
##            "-" beams run left-right, "|" beams run top-bottom
##   K        keycard                 D        vault door, opens once K is taken
##
## Optional keys:
##   "soldiers": [[x, y], ...] per soldier. Patrol waypoints in tiles, looping
##               back to the first. Legs must be straight lines over floor.
##   "drones":   [[x, y], ...] per drone. Flight waypoints that can cross walls.
##   "lasers":   {"on": s, "off": s, "stagger": s}. Beam timing; each beam's
##               cycle starts `stagger` seconds after the previous one.
##   "turret":   {"speed": rad/s, "range": tiles}
##
## tests/game_test.gd checks every map is well-formed, finishable, has valid
## patrol routes, and doesn't spot the player at the start.

const LEVELS := [
	{
		"name": "VR-01  FIRST CONTACT",
		"brief": "Reach the GOAL. Stay out of the camera's cone.",
		"map": [
			"############v###########",
			"#......#........#......#",
			"#......#........#......#",
			"#..P............#...G..#",
			"#......#........#......#",
			"#......#........#......#",
			"#......#........#......#",
			"#......#........#......#",
			"#......#........#......#",
			"#......#...............#",
			"#......#........#......#",
			"########################",
		],
	},
	{
		"name": "VR-02  HIDE IN PLAIN SIGHT",
		"brief": "Hold SPACE to hide in the box. A still box is slow to spot.",
		"map": [
			"#####v#####v#####v######",
			"#P.....................#",
			"#......................#",
			"#.....................G#",
			"########################",
		],
	},
	{
		"name": "VR-03  PILLARS",
		"brief": "Walls and pillars block a camera's view. Move through the shadows.",
		"map": [
			"######v#########v#######",
			"#.....................G#",
			"#......................#",
			"#..##....##.....##.....#",
			"#..##....##.....##.....#",
			"#......................#",
			"#......................#",
			"#.....##.....##....##..#",
			"#.....##.....##....##..#",
			"#......................#",
			"#P.....................#",
			"###########^############",
		],
	},
	{
		"name": "VR-04  TRIPWIRE",
		"brief": "Lasers cycle on and off. Touch a live beam and the alarm trips.",
		"lasers": {"on": 1.6, "off": 1.6, "stagger": 0.5},
		"map": [
			"########################",
			"#P....|......|.........#",
			"#.....|......|.........#",
			"####################--##",
			"#.........|.....|......#",
			"#.........|.....|......#",
			"#--#####################",
			"#......|....|....|....G#",
			"#......|....|....|.....#",
			"########################",
		],
	},
	{
		"name": "VR-05  PATROL",
		"brief": "Guards walk set routes and stop to look around. Never bump into one.",
		"soldiers": [
			[[3, 5], [20, 5]],
			[[12, 1], [12, 9]],
		],
		"map": [
			"########################",
			"#......................#",
			"#.P....................#",
			"#......##.....##.......#",
			"#......##.....##.......#",
			"#......................#",
			"#......................#",
			"#..##.....##.....##....#",
			"#..##.....##.....##....#",
			"#.....................G#",
			"########################",
		],
	},
	{
		"name": "VR-06  EYE IN THE SKY",
		"brief": "Drones fly over walls and see everything in their spotlight.",
		"drones": [
			[[3, 2], [14, 2], [14, 8], [3, 8]],
			[[20, 1], [20, 8]],
		],
		"map": [
			"########################",
			"#P.......#.............#",
			"#......................#",
			"#..####..#..#######....#",
			"#..#.....#........#....#",
			"#..#..#######.....#....#",
			"#..#........#.....#..G.#",
			"#..######...#..####....#",
			"#......................#",
			"########################",
		],
	},
	{
		"name": "VR-07  KEYCARD",
		"brief": "The exit is locked. Take the keycard from the vault.",
		"soldiers": [
			[[9, 2], [16, 2], [16, 8], [9, 8]],
		],
		"map": [
			"########################",
			"#P.....#..........#....#",
			"#......#..........#....#",
			"#......#..######..#..G.#",
			"#.........#....#..#....#",
			"#......#..#.K..#..D....#",
			"#......#..#....#..#....#",
			"#......#..###..#..#....#",
			"#......>..........#....#",
			"########################",
		],
	},
	{
		"name": "VR-08  TURRET",
		"brief": "The turret never stops turning. Move behind its back.",
		"turret": {"speed": 0.9, "range": 6.0},
		"lasers": {"on": 1.2, "off": 2.0, "stagger": 0.8},
		"map": [
			"########################",
			"#P..#..............#...#",
			"#...#..............#...#",
			"#...|...##....##...|...#",
			"#...#..............#...#",
			"#...#......@.......#...#",
			"#...#..............#...#",
			"#...#...##....##...#...#",
			"#...|..............|...#",
			"#...#..............#..G#",
			"########################",
		],
	},
	{
		"name": "VR-09  LABYRINTH",
		"brief": "Cameras, a guard and a drone in a maze. Plan your route.",
		"soldiers": [
			[[5, 8], [14, 8]],
		],
		"drones": [
			[[17, 1], [22, 1], [22, 8], [17, 8]],
		],
		"map": [
			"#########v##############",
			"#P..#..........#.......#",
			"#...#..........#.......#",
			"#...#...####...#..###..#",
			"#.......#..#...#..#G#..#",
			"#...#...#..#......#.#..#",
			"#...#...#..#...#.......<",
			"#...#...####...#.......#",
			"#...#..........#.......#",
			"#...#####..#####.......#",
			"#.....................<#",
			"########################",
		],
	},
	{
		"name": "VR-10  FINAL EXAM",
		"brief": "Everything at once. Keycard first, then the vault. Good luck.",
		"turret": {"speed": 0.7, "range": 4.5},
		"lasers": {"on": 1.4, "off": 1.8, "stagger": 0.6},
		"soldiers": [
			[[15, 5], [22, 5], [22, 10], [15, 10]],
		],
		"drones": [
			[[6, 2], [12, 2], [12, 9], [6, 9]],
		],
		"map": [
			"##########v#############",
			"#P..#.........#........#",
			"#...#.........|..K.....#",
			"#...|...##....#........#",
			"#...#...##....###--#####",
			"#...#.........#........#",
			"#...#....@....#........#",
			"#...#.........#..#####.#",
			"#.............#..#.G.#.#",
			"#...#.........#..##D##.#",
			"#...#.........#........#",
			"########################",
		],
	},
]
