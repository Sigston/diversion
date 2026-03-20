-- lexicon/verbs.lua
--
-- The verb lexicon. Maps every canonical verb to:
--
--   synonyms     — all words/phrases the player might type for this verb.
--                  The canonical verb itself must be in this list.
--   resolveObj   — true if the resolver should look for an in-scope object.
--                  false for verbs that don't reference objects (look, inventory)
--                  or where the "object" is a direction word (go).
--   resolveFirst — for two-object verbs: which object to resolve first.
--                  "iobj" (indirect) is the default per the architecture.
--                  "dobj" (direct) for verbs where the direct object must
--                  be known first to make sense of the indirect (e.g. unlock).
--                  Omit for single-object verbs.
--
-- The tagger uses this table to normalise synonyms to canonical verbs.
-- The resolver uses resolveObj and resolveFirst.
-- Everything downstream only ever sees canonical verb strings.

local Verbs = {

    look = {
        synonyms    = { "look", "l" },
        resolveObj  = false,    -- "look" alone describes the room; no object
    },

    examine = {
        synonyms    = { "examine", "x", "inspect", "describe", "read",
                        "look at" },
        resolveObj  = true,
        resolveFirst = "dobj",
    },

    inventory = {
        synonyms    = { "inventory", "i", "inv" },
        resolveObj  = false,    -- lists what you're carrying; no object
    },

    take = {
        synonyms    = { "take", "get", "pick up", "grab", "acquire" },
        resolveObj  = true,
        resolveFirst = "dobj",
    },

    drop = {
        synonyms    = { "drop", "put down", "leave", "discard" },
        resolveObj  = true,
        resolveFirst = "dobj",
    },

    go = {
        synonyms    = { "go", "walk", "move", "travel", "head", "enter" },
        resolveObj  = false,    -- direction is a word, not an in-scope object
    },

    put = {
        synonyms    = { "put", "place", "insert", "set", "lay" },
        resolveObj  = true,
        resolveFirst = "iobj",  -- resolve the container first, then the thing
    },

    unlock = {
        synonyms    = { "unlock" },
        resolveObj  = true,
        resolveFirst = "dobj",  -- must know what we're unlocking before
    },                          -- we can make sense of "with the key"

    open = {
        synonyms    = { "open" },
        resolveObj  = true,
        resolveFirst = "dobj",
    },

    close = {
        synonyms    = { "close", "shut" },
        resolveObj  = true,
        resolveFirst = "dobj",
    },

    light = {
        synonyms    = { "light", "ignite", "kindle", "burn" },
        resolveObj  = true,
        resolveFirst = "dobj",
    },

    push = {
        synonyms    = { "push", "shove", "press" },
        resolveObj  = true,
        resolveFirst = "dobj",
    },

    search = {
        synonyms    = { "search", "rummage" },
        resolveObj  = true,
        resolveFirst = "dobj",
    },
}

-- Build a reverse lookup: word -> canonical verb.
-- e.g. synonymMap["get"] = "take", synonymMap["x"] = "examine"
-- The tagger uses this to normalise player input.
-- We build it once here so the tagger doesn't have to loop every time.
local synonymMap = {}
for canonical, entry in pairs(Verbs) do
    for _, word in ipairs(entry.synonyms) do
        synonymMap[word] = canonical
    end
end

Verbs.synonymMap = synonymMap

return Verbs
