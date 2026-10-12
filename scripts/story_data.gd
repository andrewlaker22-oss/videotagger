class_name StoryData
extends RefCounted
## Data-driven story definition for WATCHED.
##
## Everything the narrative does lives here — beats, dialogue lines, timed
## choices, flags, effects and endings. To extend the story, edit the
## dictionaries below (or in get_beats() / get_endings()); no script changes
## are needed. See docs/STORY.md for the full script and docs/ARCHITECTURE.md
## for the schema.
##
## Beat schema:
##   "objective": String        - HUD objective text set when the beat starts (optional).
##   "effects": Array           - one-shot world effects at beat start (optional).
##                                Each entry is a String effect name ("open_door",
##                                "blackout", "power_stutter", "phone_ring") OR a
##                                Dictionary for the "text" effect:
##                                  {"effect": "text", "from": <thread_id>,
##                                   "text": <message>}            - incoming text
##                                  {"effect": "text", "from": "mara",
##                                   "to": <thread_id>, "text": <message>}
##                                                             - Mara auto-sends
##                                Thread ids come from get_phone_threads().
##   "lines": Array[Dictionary] - dialogue shown in order. Each line:
##       "who":  speaker tag ("" = narration, no speaker label)
##       "text": the line itself
##       "if":     only show if this flag is set (optional)
##       "if_not": only show if this flag is NOT set (optional)
##       "sfx":    play this named sfx when the line appears (optional)
##   "choices": Array[Dictionary] - timed Telltale-style choice. Each choice:
##       "text":    button label
##       "next":    beat id to play when picked
##       "set":     Dictionary of flags to set, e.g. {"has_knife": true} (optional)
##       "toast":   "\"X will remember that\""-style toast (optional, shown when picked)
##       "default": true on exactly one choice per beat (auto-picked on timeout)
##   "timer": float              - choice countdown in seconds (default 5.0).
##   "next": String              - beat id to play after lines when there are no
##                                choices ("" or absent = return to exploration).
##   "ending": String            - ending id; after lines, show the ending screen.
##
## Rules the GameManager relies on:
##   - Every beat id referenced by "next" or a choice MUST exist in get_beats().
##   - A beat has lines, then optionally ONE of: choices / ending / next.
##   - Exactly one choice per choice-beat must be marked "default".

static func get_start_beat_id() -> String:
	return "intro"


## Maps Interactable.interact_id -> beat id. Interactables are placed by
## apartment_builder.gd; their story meaning is defined here.
static func get_trigger_beats() -> Dictionary:
	return {
		"fridge_note": "note",
		"bedroom_photo": "photo",
		"bedroom_closet": "closet",
		"bathroom_mirror": "mirror",
		"kitchen_knife": "knife",
		"breaker_box": "breaker",
	}


## Phone threads for the iPhone-style message UI (phone_ui.gd).
##
## Thread schema:
##   "name":     display name in the thread list
##   "number":   subtitle for unknown contacts ("" for saved contacts)
##   "messages": starter messages, each {"from": "them"/"me", "text", "time"}
## Beat-triggered texts arrive via the "text" beat effect (see schema above);
## they are timestamped with the phone's clock when delivered.
static func get_phone_threads() -> Dictionary:
	return {
		"mom": {
			"name": "Mom",
			"number": "",
			"messages": [
				{"from": "them", "text": "did you get home safe??", "time": "11:02 PM"},
				{"from": "me", "text": "just walked in! all good", "time": "11:05 PM"},
				{"from": "them", "text": "ok good ❤ don't forget we're doing groceries sunday", "time": "11:06 PM"},
			],
		},
		"jess": {
			"name": "Jess",
			"number": "",
			"messages": [
				{"from": "them", "text": "u up", "time": "10:48 PM"},
				{"from": "them", "text": "u HAVE to show me the new place this weekend", "time": "10:49 PM"},
				{"from": "me", "text": "lol it's literally boxes and an air mattress rn", "time": "10:52 PM"},
			],
		},
		"unknown": {
			"name": "Unknown",
			"number": "No Caller ID",
			"messages": [],
		},
	}


static func get_beats() -> Dictionary:
	return {
		# ------------------------------------------------------------------
		# 1. INTRO — at the apartment door, hallway.
		# ------------------------------------------------------------------
		"intro": {
			"objective": "Get inside.",
			"effects": [
				{"effect": "text", "from": "unknown", "text": "i can see your lights on"},
			],
			"lines": [
				{"who": "", "text": "11:47 PM. The hallway smells like rain and old cigarettes."},
				{"who": "", "text": "Your door is open. Just a crack. You never leave it unlocked."},
				{"who": "MARA", "text": "I locked it. I always lock it."},
			],
			"timer": 6.0,
			"choices": [
				{"text": "Push the door open", "next": "entry", "default": true},
				{"text": "Call out: “Hello…?”", "next": "entry_callout",
					"set": {"called_out": true}, "toast": "Someone heard that."},
				{"text": "Call the police", "next": "entry_police",
					"set": {"called_police": true}, "toast": "Mara will remember that."},
			],
		},
		"entry_callout": {
			"lines": [
				{"who": "MARA", "text": "Hello…? Is someone in there?"},
				{"who": "", "text": "Silence. Not even the fridge hum. The apartment never goes this quiet."},
			],
			"next": "entry",
		},
		"entry_police": {
			"effects": ["open_door"],
			"lines": [
				{"who": "", "text": "You dial. It rings twice — then the line goes dead. Not a disconnect. Cut."},
				{"who": "MARA", "text": "What— no. No no no."},
				{"who": "", "text": "Behind the door, something creaks. The door swings open on its own."},
			],
			"next": "entry",
		},
		"entry": {
			# NOTE: Mara texting Mom ("home safe! love you") is NOT auto-sent
			# here anymore — it's a manual quick-reply tap in the Mom thread,
			# gated by the phone checklist ("Text Mom you're home").
			"effects": ["open_door",
				{"effect": "text", "from": "jess", "text": "how's the first night in the new place??"},
			],
			"objective": "Look around the living room.",
			"lines": [
				{"who": "", "text": "You step inside. The air is wrong — too still, like the apartment is holding its breath."},
				{"who": "MARA", "text": "Okay. Okay. Probably the lock's just old. Probably."},
			],
		},
		# ------------------------------------------------------------------
		# 2. LIVING ROOM / KITCHEN — the note on the fridge.
		# ------------------------------------------------------------------
		"note": {
			"lines": [
				{"who": "", "text": "A note on the fridge. Block letters. The handwriting isn't yours."},
				{"who": "NOTE", "text": "“I LIKE YOUR NEW PLACE.”"},
				{"who": "MARA", "text": "That's… that's not funny. Who—"},
				{"who": "", "text": "Your phone starts ringing. UNKNOWN NUMBER.", "sfx": "phone_ring"},
			],
			"objective": "Answer the phone… or don't.",
			"timer": 5.0,
			"choices": [
				{"text": "Answer it", "next": "phone_answer",
					"set": {"answered_phone": true}, "toast": "He will remember that."},
				{"text": "Let it ring out", "next": "phone_ignore", "default": true,
					"set": {"ignored_phone": true}, "toast": "He will remember that."},
			],
		},
		"phone_answer": {
			"objective": "Check the bedroom.",
			"effects": [
				{"effect": "text", "from": "unknown", "text": "you sound scared"},
			],
			"lines": [
				{"who": "MARA", "text": "Hello? Who is this?"},
				{"who": "", "text": "Breathing. Slow. Close."},
				{"who": "UNKNOWN", "text": "“I can see you.”"},
				{"who": "", "text": "Click. Dial tone."},
				{"who": "MARA", "text": "That was— that was inside the apartment. That sounded inside."},
			],
		},
		"phone_ignore": {
			"objective": "Check the bedroom.",
			"effects": [
				{"effect": "text", "from": "unknown", "text": "pick up next time"},
			],
			"lines": [
				{"who": "", "text": "It rings. And rings. And rings. Then stops."},
				{"who": "MARA", "text": "Wrong number. Just a wrong number. That's all."},
				{"who": "", "text": "You don't believe you."},
			],
		},
		# ------------------------------------------------------------------
		# 3. BEDROOM — the photo, the closet.
		# ------------------------------------------------------------------
		"photo": {
			"effects": [
				{"effect": "text", "from": "unknown", "text": "you look so peaceful when you sleep"},
			],
			"lines": [
				{"who": "", "text": "A framed photo on the nightstand. You, asleep. Taken last night — from the foot of the bed."},
				{"who": "MARA", "text": "That's my bedroom. That's last night."},
				{"who": "MARA", "text": "I live alone."},
			],
		},
		"closet": {
			"lines": [
				{"who": "", "text": "The closet. Your coats, your boots. Nothing else."},
				{"who": "MARA", "text": "Nothing. There's nothing in there."},
				{"who": "MARA", "text": "Why did I check the closet first?"},
			],
		},
		# ------------------------------------------------------------------
		# 4. BATHROOM — the mirror.
		# ------------------------------------------------------------------
		"mirror": {
			"objective": "Check the kitchen.",
			"effects": [
				{"effect": "text", "from": "unknown", "text": "turn around"},
			],
			"lines": [
				{"who": "", "text": "The mirror is fogged. The shower hasn't run in hours."},
				{"who": "", "text": "Words, dragged through the steam:"},
				{"who": "MIRROR", "text": "“TURN AROUND”"},
				{"who": "MARA", "text": "…"},
				{"who": "", "text": "Nothing. Nobody. Just you, breathing too fast."},
			],
		},
		# ------------------------------------------------------------------
		# 5. KITCHEN — the knife, then the blackout.
		# ------------------------------------------------------------------
		"knife": {
			"effects": [
				{"effect": "text", "from": "unknown", "text": "nice knife"},
			],
			"lines": [
				{"who": "", "text": "Your good kitchen knife. It's not in the block. It's lying in the middle of the counter — like it was placed there. Displayed."},
			],
			"timer": 6.0,
			"choices": [
				{"text": "Take the knife", "next": "blackout",
					"set": {"has_knife": true}, "toast": "Mara will remember that."},
				{"text": "Leave it", "next": "blackout", "default": true},
			],
		},
		"blackout": {
			"effects": ["blackout",
				{"effect": "text", "from": "unknown", "text": "dark in there, isn't it"},
				{"effect": "text", "from": "mara", "to": "mom", "text": "hey if i don't text you in an hour call me"},
			],
			"objective": "Survive.",
			"lines": [
				{"who": "", "text": "The lights die."},
				{"who": "", "text": "The knife is heavier than you expected.", "if": "has_knife"},
				{"who": "", "text": "Silence. Then — the front door handle rattles.", "sfx": "door_rattle"},
				{"who": "MARA", "text": "No no no—"},
			],
			"next": "find_breaker",
		},
		# ------------------------------------------------------------------
		# 5b. BREAKER — the basement. Objective-only beat: sends the player
		# down to the breaker box; the "breaker_box" interactable (which the
		# blackout deliberately leaves enabled) triggers the "breaker" beat.
		# ------------------------------------------------------------------
		"find_breaker": {
			"objective": "Find the breaker box in the basement.",
		},
		"breaker": {
			"objective": "Survive.",
			"effects": ["power_stutter",
				{"effect": "text", "from": "unknown", "text": "nice try"},
			],
			"lines": [
				{"who": "", "text": "The breaker box hangs open. Every switch is thrown to OFF."},
				{"who": "MARA", "text": "Come on. Come on—"},
				{"who": "", "text": "You throw the main breaker. The lights gasp back — one heartbeat, two —", "sfx": "power_stutter"},
				{"who": "", "text": "Then they die again. The dark feels closer now."},
			],
			"timer": 5.0,
			"choices": [
				{"text": "Run for the fire escape", "next": "end_escape"},
				{"text": "Hide in the closet", "next": "end_hide", "default": true},
				{"text": "Confront them at the door", "next": "end_confront"},
			],
		},
		# ------------------------------------------------------------------
		# 6. ENDINGS.
		# ------------------------------------------------------------------
		"end_escape": {
			"ending": "ESCAPE",
			"lines": [
				{"who": "", "text": "You hit the fire escape and don't look back until the street."},
				{"who": "", "text": "Halfway down the block, you stop. Across the street, under a dead streetlight — a figure. Watching."},
				{"who": "MARA", "text": "You never see their face."},
			],
		},
		"end_hide": {
			"ending": "HIDE",
			"lines": [
				{"who": "", "text": "You fold yourself into the closet and pull the coats around you like armor."},
				{"who": "", "text": "Something digs into your knee. A phone. Not yours."},
				{"who": "", "text": "The gallery is full. Hundreds of photos. All of you. Sleeping. Cooking. Reading."},
				{"who": "", "text": "The newest one was taken ten seconds ago. In this closet."},
			],
		},
		"end_confront": {
			"ending": "CONFRONT",
			"lines": [
				{"who": "", "text": "You throw the front door open—"},
				{"who": "", "text": "The hallway is empty."},
				{"who": "", "text": "Your hand tightens on the knife. It doesn't matter. It's already too late.", "if": "has_knife"},
				{"who": "", "text": "A breath, warm, against the back of your neck."},
				{"who": "UNKNOWN", "text": "“Turn around.”"},
			],
		},
	}


static func get_endings() -> Dictionary:
	return {
		"ESCAPE": {
			"title": "WATCHED",
			"subtitle": "You got out. (Or did you?)",
		},
		"HIDE": {
			"title": "SEEN",
			"subtitle": "They were closer than you thought.",
		},
		"CONFRONT": {
			"title": "FOUND",
			"subtitle": "You never saw their face.",
		},
	}
