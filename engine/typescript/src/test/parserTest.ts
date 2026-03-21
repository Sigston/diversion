// test/parserTest.ts
// TypeScript port of test/parser_test.lua.
// Runs in the browser via main.ts on page load.

import { process, reset as parserReset } from '../parser/index.ts'
import { verifyRank }                    from '../parser/resolver.ts'
import { World }                         from '../world/world.ts'

type PrintFn = (text: string, colour: string) => void

export function runTests(print: PrintFn, colours: Record<string, string>): void {
    World.reset()
    parserReset()
    let passed = 0
    let failed = 0

    function check(description: string, input: string, expected: string): void {
        const output = process(input)
        if (output === expected) {
            print('PASS: ' + description, colours.system)
            passed++
        } else {
            print('FAIL: ' + description, colours.error)
            print('  expected: ' + expected, colours.error)
            print('  got:      ' + output,   colours.error)
            failed++
        }
    }

    function header(title: string): void {
        print('', colours.system)
        print('-- ' + title + ' --', colours.narrator)
    }

    header('Empty and unrecognised input')
    check('empty input returns empty string', '', '')
    check('unrecognised verb', 'jump', 'You don\'t need to use the word "jump".')

    header('look')
    check('look gives room title', 'look',
        'Your Quarters\n' +
        'Your quarters are exactly as you left them — which is to ' +
        'say, arranged with the particular chaos of someone who ' +
        'knows where everything is. The writing desk dominates one ' +
        'wall. An oil lamp sits where you last set it down. ' +
        'Somewhere nearby, an iron key catches the light.')
    check('second look gives short description', 'look',
        'Your Quarters\nYour quarters. The writing desk, the lamp, the key.')
    check('l is a synonym for look', 'l',
        'Your Quarters\nYour quarters. The writing desk, the lamp, the key.')

    header('inventory')
    check('inventory when carrying nothing', 'inventory', 'You are carrying nothing.')
    check('i is a synonym for inventory', 'i', 'You are carrying nothing.')

    header('examine')
    check('examine the lamp', 'examine lamp',
        'A brass oil lamp. The reservoir is about half full.')
    check('x is a synonym for examine', 'x lamp',
        'A brass oil lamp. The reservoir is about half full.')
    check('examine with adjective', 'examine iron key',
        'A small iron key. The bow is cast in the shape of a hare.')
    check('examine the desk', 'examine desk',
        'A large wooden desk. Its surface is bare except for a ' +
        'faint ring left by some long-gone cup.')
    check('examine something not here', 'examine dragon',
        "You don't see any dragon here.")

    header('take')
    check('take the lamp', 'take lamp', 'Taken.')
    check('take lamp again (already carrying it)', 'take lamp', "You're already carrying that.")
    check('take the desk (not portable)', 'take desk', "You can't pick that up.")
    check('inventory shows carried item', 'inventory', 'You are carrying: oil lamp.')

    header('drop')
    check('drop the lamp (carrying it)', 'drop lamp', 'Dropped.')
    check('drop the lamp again (not carrying it)', 'drop lamp', "You aren't carrying that.")
    check("drop iron key (never picked up)", 'drop iron key', "You aren't carrying that.")

    header('go')
    check('go north moves to entrance passage', 'go north',
        'Entrance Passage\n' +
        'A narrow stone passage leads away from your quarters. ' +
        'Bare walls, bare floor. The way back is to the south.')
    check('second look in new room gives short desc', 'look',
        'Entrance Passage\nThe entrance passage. Bare stone.')
    check('go east blocked (no exit in entrance passage)', 'go east',
        "You can't go that way.")
    check('go south returns to player quarters', 'go south',
        'Your Quarters\nYour quarters. The writing desk, the lamp, the key.')

    header('bare directions')
    check('bare north moves room', 'north',
        'Entrance Passage\nThe entrance passage. Bare stone.')
    check("bare 's' abbreviation moves back", 's',
        'Your Quarters\nYour quarters. The writing desk, the lamp, the key.')
    check("bare 'n' abbreviation moves again", 'n',
        'Entrance Passage\nThe entrance passage. Bare stone.')
    check('bare direction with no exit', 'east', "You can't go that way.")
    check("bare 'south' returns home", 'south',
        'Your Quarters\nYour quarters. The writing desk, the lamp, the key.')

    header('disambiguation')
    check('take key is ambiguous', 'take key',
        'Which do you mean, the iron key or the copper key?')
    check('clarification resolves and dispatches', 'copper key', 'Taken.')
    check('take key auto-resolves after one is taken', 'take key',
        '(the iron key) Taken.')

    header('put')
    check('put key on desk', 'put iron key on desk',
        'You put the iron key on the writing desk.')
    check('put key on desk again (not holding it)', 'put iron key on desk',
        "You aren't holding that.")
    check('put with no destination', 'put copper key',
        'Put the copper key where?')

    header('unlock / lock')
    check('unlock chest with no key', 'unlock chest', "You'll need a key for that.")
    check('unlock chest with wrong key', 'unlock chest with copper key', "That key doesn't fit.")
    check('unlock chest with correct key', 'unlock chest with iron key', 'Unlocked.')
    check('unlock already-unlocked chest', 'unlock chest with iron key', "It's not locked.")
    check('lock chest with correct key', 'lock chest with iron key', 'Locked.')
    check('lock already-locked chest', 'lock chest with iron key', "It's already locked.")
    check('unlock non-lockable object', 'unlock desk', "That doesn't have a lock.")

    header('verifyRank')
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
    checkRank('null result -> 100',            null,                        100)
    checkRank('logical -> 100',                { logical: true },           100)
    checkRank('logical with rank -> custom',   { logical: true, rank: 150 }, 150)
    checkRank('dangerous -> 90',               { dangerous: true },         90)
    checkRank('illogicalAlready -> 40',        { illogicalAlready: '' },    40)
    checkRank('illogicalNow -> 40',            { illogicalNow: '' },        40)
    checkRank('illogical -> 30',               { illogical: '' },           30)
    checkRank('nonObvious -> 30',              { nonObvious: true },        30)

    print('', colours.system)
    const colour = failed > 0 ? colours.error : colours.system
    print(`${passed} passed, ${failed} failed.`, colour)
}
