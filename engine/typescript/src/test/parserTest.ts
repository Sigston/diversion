// test/parserTest.ts
// TypeScript port of test/parser_test.lua.
// Runs in the browser via main.ts on page load.

import { process } from '../parser/index.ts'
import { World }   from '../world/world.ts'

type PrintFn = (text: string, colour: string) => void

export function runTests(print: PrintFn, colours: Record<string, string>): void {
    World.reset()
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

    print('', colours.system)
    const colour = failed > 0 ? colours.error : colours.system
    print(`${passed} passed, ${failed} failed.`, colour)
}
