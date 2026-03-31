// world/settings.ts
//
// Engine-level settings loaded from settings.json at startup.
// Unlike State, settings are configuration rather than game state —
// they are not saved/restored and survive World.reset().
//
// API:
//   Settings.load(obj)   called by the loader with the parsed JSON
//   Settings.get(key)    returns the setting value, or the default if unset
//   Settings.reset()     restores defaults (called between test runs)

const defaults: Record<string, unknown> = {
    doorsCloseOnExit: true,
    integrityCheck:   true,
}

let data: Record<string, unknown> = {}

export const Settings = {
    load(raw: Record<string, unknown>): void {
        data = raw ?? {}
    },

    get(key: string): unknown {
        if (key in data) return data[key]
        return defaults[key]
    },

    reset(): void {
        data = {}
    },
}
