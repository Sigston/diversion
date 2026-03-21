# TADS 3 / adv3Lite Reference Notes

Compiled from official documentation and community sources. For use as a
design reference when building the Diversion engine.

---

## Table of Contents

1. [verify/check/action/report Phases](#1-verifycheckactionreport-phases)
2. [Action Types](#2-action-types)
3. [Object Properties](#3-object-properties)
4. [World Model / Containment Tree](#4-world-model--containment-tree)
5. [Parser / Vocabulary](#5-parser--vocabulary)
6. [Scope Rules](#6-scope-rules)
7. [adv3Lite vs adv3 Differences](#7-adv3lite-vs-adv3-differences)
8. [Event / Notification System](#8-event--notification-system)
9. [Implied Actions](#9-implied-actions)
10. [Doers](#10-doers)
11. [Other Distinctive Patterns](#11-other-distinctive-patterns)

---

## 1. verify/check/action/report Phases

adv3Lite implements a six-stage action processing pipeline. The stages execute
in this order:

1. **Verify** -- Parser disambiguation and logical validation
2. **Preconditions** -- Required state conditions with optional implicit actions
3. **Check** -- Non-obvious blocking conditions
4. **Action** -- State changes and core mechanics
5. **Report** -- Grouped summarisation of multi-object effects
6. **Remap** -- Object substitution in the same role

### 1.1 Verify Phase

**Purpose:** Serves dual purposes: (a) helping the parser select the most
appropriate object when ambiguity exists, and (b) preventing obviously
illogical actions with an explanation.

**Core principle:** "Logical" means what the *player* thinks it means -- not
the game author, not the player character, not an omniscient narrator. The
question is always "would the player think this is an obviously stupid thing
to try?"

**Execution model:** Verify runs *twice* during command execution:
1. During parsing -- the parser scores all matching objects; highest-scored
   object is selected.
2. During action validation -- the selected object's verify re-runs; if it
   fails, the failure message displays.

**Critical constraints:**
- Verify routines must NEVER modify game state.
- They must NEVER display text via `say()` or direct output.
- They should contain only verify result macros and conditional logic.
- Multiple verify results on one object: the *worst* (most illogical) result
  prevails.
- You cannot override a superclass objection to make something more logical.

#### 1.1.1 Verify Result Macros (Ranked Most to Least Logical)

| Macro | Rank | Blocks? | Use Case |
|-------|------|---------|----------|
| `logical` | 100 | No | Default state. Rarely needs explicit use. |
| `logicalRank(n)` | n | No | Fine-tune preference. 150 = especially good fit. |
| `dangerous` | 90 | No* | Allows explicit commands but prevents implicit/default selection. E.g. opening an airlock. |
| `illogicalAlready(msg)` | 40 | Yes | Action already accomplished. "The door is already open." |
| `illogicalNow(msg)` | 40 | Yes | Currently impossible due to state. "The raft is deflated." |
| `implausible(msg)` | 35 | Yes | Seems odd but not absurd. |
| `illogical(msg)` | 30 | Yes | Illogical at ALL times, inherent to the object. "You can't take a building." |
| `nonObvious` | 30 | No* | Allows explicit commands but prevents implicit/default. For hidden puzzle solutions. |
| `illogicalSelf(msg)` | 20 | Yes | Prevents self-reference. "PUT BOX IN BOX." |
| `inaccessible(msg)` | 10 | Yes | Object is out of reach or inaccessible to senses. |

*`dangerous` and `nonObvious` allow the action for explicit commands but
block it as an implicit action or default disambiguation choice.

**Note on adv3Lite specifically:** `illogicalAlready` doesn't behave much
differently from `illogicalNow` in adv3Lite, but it's provided for
familiarity with adv3 conventions and is given a slightly higher logical
rank than `illogicalNow`.

#### 1.1.2 logicalRank Conventional Values

| Rank | Meaning |
|------|---------|
| 150 | Especially good fit (e.g. book for READ) |
| 140 | Entirely appropriate but not uniquely ideal |
| 100 | Default ranking; good candidate |
| 80 | Slightly less perfect; unmet preconditions |
| 70 | Less favourable; suggests player likely means something else |
| 60 | Similar to 70, slightly worse |
| 50 | Logical but improbable |

#### 1.1.3 How Disambiguation Uses Verify

When multiple objects match a noun phrase:
1. Parser calls verify on all candidates.
2. Objects with higher verify scores are preferred.
3. If all matching objects have identical results, verify doesn't help --
   the parser asks for clarification.
4. Objects with no verify results at all are assumed logical (score 100).

For TIActions (two-object commands), use `gVerifyDobj`/`gVerifyIobj`
instead of `gDobj`/`gIobj` in verify methods, because the other object
might not be resolved yet. These macros safely return actual objects or
tentative candidates from `gTentativeDobj`/`gTentativeIobj`.

#### 1.1.4 Failed Actions and Turn Counting

By default, actions failing at verify still count as turns (incrementing
counters, executing daemons). Override `Action.failedActionCountsAsTurn`
to change this.

### 1.2 Preconditions Phase

Preconditions encapsulate frequently needed state requirements and can
trigger implicit actions to satisfy them.

**Built-in PreCondition objects:**

| PreCondition | Requirement | Implicit Action |
|--------------|-------------|-----------------|
| `objHeld` | Object must be carried | Take |
| `objCarried` | Object must be held (variant for DROP) | TakeFrom if in container with `canDropContents = true` |
| `objClosed` | Object must be closed | Close |
| `objNotWorn` | Object must not be worn | Doff |
| `objVisible` | Object must be visible with adequate light | None (check only) |
| `objAudible` | Object must be audible | None (check only) |
| `objSmellable` | Object must be smellable | None (check only) |
| `objDetached` | Object must be detached | Detach |
| `objUnlocked` | Object must be unlocked | Unlock (only if `autoUnlock = true`) |
| `containerOpen` | If container, must be open | Open |
| `touchObj` | Actor can physically reach object | Opens closed transparent containers |
| `actorInStagingLocation` | Actor in object's staging location | Get in/out/off/on |
| `actorOutOfNested` | Actor removed from nested rooms | Exit |
| `travelPermitted` | Travel not blocked | Check only; calls beforeTravel |

Preconditions are listed in the `preCond` property of action handlers:

```
dobjFor(PutIn) {
    preCond = [objHeld, objNotWorn]
}
iobjFor(PutIn) {
    preCond = [containerOpen]
}
```

### 1.3 Check Phase

**Purpose:** Blocks actions that aren't *obviously* illogical -- conditions
the player couldn't know about or wouldn't consider illogical.

**Key distinction from verify:** The parser only calls verify during
disambiguation, never check. An object that fails check is *favoured* over
one that fails verify during disambiguation, because the check failure
isn't "obviously wrong" from the player's perspective.

**Classic example:** Two boxes -- one white (ordinary), one black (glued
shut). Player types OPEN BOX. The player doesn't know the black box is
glued shut, so both commands are equally logical. The "glued shut" condition
belongs in check, not verify. The parser must ask for clarification.

**Design rule:** "Would a reasonable player consider this *obviously* the
wrong thing to try?" If yes -> verify. If no -> check.

**Critical constraint:** Check must NOT modify game state (one exception:
setting tracking flags like "player has attempted this").

**Output control in check:**
- Displaying any text halts the action by default.
- `noHalt()` -- display text without halting.
- `reportAfter(msg)` -- queue message for after report phase.
- `extraReport(msg)` -- display introductory text without suppressing report.

### 1.4 Action Phase

**Purpose:** Execute the effect -- move objects, change state, return output.

**When to display text from action:**
1. The message IS the main point (examining, reading).
2. The outcome is unusual/unexpected (triggering traps, secret doors).

**Implicit action safety patterns:**

Pattern 1 -- suppress custom text when implicit:
```
action() {
    if (!gAction.isImplicit)
        "Custom message. ";
    inherited();
}
```

Pattern 2 -- use `actionReport()`:
```
action() {
    actionReport('Explicit message. ');
    inherited();
}
```

**State change methods:**
- `actionMoveInto(container)` -- move object to container
- `makeLocked(true/false)` -- change lock state
- `makeOpen(true/false)` -- change open state
- `makeOn(true/false)` -- change switch state
- `makeLit(true/false)` -- change lit state

**Nested and Instead actions:**
- `doInstead(action, dobj, iobj)` -- completely replace current action.
  Subsequent code doesn't execute.
- `doNested(action, dobj, iobj)` -- execute action within current action,
  then resume.

### 1.5 Report Phase

**Purpose:** Display grouped summaries for multi-object commands (e.g.
TAKE ALL). Only runs on the last object processed.

**`gActionListStr`** -- single-quoted string listing affected objects in
natural form: `'the pen, the ink and the paper'`.

Report text uses `|` separator:
```
report() {
    say('Taken. | You take <<gActionListStr>>. ');
}
```
Left of `|` = brief (specific commands). Right of `|` = detailed (TAKE ALL).

### 1.6 Remap Phase

Replaces an action's object with another object in the same role:
```
desk: Thing 'desk'
    iobjFor(PutIn) { remap = drawer }
;
```

`asDobjFor(OtherAction)` / `asIobjFor(OtherAction)` make one action behave
identically to another on the same object:
```
drawer: Thing 'drawer'
    isOpenable = true
    dobjFor(Pull) asDobjFor(Open)
;
```

---

## 2. Action Types

### 2.1 Action Classification

| Type | Objects | Example | Handler Location |
|------|---------|---------|------------------|
| `IAction` | None | JUMP | `execAction(c)` on Action |
| `TAction` | 1 (dobj) | TAKE BALL | `dobjFor()` on Thing |
| `TIAction` | 2 (dobj + iobj) | PUT BALL IN BOX | `dobjFor()` + `iobjFor()` on Thing |
| `LiteralAction` | Literal text | WRITE FOO | `execAction(c)` on Action |
| `LiteralTAction` | Literal + dobj | TURN DIAL TO PLAY | `dobjFor()` on Thing |
| `TopicAction` | Topic | THINK ABOUT X | `execAction(c)` on Action |
| `TopicTAction` | Topic + dobj | ASK BOB ABOUT X | `dobjFor()` on Thing |
| `NumericAction` | Number | FOOTNOTE 4 | `execAction(c)` on Action |
| `NumericTAction` | Number + dobj | DIAL 83272 ON PHONE | `dobjFor()` on Thing |

**Critical rule:** Only override `execAction()` for IAction, TopicAction,
LiteralAction, or NumericAction. NEVER for TAction or TIAction -- those use
normal action processing on their objects.

### 2.2 Global Action Variables

| Macro | Value |
|-------|-------|
| `gAction` | Current action object |
| `gActor` | Who's performing the action |
| `gDobj` | Direct object |
| `gIobj` | Indirect object |
| `gLiteral` | Text string for literal actions |
| `gNumber` | Numeric value for numeric actions |
| `gTopic` | ResolvedTopic for topic actions |
| `gCommand` | Current command coordinator |
| `gVerbWord` | First word entered ("hit", "kick") |
| `gVerbPhrase` | Complete command with placeholders |
| `gCommandToks` | Full command tokenised as list |

### 2.3 TIAction Resolution Order

The `resolveFirst` property controls which object resolves first:
- Default: `IndirectObject` (resolve iobj first)
- Exceptions: LockWith, UnlockWith resolve `DirectObject` first

The `execFirst` property controls which object's action handler runs first
(defaults to `resolveFirst` value).

### 2.4 Defining New Verbs

Each verb needs two components:
1. **Action definition** via `DefineIAction`, `DefineTAction`, `DefineTIAction`, etc.
2. **Grammar rule** via `VerbRule` specifying syntax patterns.

Grammar patterns use `singleDobj`/`multiDobj` for object slots,
`singleIobj`/`multiIobj` for indirect objects. At most ONE slot can use
a multi-object keyword.

```
DefineTIAction(PutIn);

VerbRule(PutIn)
    'put' multiDobj 'in' singleIobj
    : VerbProduction
    action = PutIn
    verbPhrase = 'put/putting (what) (in what)'
    missingQ = 'what do you want to put; what do you want to put it in'
;
```

### 2.5 Property Naming Conventions for Actions

**Single-object actions:**
- `isFooable` (e.g. `isTakeable`, `isBurnable`)
- `cannotFooMsg` for custom refusal messages

**Two-object actions:**
- Direct object: `isFooable` (e.g. `isCuttable`)
- Indirect object: `canFooPrepMe` (e.g. `canCutWithMe`)
- Messages: `cannotFooMsg`, `cannotFooPrepMsg`, `cannotFooPrepSelfMsg`

**Derived defaults:**
- `isTakeable` defaults to `!isFixed`
- `isCloseable` defaults to `isOpenable`

---

## 3. Object Properties

### 3.1 Identity and Vocabulary

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `vocab` | string | nil | `'article short name; adjectives; nouns; pronouns'` |
| `name` | string | derived | Override inferred name from vocab |
| `proper` | boolean | auto | True for proper names (auto-set if vocab starts capitalised) |
| `qualified` | boolean | nil | True if name needs no article |
| `plural` | boolean | nil | True for plural names like 'stairs' |
| `disambigName` | string | nil | Name used during parser disambiguation |
| `theName` | string | auto | Name with definite article |
| `aName` | string | auto | Name with indefinite article |

### 3.2 Location and Visibility

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `location` | object | nil | Immediate container. Never set directly -- use `moveInto()`. |
| `isFixed` | boolean | nil | Cannot be picked up. Equivalent to adv3's Fixture class. |
| `isListed` | boolean | auto | Listed in room descriptions. Auto-set opposite of isFixed. |
| `isHidden` | boolean | nil | Hidden from view and player commands. |
| `moved` | boolean | nil | True when object has been moved by player. |
| `listOrder` | number | 0 | Controls sort order in listings. |
| `visibleInDark` | boolean | nil | Object visible in dark without providing light. |

### 3.3 Description Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `desc` | string/method | nil | Main EXAMINE response. |
| `stateDesc` | string | empty | State-specific examination info appended to desc. |
| `specialDesc` | string | nil | Separate paragraph in room listing. |
| `initSpecialDesc` | string | nil | Like specialDesc but only until object is moved. |
| `roomFirstDesc` | string | nil | Room description shown first time only. |
| `inDarkDesc` | string/method | nil | Description shown in darkness if visibleInDark. |
| `smellDesc` | string/method | nil | Response to SMELL. |
| `listenDesc` | string/method | nil | Response to LISTEN TO. |
| `feelDesc` | string/method | nil | Response to FEEL. |
| `tasteDesc` | string/method | nil | Response to TASTE. |
| `readDesc` | string/method | nil | Response to READ. |

### 3.4 Containment

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `contType` | LocType | Outside | `In`, `On`, `Under`, `Behind`, `Carrier`, or `Outside` |
| `contents` | list | empty | All things directly contained. |
| `allContents` | list | evaluated | All direct and indirect contents recursively. |
| `hiddenIn` | list | nil | Objects revealed by LOOK IN. |
| `hiddenUnder` | list | nil | Objects revealed by LOOK UNDER. |
| `hiddenBehind` | list | nil | Objects revealed by LOOK BEHIND. |
| `remapIn` | object | nil | Redirect IN operations to another object. |
| `remapOn` | object | nil | Redirect ON operations. |
| `remapUnder` | object | nil | Redirect UNDER operations. |
| `remapBehind` | object | nil | Redirect BEHIND operations. |

### 3.5 Capacity

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `bulk` | number | 0 | How much space this object occupies. |
| `bulkCapacity` | number | 10000 | Total bulk this object can contain. |
| `maxSingleBulk` | number | bulkCapacity | Max bulk of a single item that fits inside. |
| `maxItemsCarried` | number | 100000 | Max discrete items an actor can carry. |

### 3.6 State Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `isOpen` | boolean | nil | Use `makeOpen()` to change. |
| `isOpenable` | boolean | nil | Can be opened/closed. |
| `isLocked` | boolean | nil | Use `makeLocked()` to change. |
| `lockability` | enum | notLockable | `notLockable`, `lockableWithoutKey`, `lockableWithKey`, `indirectLockable` |
| `autoUnlock` | boolean | nil | Auto-attempt unlock before opening. |
| `isOn` | boolean | nil | Use `makeOn()` to change. |
| `isSwitchable` | boolean | nil | Can be switched on/off. |
| `isLit` | boolean | nil | Use `makeLit()` to change. |
| `isLightable` | boolean | nil | Can be lit/extinguished. |
| `wornBy` | object | nil | Actor currently wearing this. |
| `isWearable` | boolean | nil | Can be worn/doffed. |

### 3.7 Behaviour Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `isEdible` | boolean | nil | Can be eaten. |
| `isDecoration` | boolean | nil | Responds to all commands except EXAMINE with "not important". |
| `decorationActions` | list | [Examine] | Actions allowed on decoration. |
| `isEnterable` | boolean | nil | Player can GET IN (requires contType = In). |
| `isBoardable` | boolean | nil | Player can GET ON (requires contType = On). |
| `isTransparent` | boolean | nil | Can see through closed container. |
| `isVehicle` | boolean | nil | Travels with actor. |

### 3.8 Knowledge Tracking

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `examined` | boolean | nil | Player has examined this. |
| `seen` | boolean | nil | Object has been seen. |
| `familiar` | boolean | nil | PC knows about object without seeing it. |
| `known` | boolean | evaluated | True if seen OR familiar. |
| `lastSeenAt` | object | nil | Room where PC last saw this. |

### 3.9 Reachability

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `checkReach(actor)` | method | unrestricted | Override to block touching. |
| `allowReachOut(obj)` | method | true | Can actor inside reach objects outside? |
| `allowReachIn(obj)` | method | true | Can actor outside reach objects inside? |
| `autoGetOutToReach` | boolean | true | Actor exits to reach external objects. |
| `dropLocation` | object | self | Where items dropped inside land. |
| `stagingLocation` | object | calculated | Where actor must be to enter/board. |

### 3.10 Key Methods

| Method | Description |
|--------|-------------|
| `moveInto(loc)` | Move object silently (no notifications). |
| `actionMoveInto(loc)` | Move with notifications and side effects. |
| `makeOpen(state)` | Open/close with side effects. |
| `makeLocked(state)` | Lock/unlock with side effects. |
| `makeOn(state)` | Switch on/off with side effects. |
| `makeLit(state)` | Light/extinguish with side effects. |
| `isIn(obj)` | True if directly or indirectly contained in obj. |
| `isOrIsIn(obj)` | True if this IS obj or is contained within obj. |
| `isDirectlyIn(obj)` | True if obj is immediate container. |
| `getOutermostRoom()` | Return the Room containing this object. |
| `discover()` | Set isHidden to nil. |
| `addVocabWord(word, flags)` | Add word to vocabulary at runtime. |
| `removeVocabWord(word, flags)` | Remove word from vocabulary. |
| `replaceVocab(voc)` | Replace entire vocab string. |

---

## 4. World Model / Containment Tree

### 4.1 Hierarchy Structure

- The containment model is a strict **tree**: each object has at most one
  parent; parents can have unlimited children.
- **Rooms** sit at the top of the hierarchy and never have parents.
- Everything in the game world must be directly or indirectly inside a Room.
- Objects can be moved to "limbo" (`nil`) to remove them from the world.
- Room is a subclass of Thing -- it inherits all Thing properties/methods.

### 4.2 contType Values

| Value | Meaning | Allows |
|-------|---------|--------|
| `In` | Inside | PUT X IN Y |
| `On` | On top of | PUT X ON Y |
| `Under` | Underneath | PUT X UNDER Y |
| `Behind` | Behind | PUT X BEHIND Y |
| `Carrier` | Carried/worn by actor | Default for Actor class |
| `Outside` | Not a container | Default for Thing |

An object can only have ONE contType. A desk that has both a drawer (In)
and a surface (On) requires two programming objects (or use `remapIn` /
`remapOn` to redirect).

### 4.3 Key Relationships

- `location` -- points to parent. NEVER set directly; use `moveInto()`.
- `contents` -- list of children.
- `allContents` -- recursive list of all descendants.
- `isIn(obj)` -- is this object anywhere inside obj (any depth)?
- `isDirectlyIn(obj)` -- is obj the immediate parent?

### 4.4 Actor Containment

Actors have `contType = Carrier`. Their children include:
- Items carried (default)
- Items worn (tracked via `wornBy` property)
- Body parts (marked `isFixed = true`)

### 4.5 Room Class

**Key Room properties:**

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `roomTitle` | string | -- | Bold name at top of room description |
| `desc` | string/method | -- | Main room description body |
| `isLit` | boolean | true | Room has light |
| `darkName` | string | "In the dark" | Title when dark |
| `darkDesc` | string | standard | Description when dark |
| `allowDarkTravel` | boolean | false | Permit travel from dark rooms |
| `visited` | boolean | nil | PC has been here |
| `floorObj` | object | default Floor | Floor for disambiguation |
| `extraScopeItems` | list | nil | Objects in scope despite normal rules |

**Direction properties** (16 total): `north`, `south`, `east`, `west`,
`northeast`, `northwest`, `southeast`, `southwest`, `port`, `starboard`,
`fore`, `aft`, `up`, `down`, `in`, `out`.

Direction values can be:
- Another Room (direct travel)
- A Door object
- A TravelConnector (complex travel)
- Double-quoted string (failed travel, triggers beforeTravel)
- Single-quoted string (no travel, no beforeTravel)
- Method (executed; return value NOT used)
- `asExit(direction)` macro (invisible synonym)

### 4.6 Regions

Regions group rooms. Rooms list regions via their `regions` property;
Regions can list rooms via `rooms`.

- Regions can nest (contain other regions).
- Rooms can belong to multiple overlapping regions.
- `familiar` on a region makes all contained rooms familiar.
- `extraScopeItems` on a region applies to all rooms within.
- Regions have their own `regionBeforeAction()`, `regionAfterAction()`,
  `regionBeforeTravel()`, `regionAfterTravel()`, `regionDaemon()`.

---

## 5. Parser / Vocabulary

### 5.1 The vocab Property

adv3Lite consolidates object vocabulary into a single `vocab` property:

```
'article short name; adjectives; nouns; pronouns'
```

Example:
```
velvetCloak: Thing 'dark handsome velvet cloak; black satin; cloak wrap'
```

- **Section 1** (before first `;`): The display name with adjectives and noun.
  First word may be an article. Capitalised first word auto-sets `proper = true`.
- **Section 2**: Additional adjectives not in the display name.
- **Section 3**: Additional nouns/synonyms.
- **Section 4** (optional): Pronoun overrides (`him`, `her`, `it`, `them`).

### 5.2 Parser Matching (Mercury Parser)

adv3Lite uses the **Mercury parser** (not the adv3 parser). Key differences:
- Vocabulary is stored at the individual object level, not in a central
  dictionary.
- Less fussy about word order -- handles phrases like "Kranky the Clown".
- Each object's `vocabWords` is a vector of vocabWord objects with `posFlags`
  (`MatchNoun`, `MatchAdj`).

### 5.3 matchName and Disambiguation

- `matchName(toks)` -- override for custom word-order matching.
- `matchNameCommon()` -- shared handler for normal and disambiguation matching.
- `filterResolveList(np, cmd, mode)` -- filter during parser selection.
- `hideFromAll(action)` -- return true to exclude from ALL commands.
- `vocabLikelihood` -- -20 to +20 tie-breaker for parser preference.

### 5.4 matchPhrases

`matchPhrases` restricts matching to specific word sequences:
```
matchPhrases = ['dark green']  // only match when both words used together
```

### 5.5 Grammar Rules (VerbRule)

Grammar patterns use:
- Single quotes for literal words: `'take'`, `'pick' 'up'`
- `singleDobj` / `multiDobj` for object slots
- `singleIobj` / `multiIobj` for indirect objects
- `literalDobj` for literal text
- `topicDobj` / `topicIobj` for topics
- `|` for alternatives: `'take' | 'grab' | 'get'`
- Parentheses for grouping: `('doze' | 'nod') 'off'`

---

## 6. Scope Rules

### 6.1 What is Scope?

Scope = the set of objects available to be targets of commands. Roughly:
objects in the same top-level Room AND visible to the player (not enclosed
in an opaque closed container).

### 6.2 Normal Scope Computation

Objects in scope include:
- Objects in the current Room
- Objects in open containers that are themselves in scope
- Objects carried by the actor
- Objects visible through transparent containers (for non-touch actions)

Objects NOT in scope:
- Objects in opaque closed containers
- Objects in other rooms
- Objects invisible/hidden

### 6.3 Dark Room Scope

When a room lacks light, scope is restricted to:
- The actor itself
- The actor's contents (carried items)
- Objects where `visibleInDark = true`

### 6.4 Topic Scope

Topic scope defaults to Things and Topics "known to the player character"
(where `obj.known` is true or `gPlayerChar.knowsAbout(obj)` is true).

### 6.5 Modifying Scope

Six techniques (in order of intrusiveness):

1. Define `Special` objects to change `Q.scopeList()` results
2. Override `addExtraScopeItems(role)` on the action
3. Override `addExtraScopeItems(action)` on the current Room
4. List items in `extraScopeItems` on enclosing Room or Region
5. Override `addExtraScopeItems(action)` on Region
6. Override `buildScopeList(role)` for completely custom scope

### 6.6 Querying Scope

```
Q.scopeList(actor).toList()   // physical scope
Q.topicScope()                // topic scope
Q.knownScopeList()            // Things known to PC
```

---

## 7. adv3Lite vs adv3 Differences

### 7.1 What adv3Lite Removes/Simplifies

| Feature | adv3 | adv3Lite |
|---------|------|---------|
| Class hierarchy | Vast, many specialised classes | Drastically reduced; most objects are Thing with properties |
| Containment classes | Container, Surface, Underside, etc. | Thing with `contType = In/On/Under/Behind` |
| Actor classes | Multiple Actor + ActorState classes | One Actor class, one ActorState class |
| Lighting | 4 brightness levels (0-4) | Binary `isLit` / `visibleInDark` |
| Sense passing | Complex sensory media types + attenuation | Simplified; SenseRegions for cross-room sensing |
| Postures | Standing, sitting, lying down | Removed entirely |
| Room parts | Walls, ceilings, floor details | Removed (floor retained for disambiguation) |
| Real-time processing | Supported | Removed |
| Transcript system | Output capture/manipulation | Removed; text goes directly to screen |
| Parser | adv3 parser | Mercury parser (built from scratch) |
| Vocabulary | `vocabWords` + `name` separate | Single `vocab` property |
| Room name | `roomName` | `roomTitle` |

### 7.2 What adv3Lite Adds

- **Scenes** -- borrowed from Inform 7
- **Regions** -- room grouping with shared behaviour
- **GO TO command** -- built-in pathfinding
- **Doers** -- action interception (similar to Inform 7's Instead rules)
- **Improved conversation system** -- more flexible than adv3's
- **Modular architecture** -- can exclude NPC module, etc.
- **Automatic object grouping** -- "three gold coins" instead of listing each

### 7.3 Architecture

adv3Lite was NOT built by stripping down adv3. It was built from scratch
on the Mercury parser foundation. This means direct backporting of adv3
features is difficult. The two libraries share TADS 3 the language but
diverge significantly in library architecture.

---

## 8. Event / Notification System

### 8.1 Notification Order

**Before action notifications** (by priority):

| Priority | Rule | What it calls |
|----------|------|---------------|
| 8000 | sceneNotifyBeforeRule | `beforeAction()` on current Scenes |
| 7000 | roomNotifyBeforeRule | `roomBeforeAction()` on current Room; `regionBeforeAction()` on Regions |
| 6000 | scopeListNotifyBeforeRule | `beforeAction()` on all objects in scope |

**After action notifications:**

| Priority | Rule | What it calls |
|----------|------|---------------|
| 9000 | notifyScenesAfterRule | `afterAction()` on current Scenes |
| 8000 | roomNotifyAfterRule | `roomAfterAction()` on current Room; `regionAfterAction()` on Regions |

### 8.2 Notification Methods on Objects

| Method | Where Defined | When Called |
|--------|---------------|------------|
| `beforeAction()` | Any in-scope object | Before action executes |
| `afterAction()` | Any in-scope object | After action completes |
| `roomBeforeAction()` | Room | Before action in this room |
| `roomAfterAction()` | Room | After action in this room |
| `regionBeforeAction()` | Region | Before action in this region |
| `regionAfterAction()` | Region | After action in this region |
| `roomDaemon()` | Room | Each turn (often cycles atmospheric messages) |
| `regionDaemon()` | Region | Each turn |
| `travelerLeaving(traveler, dest)` | Room | Someone leaves this room |
| `travelerEntering(traveler, origin)` | Room | Someone enters this room |
| `regionBeforeTravel(traveler, connector)` | Region | Before inter-region travel |
| `regionAfterTravel(traveler, connector)` | Region | After inter-region travel |

### 8.3 beforeAction Can Block

Any `beforeAction` / `roomBeforeAction` / `regionBeforeAction` can block
the action by displaying text (which halts execution) or by calling `exit`.

### 8.4 Configurable Ordering

The `gameMain.beforeRunsBeforeCheck` flag controls whether before
notifications run before or after the check phase:
- `true` (default in modern TADS): before runs BEFORE check
- `nil`: before runs AFTER check (lets "before" handlers assume the
  command will complete)

Game code can reorder rules by reassigning priorities.

---

## 9. Implied Actions

### 9.1 How They Work

An implicit action is an automatic action the game performs to enable
the explicitly commanded action to proceed. Example: THROW BALL when not
holding it triggers implicit Take.

### 9.2 Trigger Mechanisms

**PreConditions** (primary): When a PreCondition fails, it automatically
invokes an implicit action. E.g., `objHeld` triggers implicit Take.

**Manual trigger**: `tryImplicitAction(ActionName, objects...)`:
```
tryImplicitAction(Take, redBall);
```

### 9.3 Blocking Implicit Actions

- `dangerous` in verify: prevents implicit selection but allows explicit.
- `nonObvious` in verify: prevents implicit/default selection.
- If verify result is `nonObvious` or `dangerous`, implicit action is
  aborted before announcement.

### 9.4 Implicit Action Reports

- Success: `"(first taking the pen)"`
- Failure: `"(first trying to take the pen)"`
- Multiple: `"(first taking the gold key, then unlocking the small box with the gold key, then opening the small box)"`

Suppress reports per action: `modify Take { reportImplicitActions = nil }`

### 9.5 Implicit Action Chain Example

Player types: PUT RING IN BOX (box is locked, key is on floor)

Chain if autoUnlock = true:
1. Precondition `containerOpen` on box fails -> implicit Open
2. Open's precondition `objUnlocked` fails -> implicit Unlock
3. Unlock's precondition `objHeld` (for key) fails -> implicit Take
4. Take succeeds -> Unlock succeeds -> Open succeeds -> PutIn proceeds

Report: `"(first taking the gold key, then unlocking the small box with the gold key, then opening the small box)"`

---

## 10. Doers

### 10.1 What They Are

A Doer intercepts between a Command and the actions it performs. Similar to
Inform 7's "Instead" rules. They operate after the parser identifies the
action and objects but before verify methods run.

### 10.2 Command Matching

The `cmd` property uses source-code object names:
```
Doer 'put Treasure in Container'      // any Treasure in any Container
     'take skull; put skull in Thing'  // multiple verbs with semicolons
     '* Thing'                         // any verb with a Thing dobj
     'go north|south'                  // direction matching
;
```

### 10.3 Conditional Properties

| Property | Purpose |
|----------|---------|
| `where` | Limit to specific rooms/regions |
| `during` | Restrict to particular scenes |
| `when` | Custom boolean condition |
| `who` | Specific actor(s) |
| `strict` | Match exact first word (prevent alias matching) |

### 10.4 Priority

When multiple Doers match, specificity determines precedence:
1. Manual `priority` property (highest weight)
2. `when` condition presence
3. `where` condition presence
4. `who` condition presence
5. `during` condition presence
6. Specific actions over wildcards
7. Specialised object classes over base classes

### 10.5 Key Methods

- `exec(curCmd)` -- called for all commands (player + directed NPC)
- `execAction(curCmd)` -- called only for player character actions
- `doInstead(Action, dobj, iobj)` -- redirect to different action
- `handleAction = true` -- ensure beforeAction notifications fire

---

## 11. Other Distinctive Patterns

### 11.1 The Q Object

adv3Lite routes all "query" operations through a global `Q` object,
allowing the query system to be swapped or modified:
- `Q.scopeList(actor)` -- get scope list
- `Q.topicScope()` -- get topic scope
- `Q.knownScopeList()` -- get known scope

### 11.2 Scenes

Borrowed from Inform 7. Scenes represent story phases with:
- `isHappening` -- currently active?
- `startsWhen` / `endsWhen` -- conditions
- `whenStarting()` / `whenEnding()` -- hooks
- `beforeAction()` / `afterAction()` -- action interception

### 11.3 Sensory Regions

SenseRegions provide sensory connections between rooms:
- Can hear across rooms in the same SenseRegion
- Can smell across rooms
- Can see across rooms (configurable per sense)

### 11.4 The "Key" Knowledge Pattern

The library's Key class implements a knowledge-tracking pattern: initially
all keys rank equally for UNLOCK. But after a key is successfully used on
a lock, the game records this, and future verify scores boost that key for
that lock. This models player knowledge accumulation.

### 11.5 Multi-Method Dispatch for TIActions

Alternative to dobjFor/iobjFor: polymorphic methods dispatched on both
object types simultaneously:
```
checkCutWith(Thing dobj, lawnmower iobj) {
    "That would be impracticable. ";
}
actionCutWith(lawn dobj, lawnmower iobj) {
    dobj.makeMown();
    "You manage to mow the lawn. ";
}
```

### 11.6 askForDobj / askForIobj

When a required object is missing from the command, the action can prompt:
```
askForDobj(PutIn)   // "What do you want to put in it?"
askForIobj(PutIn)   // "What do you want to put it in?"
```

### 11.7 EventList Classes

Used for cycling atmospheric messages:
- `EventList` -- plays events in order, stops at end
- `CyclicEventList` -- loops
- `ShuffledEventList` -- random order, no immediate repeats
- `RandomEventList` -- truly random
- `SyncEventList` -- synchronised with another list

### 11.8 The Command Execution Pipeline (Full)

1. **Input** -- PromptDaemons, StringPreParsers, tokenisation
2. **Parse** -- Grammar matching, verb identification, CommandRanking
3. **Resolve nouns** -- Scope filtering, matchName, filterResolveList,
   verify scoring, disambiguation
4. **Pre-execution** -- Global remapping, savepoint, actor busy check
5. **For each object:**
   a. Remap check
   b. Implicit action verify (abort if nonObvious/dangerous)
   c. Announce implicit action
   d. Full verify
   e. Check preconditions (may trigger implicit actions, loop to d)
   f. Before notifications (scenes, room, region, scope objects)
   g. Actor action
   h. Check phase
   i. Action phase
   j. After notifications
6. **Report** (multi-object summary)
7. **Post-action** -- lighting state changes, busy time

---

## Sources

- [adv3Lite Manual -- Action Results](https://faroutscience.com/adv3lite_docs/manual/actres.htm)
- [adv3Lite Manual -- Things](https://faroutscience.com/adv3lite_docs/manual/thing.htm)
- [adv3Lite Manual -- Rooms](https://faroutscience.com/adv3lite_docs/manual/room.htm)
- [adv3Lite Manual -- Scope](https://tads.dev/docs/adv3lite/docs/manual/scope.htm)
- [adv3Lite Manual -- Action Overview](https://faroutscience.com/adv3lite_docs/manual/actionoverview.htm)
- [adv3Lite Manual -- Implicit Actions](https://faroutscience.com/adv3lite_docs/manual/implicit.htm)
- [adv3Lite Manual -- Doers](https://jimbonator.github.io/tads-cookbook/adv3Lite/manual/doer.htm)
- [Verify, Check, and When to Use Which](https://faroutscience.com/adv3lite_docs/techman/t3verchk.htm)
- [How to Create Verbs](https://faroutscience.com/adv3lite_docs/techman/t3verb.htm)
- [TADS 3 Action Results](http://www.tads.org/t3doc/doc/techman/t3res.htm)
- [TADS 3 Command Execution Cycle](http://www.tads.org/t3doc/doc/techman/t3cycle.htm)
- [TADS 3 Verify Phase (Getting Started)](https://tads.org/t3doc/doc/gsg/verify.htm)
- [TADS 3 System Manual Introduction](https://www.tads.org/t3doc/doc/sysman/intro.htm)
- [adv3Lite Containment Tutorial](https://faroutscience.com/adv3lite_docs/tutorial/containment.htm)
- [adv3Lite Features -- Eric Eve](https://ericeve.livejournal.com/1709.html)
- [adv3Lite Design Decisions (intfiction.org)](https://intfiction.org/t/adv3lite-design-decisions/11106)
- [Verify Action Results Discussion (intfiction.org)](https://intfiction.org/t/working-with-action-verifyaction-results-a-la-illogical-illogicalnow-and-so-on/59319)
- [adv3Lite Overview (users.ox.ac.uk)](https://users.ox.ac.uk/~manc0049/TADSGuide/adv3Lite.htm)
- [adv3Lite Tutorial -- What Is It](https://tads.dev/docs/adv3lite/docs/tutorial/whatis.htm)
- [adv3Lite GitHub Repository](https://github.com/EricEve/adv3lite)
