// parser/tokeniser.ts
// See engine/lua/parser/tokeniser.lua for documentation.

export function tokenise(input: string): string[] {
    return input
        .toLowerCase()
        .replace(/[^a-z0-9\s]/g, '')
        .trim()
        .split(/\s+/)
        .filter(t => t.length > 0)
}
