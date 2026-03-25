// test/parserTest.ts
// TypeScript port of test/parser_test.lua.
// Runs in the browser via main.ts on page load.

import { process, reset as parserReset } from '../parser/index.ts'
import { verifyRank }                    from '../parser/resolver.ts'
import { World }                         from '../world/world.ts'
import { State }                         from '../world/state.ts'

type PrintFn = (text: string, colour: string) => void

export function runTests(print: PrintFn, colours: Record<string, string>): void {
    World.reset()
    parserReset()
    State.reset()
    let passed = 0
    let failed = 0

    function check(description: string, input: string, expected: string): void {
        const output = process(input)
        if (output === expected) {
            print('PASS: ' + description, colours.system)
            passed++
        } else {
            print('FAIL: ' + description, colours.error)
            print('  expected: ' + JSON.stringify(expected), colours.error)
            print('  got:      ' + JSON.stringify(output),   colours.error)
            failed++
        }
    }

    function header(title: string): void {
        print('', colours.system)
        print('-- ' + title + ' --', colours.narrator)
    }

    // -----------------------------------------------------------------------
    header('Empty and unrecognised input')
    // -----------------------------------------------------------------------

    check('empty input returns empty string', '', '')
    check('unrecognised verb', 'jump', 'You don\'t need to use the word "jump".')

    // -----------------------------------------------------------------------
    header('look')
    // -----------------------------------------------------------------------

    check('look gives room title and description', 'look',
        'Your Quarters\n' +
        'Your quarters are exactly as you left them — which is to ' +
        'say, arranged with the particular chaos of someone who ' +
        'knows where everything is.' +
        '\n\nYou can also see: iron key, copper key, oil lamp, and small chest.' +
        '\n\nThere is a writing desk here. On the desk surface: quill pen.' +
        '\n\nExits: north.')

    check('second look gives short description', 'look',
        'Your Quarters\n' +
        'Your quarters.' +
        '\n\nYou can also see: iron key, copper key, oil lamp, and small chest.' +
        '\n\nThere is a writing desk here. On the desk surface: quill pen.' +
        '\n\nExits: north.')

    check('l is a synonym for look', 'l',
        'Your Quarters\n' +
        'Your quarters.' +
        '\n\nYou can also see: iron key, copper key, oil lamp, and small chest.' +
        '\n\nThere is a writing desk here. On the desk surface: quill pen.' +
        '\n\nExits: north.')

    // -----------------------------------------------------------------------
    header('inventory')
    // -----------------------------------------------------------------------

    check('inventory when carrying nothing', 'inventory', 'You are carrying nothing.')
    check('i is a synonym for inventory', 'i', 'You are carrying nothing.')

    // -----------------------------------------------------------------------
    header('examine')
    // -----------------------------------------------------------------------

    check('examine the lamp', 'examine lamp',
        'A brass oil lamp. The reservoir is about half full.')
    check('x is a synonym for examine', 'x lamp',
        'A brass oil lamp. The reservoir is about half full.')
    check('examine with adjective', 'examine iron key',
        'A small iron key. The bow is cast in the shape of a hare.')
    check('examine the desk', 'examine desk',
        'A large wooden desk. A faint ring left by some long-gone cup marks the surface.' +
        '\nThe desk drawer is closed.' +
        '\nOn the desk surface: quill pen.')
    check('examine something not here', 'examine dragon',
        "You don't see any dragon here.")

    // -----------------------------------------------------------------------
    header('take')
    // -----------------------------------------------------------------------

    check('take the lamp', 'take lamp', 'Taken.')
    check('take lamp again (already carrying it)', 'take lamp', "You're already carrying that.")
    check('take the desk (not portable)', 'take desk', "You can't pick that up.")
    check('inventory shows carried item', 'inventory', 'You are carrying: oil lamp.')

    // -----------------------------------------------------------------------
    header('drop')
    // -----------------------------------------------------------------------

    check('drop the lamp (carrying it)', 'drop lamp', 'Dropped.')
    check('drop the lamp again (not carrying it)', 'drop lamp', "You aren't carrying that.")
    check('drop iron key (never picked up)', 'drop iron key', "You aren't carrying that.")

    // -----------------------------------------------------------------------
    header('go')
    // -----------------------------------------------------------------------

    check('go north moves to entrance passage', 'go north',
        'Entrance Passage\n' +
        'A narrow stone passage leads away from your quarters. ' +
        'Bare walls, bare floor. The way back is to the south.' +
        '\n\nExits: south.')

    check('second look in new room gives short desc', 'look',
        'Entrance Passage\n' +
        'The entrance passage. Bare stone.' +
        '\n\nExits: south.')

    check('go east blocked (connector present but canPass false)', 'go east',
        'The door is locked shut.')

    check('go south returns to player quarters', 'go south',
        'Your Quarters\n' +
        'Your quarters.' +
        '\n\nYou can also see: iron key, copper key, oil lamp, and small chest.' +
        '\n\nThere is a writing desk here. On the desk surface: quill pen.' +
        '\n\nExits: north.')

    // -----------------------------------------------------------------------
    header('bare directions')
    // -----------------------------------------------------------------------

    check('bare north moves room', 'north',
        'Entrance Passage\n' +
        'The entrance passage. Bare stone.' +
        '\n\nExits: south.')

    check("bare 's' abbreviation moves back", 's',
        'Your Quarters\n' +
        'Your quarters.' +
        '\n\nYou can also see: iron key, copper key, oil lamp, and small chest.' +
        '\n\nThere is a writing desk here. On the desk surface: quill pen.' +
        '\n\nExits: north.')

    check("bare 'n' abbreviation moves again", 'n',
        'Entrance Passage\n' +
        'The entrance passage. Bare stone.' +
        '\n\nExits: south.')

    check('bare direction with blocked connector', 'east',
        'The door is locked shut.')

    check("bare 'south' returns home", 'south',
        'Your Quarters\n' +
        'Your quarters.' +
        '\n\nYou can also see: iron key, copper key, oil lamp, and small chest.' +
        '\n\nThere is a writing desk here. On the desk surface: quill pen.' +
        '\n\nExits: north.')

    // -----------------------------------------------------------------------
    header('disambiguation')
    // -----------------------------------------------------------------------

    check('take key is ambiguous', 'take key',
        'Which do you mean, the iron key or the copper key?')
    check('clarification resolves and dispatches', 'copper key', 'Taken.')
    check('take key auto-resolves after one is taken', 'take key',
        '(the iron key) Taken.')

    // -----------------------------------------------------------------------
    header('put')
    // copper_key and iron_key are in inventory; oil_lamp is in the room.
    // -----------------------------------------------------------------------

    check('put key on desk (remaps to desk surface)', 'put iron key on desk',
        'You put the iron key on the desk surface.')
    check('put key on desk again (not holding it)', 'put iron key on desk',
        "You aren't holding that.")
    check('put with no destination', 'put copper key',
        'Put the copper key where?')

    // -----------------------------------------------------------------------
    header('unlock / lock')
    // iron_key is on desk_surface (accessible); copper_key is in inventory.
    // -----------------------------------------------------------------------

    check('unlock chest with ambiguous key disambiguates', 'unlock chest with key',
        'Which do you mean, the iron key or the copper key?')
    check('clarifying wrong key gives correct rejection', 'copper key',
        "That key doesn't fit.")
    check('unlock chest with no key', 'unlock chest', "You'll need a key for that.")
    check('unlock chest with wrong key', 'unlock chest with copper key', "That key doesn't fit.")
    check('unlock chest with correct key', 'unlock chest with iron key', 'Unlocked.')
    check('unlock already-unlocked chest', 'unlock chest with iron key', "It's not locked.")
    check('lock chest with correct key', 'lock chest with iron key', 'Locked.')
    check('lock already-locked chest', 'lock chest with iron key', "It's already locked.")
    check('unlock non-lockable object', 'unlock desk', "That doesn't have a lock.")

    check('unlock with key is ambiguous', 'unlock chest with key',
        'Which do you mean, the iron key or the copper key?')
    check('adjective-only clarification selects iron key', 'iron', 'Unlocked.')
    check('lock chest to restore state', 'lock chest with iron key', 'Locked.')

    // -----------------------------------------------------------------------
    header('verifyRank')
    // -----------------------------------------------------------------------

    function checkRank(description: string, result: Parameters<typeof verifyRank>[0], expected: number): void {
        const got = verifyRank(result)
        if (got === expected) {
            print('PASS: ' + description, colours.system)
            passed++
        } else {
            print('FAIL: ' + description, colours.error)
            print(`  expected rank: ${expected}`, colours.error)
            print(`  got rank:      ${got}`,      colours.error)
            failed++
        }
    }
    checkRank('null result -> 100',            null,                         100)
    checkRank('logical -> 100',                { logical: true },            100)
    checkRank('logical with rank -> custom',   { logical: true, rank: 150 }, 150)
    checkRank('dangerous -> 90',               { dangerous: true },          90)
    checkRank('illogicalAlready -> 40',        { illogicalAlready: '' },     40)
    checkRank('illogicalNow -> 40',            { illogicalNow: '' },         40)
    checkRank('illogical -> 30',               { illogical: '' },            30)
    checkRank('nonObvious -> 30',              { nonObvious: true },         30)

    // -----------------------------------------------------------------------
    header('connectors')
    // Player is in player_quarters (reset). Go north to entrance_passage first.
    // -----------------------------------------------------------------------

    check('go north to entrance passage (setup for connector tests)', 'north',
        'Entrance Passage\n' +
        'The entrance passage. Bare stone.' +
        '\n\nExits: south.')

    check('blocked connector returns blockedMsg', 'east',
        'The door is locked shut.')

    check('listExits hides blocked connector', 'look',
        'Entrance Passage\n' +
        'The entrance passage. Bare stone.' +
        '\n\nExits: south.')

    State.set('test_passage_open', true)

    check('unblocked connector traverses with traversalMsg', 'east',
        'You push through the heavy door.\n\n' +
        'Blocked Passage\n' +
        'A short corridor. The way back is west.' +
        '\n\nExits: west.')

    check('listExits shows unblocked connector from destination', 'look',
        'Blocked Passage\n' +
        'A short corridor. The way back is west.' +
        '\n\nExits: west.')

    // -----------------------------------------------------------------------
    header('open / close')
    // Navigate back to player_quarters where the chest is.
    // -----------------------------------------------------------------------

    check('west back to entrance passage', 'west',
        'Entrance Passage\n' +
        'The entrance passage. Bare stone.' +
        '\n\nExits: east, south.')

    check('south back to player quarters', 'south',
        'Your Quarters\n' +
        'Your quarters.' +
        '\n\nYou can also see: oil lamp and small chest.' +
        '\n\nThere is a writing desk here. On the desk surface: iron key, quill pen.' +
        '\n\nExits: north.')

    check('open locked chest is blocked', 'open chest', "It's locked.")
    check('unlock chest to allow opening', 'unlock chest with iron key', 'Unlocked.')
    check('open chest', 'open chest', 'Opened.')
    check('open chest again (already open)', 'open chest', "It's already open.")
    check('close chest', 'close chest', 'Closed.')
    check('close chest again (already closed)', 'close chest', "It's already closed.")
    check('open non-openable object', 'open lamp', "That doesn't open.")

    // -----------------------------------------------------------------------
    header('containment')
    // -----------------------------------------------------------------------

    check('examine quill pen via desk surface', 'examine quill pen',
        'A quill pen of dark feather. The nib is still sharp.')
    check('examine desk surface shows contents', 'examine desk surface',
        'The writing surface of the desk.\nOn it: iron key, quill pen.')
    check('velvet pouch out of scope when chest closed', 'examine velvet pouch',
        "You don't see any velvet pouch here.")
    check('examine desk drawer (closed)', 'examine desk drawer',
        'A narrow drawer in the writing desk. It is closed.')
    check('take quill pen from desk surface', 'take quill pen', 'Taken.')
    check('put quill pen on desk (remaps to desk surface)', 'put quill pen on desk',
        'You put the quill pen on the desk surface.')
    check('take quill pen again', 'take quill pen', 'Taken.')
    check('put quill pen in desk (drawer closed)', 'put quill pen in desk',
        "The desk drawer isn't open.")
    check('open desk drawer', 'open desk drawer', 'Opened.')
    check('put quill pen in desk (drawer open)', 'put quill pen in desk',
        'You put the quill pen in the desk drawer.')
    check('examine desk drawer (open, with quill pen)', 'examine desk drawer',
        'A narrow drawer in the writing desk. It is open.\nIt contains: quill pen.')
    check('open chest (unlocked from earlier)', 'open chest', 'Opened.')
    check('velvet pouch in scope when chest open', 'examine velvet pouch',
        'A small velvet pouch, tied with a drawstring.')
    check('examine chest (open, with velvet pouch)', 'examine chest',
        'A small wooden chest secured with an iron lock. It is open.\n' +
        'It contains: velvet pouch.')
    check('put key in lamp (lamp is not a container)', 'put copper key in lamp',
        "You can't put things in the oil lamp.")

    // -----------------------------------------------------------------------
    header('open / close desk via remap')
    // -----------------------------------------------------------------------

    check('close desk (remaps to drawer)', 'close desk', 'Closed.')
    check('take iron key from desk surface', 'take iron key', 'Taken.')
    check('open desk (remaps to drawer)', 'open desk', 'Opened.')
    check('put iron key in desk', 'put iron key in desk',
        'You put the iron key in the desk drawer.')
    check('close desk again', 'close desk', 'Closed.')
    check('iron key not in scope when drawer closed', 'take iron key',
        "You don't see any iron key here.")
    check('open desk to retrieve iron key', 'open desk', 'Opened.')
    check('take iron key from open drawer', 'take iron key', 'Taken.')
    check('inventory shows iron key and copper key', 'inventory',
        'You are carrying: copper key, iron key.')

    // -----------------------------------------------------------------------
    print('', colours.system)
    const colour = failed > 0 ? colours.error : colours.system
    print(`${passed} passed, ${failed} failed.`, colour)
}
