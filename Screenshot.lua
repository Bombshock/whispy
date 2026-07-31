-- Chaty - Screenshot.lua
-- Presentation mode for captures. Pins the UI to English, swaps the stored
-- history for a generated sample set, and opens a few conversations so the
-- screen is populated. Toggling back restores the real data untouched; so
-- does logging out, so the sample set can never reach SavedVariables.

local addonName, ns = ...

--=========================================================================
-- Deterministic RNG -- Park-Miller (16807 / 2^31-1), seeded from a constant,
-- so the generated conversations look scattered but come out identical on
-- every toggle, character and client. Multiplier and modulus are chosen to
-- keep every intermediate under 2^53, where Lua's doubles are still exact.
-- math.random is deliberately avoided: it shares global state with the rest
-- of the UI, so its sequence depends on whatever ran before us.
--=========================================================================
local SEED = 20240614

local function NewRand(seed)
    local state = seed % 2147483646 + 1      -- must start in [1, m-1]
    return function(n)                       -- integer in [1, n]
        state = (state * 16807) % 2147483647
        return math.floor(state / 2147483647 * n) + 1
    end
end

--=========================================================================
-- Sample cast and dialogue
--=========================================================================
local PEOPLE = {
    { name = "Naowh",     class = "MAGE"        },
    { name = "Miathriel", class = "DRUID"       },
    { name = "Peaches",   isBN = true, presenceID = 90001 },
    { name = "Torvald",   class = "WARRIOR"     },
    { name = "Kelsara",   class = "ROGUE"       },
    { name = "Brumm",     class = "PALADIN"     },
    { name = "Ysolde",    class = "PRIEST"      },
    { name = "Vexhowl",   class = "WARLOCK"     },
}

local THEM = {
    "hey, free for a +18 tonight?",
    "ty for the run earlier, that trinket carried",
    "invite when you're ready",
    "still short a healer for the last two keys",
    "did you see the new tier bonus? it's absurd",
    "we're 3/8 mythic, might push tonight",
    "can you craft me a spark weapon? i have the mats",
    "omw, just repairing",
    "one sec, phone",
    "sold! thanks",
    "raid got moved to 20:30",
    "grats on the mount btw",
    "i'll bring the feast",
    "you still on your warrior?",
}

local YOU = {
    "yeah give me 10 min",
    "sure, sending invite now",
    "sounds good",
    "i can heal, just need to swap spec",
    "nice, gz",
    "mats are in the guild bank",
    "can't tonight sorry, work",
    "ping me when you're on",
    "ok see you there",
    "that was a fun run :)",
    "anytime",
    "switching to my alt, one moment",
}

local STEPS = { 40, 65, 95, 150, 260, 420, 900 }              -- gap inside a chat
local GAPS  = { 1800, 5400, 12000, 30000, 61000, 96000, 140000 }  -- gap between chats

-- Draw a line the conversation hasn't used yet, so nobody repeats themselves
-- within one window. The pools are larger than the longest conversation, so
-- the retry loop always terminates well before the cap.
local function PickLine(rnd, pool, used)
    for _ = 1, 20 do
        local text = pool[rnd(#pool)]
        if not used[text] then
            used[text] = true
            return text
        end
    end
    return pool[rnd(#pool)]
end

-- Build the sample history into the (already emptied) db tables.
-- Returns the conversation keys, newest first.
local function BuildSampleHistory()
    local rnd  = NewRand(SEED)
    local db   = ns.db
    local keys = {}

    -- The newest line lands a couple of minutes ago and each conversation is
    -- pushed further back, so the chat list shows a believable spread of
    -- "now / 20m / 3h / 2d" stamps and the windows get date dividers.
    local endAt = time() - 120

    for _, person in ipairs(PEOPLE) do
        local info = { name = person.name, isBN = person.isBN, presenceID = person.presenceID }
        local key  = ns.MakeKey(info)
        local n    = 3 + rnd(6)                      -- 4..9 messages

        -- Walk backwards so the newest line sits exactly on endAt.
        local stamps, t = {}, endAt
        for i = n, 1, -1 do
            stamps[i] = t
            t = t - STEPS[rnd(#STEPS)]
        end

        -- Usually they opened the conversation, occasionally you did.
        local list = {}
        local dir  = (rnd(4) == 1) and "out" or "in"
        local used = { [THEM] = {}, [YOU] = {} }
        for i = 1, n do
            if i > 1 and rnd(10) <= 8 then           -- mostly alternate, sometimes double up
                dir = (dir == "in") and "out" or "in"
            end
            local pool = (dir == "in") and THEM or YOU
            local text = PickLine(rnd, pool, used[pool])
            list[i] = {
                t    = stamps[i],
                dir  = dir,
                who  = (dir == "in") and person.name or nil,
                text = text,
            }
        end

        db.history[key] = list
        db.meta[key] = {
            name       = person.name,
            isBN       = person.isBN,
            presenceID = person.presenceID,
            class      = person.class,
        }
        keys[#keys + 1] = key

        endAt = stamps[1] - GAPS[rnd(#GAPS)]
    end

    return keys
end

--=========================================================================
-- Toggle
--=========================================================================
local saved       -- { history =, meta = } while the mode is active, else nil
local OPEN_COUNT = 3   -- conversations opened automatically on enable

-- Put the player's own data back exactly as it was.
local function Restore()
    if not saved then return end
    ns.db.history, ns.db.meta = saved.history, saved.meta
    saved = nil
    ns.screenshot   = nil
    ns.forceEnglish = nil
end

function ns.SetScreenshotMode(on)
    if not ns.db then return end
    on = on and true or false
    if on == (saved ~= nil) then return end

    if on then
        saved = { history = ns.db.history, meta = ns.db.meta }
        ns.db.history, ns.db.meta = {}, {}
        ns.screenshot   = true
        ns.forceEnglish = true

        local keys = BuildSampleHistory()
        ns.HideAllWindows()
        ns.ReloadAllWindows()
        ns.RefreshChatLists()

        -- Oldest first, so the most recent conversation ends up on top and
        -- keeps the keyboard focus.
        for i = math.min(OPEN_COUNT, #keys), 1, -1 do
            ns.OpenFromKey(keys[i])
        end
        -- Deliberately silent: a chat line here would land in the capture.
    else
        ns.HideAllWindows()
        Restore()
        ns.ReloadAllWindows()
        ns.RefreshChatLists()
        ns.Print("screenshot mode |cffff6666OFF|r -- your chats are back.")
    end
end

-- Never let the sample data be written to SavedVariables.
local guard = CreateFrame("Frame")
guard:RegisterEvent("PLAYER_LOGOUT")
guard:SetScript("OnEvent", Restore)
