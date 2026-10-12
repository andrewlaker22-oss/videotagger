# STORY — full script for WATCHED (prototype)

Protagonist: **MARA**. Tone: quiet psychological dread, stalker theme.
Notation: `(beat: id)` = story beat; `[CHOICE — 6s]` = timed choice with timeout;
`→` = where a pick leads; `★` = default pick on timeout; `⚑` = sets a flag;
`🔔` = "will remember that" toast. `(if has_knife)` = conditional line.

---

## 1. INTRO — the hallway, 11:47 PM `(beat: intro)`

> 11:47 PM. The hallway smells like rain and old cigarettes.
>
> Your door is open. Just a crack. You never leave it unlocked.
>
> **MARA:** I locked it. I always lock it.

**[CHOICE — 6 s]**
- Push the door open ★ → `entry`
- Call out: “Hello…?” ⚑ `called_out` 🔔 “Someone heard that.” → `entry_callout`
- Call the police ⚑ `called_police` 🔔 “Mara will remember that.” → `entry_police`

### `entry_callout`
> **MARA:** Hello…? Is someone in there?
>
> Silence. Not even the fridge hum. The apartment never goes this quiet.
→ `entry`

### `entry_police`
> You dial. It rings twice — then the line goes dead. Not a disconnect. Cut.
>
> **MARA:** What— no. No no no.
>
> Behind the door, something creaks. The door swings open on its own.
→ `entry`

### `entry` — objective: *Look around the living room.*
> You step inside. The air is wrong — too still, like the apartment is holding its breath.
>
> **MARA:** Okay. Okay. Probably the lock's just old. Probably.

---

## 2. THE NOTE — fridge, kitchen `(beat: note)`

> A note on the fridge. Block letters. The handwriting isn't yours.
>
> **NOTE:** “I LIKE YOUR NEW PLACE.”
>
> **MARA:** That's… that's not funny. Who—
>
> Your phone starts ringing. UNKNOWN NUMBER. *(sfx: phone_ring)*

**[CHOICE — 5 s]** — objective: *Answer the phone… or don't.*
- Answer it ⚑ `answered_phone` 🔔 “He will remember that.” → `phone_answer`
- Let it ring out ★ ⚑ `ignored_phone` 🔔 “He will remember that.” → `phone_ignore`

### `phone_answer` — objective: *Check the bedroom.*
> **MARA:** Hello? Who is this?
>
> Breathing. Slow. Close.
>
> **UNKNOWN:** “I can see you.”
>
> Click. Dial tone.
>
> **MARA:** That was— that was inside the apartment. That sounded inside.

### `phone_ignore` — objective: *Check the bedroom.*
> It rings. And rings. And rings. Then stops.
>
> **MARA:** Wrong number. Just a wrong number. That's all.
>
> You don't believe you.

---

## 3. BEDROOM

### The photo `(beat: photo)` — nightstand
> A framed photo on the nightstand. You, asleep. Taken last night — from the foot of the bed.
>
> **MARA:** That's my bedroom. That's last night.
>
> **MARA:** I live alone.

### The closet `(beat: closet)` — wardrobe
> The closet. Your coats, your boots. Nothing else.
>
> **MARA:** Nothing. There's nothing in there.
>
> **MARA:** Why did I check the closet first?

---

## 4. BATHROOM — the mirror `(beat: mirror)` — objective: *Check the kitchen.*

> The mirror is fogged. The shower hasn't run in hours.
>
> Words, dragged through the steam:
>
> **MIRROR:** “TURN AROUND”
>
> **MARA:** …
>
> Nothing. Nobody. Just you, breathing too fast.

---

## 5. KITCHEN — the knife `(beat: knife)`

> Your good kitchen knife. It's not in the block. It's lying in the middle of the
> counter — like it was placed there. Displayed.

**[CHOICE — 6 s]**
- Take the knife ⚑ `has_knife` 🔔 “Mara will remember that.” → `blackout`
- Leave it ★ → `blackout`

---

## 6. BLACKOUT `(beat: blackout)` — objective: *Survive.*

*(All lights die. Front-door handle rattles — sfx: door_rattle.)*

> The lights die.
>
> *(if has_knife)* The knife is heavier than you expected.
>
> Silence. Then — the front door handle rattles.
>
> **MARA:** No no no—

→ `find_breaker` — objective: *Find the breaker box in the basement.*

---

## 6b. BREAKER `(beat: breaker)` — the basement breaker box

> The breaker box hangs open. Every switch is thrown to OFF.
>
> **MARA:** Come on. Come on—
>
> You throw the main breaker. The lights gasp back — one heartbeat, two — *(sfx: power_stutter)*
>
> Then they die again. The dark feels closer now.

**[CHOICE — 5 s]** — objective: *Survive.*
- Run for the fire escape → `end_escape` → **ENDING: ESCAPE**
- Hide in the closet ★ → `end_hide` → **ENDING: HIDE**
- Confront them at the door → `end_confront` → **ENDING: CONFRONT**

---

## ENDINGS

### ESCAPE — “WATCHED” / *You got out. (Or did you?)*
> You hit the fire escape and don't look back until the street.
>
> Halfway down the block, you stop. Across the street, under a dead streetlight —
> a figure. Watching.
>
> **MARA:** You never see their face.

### HIDE — “SEEN” / *They were closer than you thought.*
> You fold yourself into the closet and pull the coats around you like armor.
>
> Something digs into your knee. A phone. Not yours.
>
> The gallery is full. Hundreds of photos. All of you. Sleeping. Cooking. Reading.
>
> The newest one was taken ten seconds ago. In this closet.

### CONFRONT — “FOUND” / *You never saw their face.*
> You throw the front door open—
>
> The hallway is empty.
>
> *(if has_knife)* Your hand tightens on the knife. It doesn't matter. It's already too late.
>
> A breath, warm, against the back of your neck.
>
> **UNKNOWN:** “Turn around.”

---

*Cut to black. “Press R to play again.”*
