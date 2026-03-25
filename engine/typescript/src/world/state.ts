// world/state.ts
// Global state flags.
// State.set(key, value), State.get(key), State.reset()

const flags: Record<string, unknown> = {}

export const State = {
    set(key: string, value: unknown): void {
        flags[key] = value
    },
    get(key: string): unknown {
        return flags[key]
    },
    reset(): void {
        for (const k of Object.keys(flags)) delete flags[k]
    },
}
