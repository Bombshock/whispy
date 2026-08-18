-- Whispy - Sound.lua
-- Alert sounds for incoming and outgoing whispers.
--
-- Modelled on WIM's Sounds module: one configurable sound per event (incoming,
-- outgoing, plus a special one for Battle.net whispers) and an option to force
-- the sound through when the game's sound is switched off entirely. Unlike WIM
-- we play Blizzard's own SOUNDKIT entries rather than shipping audio files, so
-- there is no media library to depend on and nothing extra to install.

local addonName, ns = ...

--=========================================================================
-- The picker list
--
-- `id` is a fallback for clients whose SOUNDKIT table lacks the key; the
-- numeric ids themselves are stable across builds.
--=========================================================================
local SOUNDS = {
    { key = "TELL_MESSAGE",                   id = 3081,  label = "sndTell"   },
    { key = "READY_CHECK",                    id = 8960,  label = "sndReady"  },
    { key = "RAID_WARNING",                   id = 8959,  label = "sndWarning"},
    { key = "ALARM_CLOCK_WARNING_3",          id = 12867, label = "sndAlarm"  },
    { key = "AUCTION_WINDOW_OPEN",            id = 5274,  label = "sndBell"   },
    { key = "MAP_PING",                       id = 3175,  label = "sndPing"   },
    { key = "IG_MAINMENU_OPTION_CHECKBOX_ON", id = 856,   label = "sndClick"  },
    { key = "IG_PLAYER_INVITE",               id = 880,   label = "sndInvite" },
    { key = "MURLOC_AGGRO",                   id = 416,   label = "sndMurloc" },
}
ns.SOUNDS = SOUNDS

local byKey = {}
for _, s in ipairs(SOUNDS) do byKey[s.key] = s end

-- Display name of a stored sound key (falls back to the first entry).
function ns.SoundLabel(key)
    return ns.T((byKey[key] or SOUNDS[1]).label)
end

--=========================================================================
-- Forcing sound through
--
-- WIM flips Sound_EnableAllSound on for a moment and puts it back afterwards;
-- we do the same, remembering the player's own setting rather than tracking
-- CVAR_UPDATE, since the override only lives for a second.
--=========================================================================
local RESTORE_DELAY = 1
local savedCVar

local holder = CreateFrame("Frame")
holder:Hide()
holder:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed >= RESTORE_DELAY then
        self:Hide()
        SetCVar("Sound_EnableAllSound", savedCVar or "1")
    end
end)

local function ForceSoundOn()
    if holder:IsShown() then       -- already holding it open; just extend
        holder.elapsed = 0
        return
    end
    savedCVar = GetCVar("Sound_EnableAllSound")
    if savedCVar == "0" then
        SetCVar("Sound_EnableAllSound", "1")
        holder.elapsed = 0
        holder:Show()
    end
end

--=========================================================================
-- Playback
--=========================================================================
function ns.PlayWhispySound(key)
    local s = byKey[key] or SOUNDS[1]
    if ns.db and ns.db.sound and ns.db.sound.force then ForceSoundOn() end
    PlaySound(SOUNDKIT[s.key] or s.id, "Master")
end

-- kind: "in" | "out". info is the conversation identity, for the Battle.net rule.
function ns.AlertSound(kind, info)
    local s = ns.db and ns.db.sound
    if not s then return end

    if kind == "out" then
        if s.outgoing then ns.PlayWhispySound(s.outgoingKey) end
        return
    end

    if not s.incoming then return end
    if s.bnet and info and info.isBN then
        ns.PlayWhispySound(s.bnetKey)
    else
        ns.PlayWhispySound(s.incomingKey)
    end
end
