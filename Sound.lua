-- Whispy - Sound.lua
-- Alert sounds for incoming and outgoing whispers.
--
-- Modelled on WIM's Sounds module: one configurable sound per event (incoming,
-- outgoing, plus a special one for Battle.net whispers) and an option to force
-- the sound through when the game's sound is switched off entirely. Unlike WIM
-- we play Blizzard's own SOUNDKIT entries rather than shipping audio files, so
-- there is no media library to depend on and nothing extra to install. If
-- LibSharedMedia-3.0 happens to be loaded anyway (WIM and SharedMedia both
-- bundle it), every sound registered there is offered too -- that list is
-- exactly where WIM's picker gets its entries from.

local addonName, ns = ...

--=========================================================================
-- The built-in picker list
--
-- `id` is a fallback for clients whose SOUNDKIT table lacks the key; the
-- numeric ids themselves are stable across builds. `grp` is the locale key
-- of the section header the sound is listed under; sounds sharing a `grp`
-- must be contiguous.
--=========================================================================
local SOUNDS = {
    -- alerts
    { key = "TELL_MESSAGE",                 id = 3081,  label = "sndTell",        grp = "sndGrpAlerts" },
    { key = "UI_BNET_TOAST",                id = 18019, label = "sndBnetToast",   grp = "sndGrpAlerts" },
    { key = "GM_CHAT_WARNING",              id = 15273, label = "sndGMChat",      grp = "sndGrpAlerts" },
    { key = "UI_RAID_BOSS_WHISPER_WARNING", id = 37666, label = "sndBossWhisper", grp = "sndGrpAlerts" },
    { key = "RAID_BOSS_EMOTE_WARNING",      id = 12197, label = "sndBossEmote",   grp = "sndGrpAlerts" },
    { key = "RAID_WARNING",                 id = 8959,  label = "sndWarning",     grp = "sndGrpAlerts" },
    { key = "READY_CHECK",                  id = 8960,  label = "sndReady",       grp = "sndGrpAlerts" },
    { key = "ALARM_CLOCK_WARNING_1",        id = 18871, label = "sndAlarm1",      grp = "sndGrpAlerts" },
    { key = "ALARM_CLOCK_WARNING_2",        id = 12867, label = "sndAlarm2",      grp = "sndGrpAlerts" },
    { key = "ALARM_CLOCK_WARNING_3",        id = 12889, label = "sndAlarm",       grp = "sndGrpAlerts" },
    { key = "TUTORIAL_POPUP",               id = 7355,  label = "sndTutorial",    grp = "sndGrpAlerts" },

    -- chimes & toasts
    { key = "AUCTION_WINDOW_OPEN",                id = 5274,  label = "sndBell",        grp = "sndGrpToasts" },
    { key = "MAP_PING",                           id = 3175,  label = "sndPing",        grp = "sndGrpToasts" },
    { key = "IG_PLAYER_INVITE",                   id = 880,   label = "sndInvite",      grp = "sndGrpToasts" },
    { key = "UI_AUTO_QUEST_COMPLETE",             id = 23404, label = "sndQuestDone",   grp = "sndGrpToasts" },
    { key = "IG_QUEST_LIST_COMPLETE",             id = 878,   label = "sndQuestTurnIn", grp = "sndGrpToasts" },
    { key = "UI_EPICLOOT_TOAST",                  id = 31578, label = "sndEpicLoot",    grp = "sndGrpToasts" },
    { key = "UI_LEGENDARY_LOOT_TOAST",            id = 63971, label = "sndLegendary",   grp = "sndGrpToasts" },
    { key = "UI_PERSONAL_LOOT_BANNER",            id = 50893, label = "sndLootBanner",  grp = "sndGrpToasts" },
    { key = "UI_DIG_SITE_COMPLETION_TOAST",       id = 38326, label = "sndDigsite",     grp = "sndGrpToasts" },
    { key = "UI_GARRISON_TOAST_MISSION_COMPLETE", id = 44294, label = "sndMission",     grp = "sndGrpToasts" },
    { key = "UI_GARRISON_TOAST_FOLLOWER_GAINED",  id = 44296, label = "sndFollower",    grp = "sndGrpToasts" },
    { key = "UI_GARRISON_TOAST_INVASION_ALERT",   id = 44292, label = "sndInvasion",    grp = "sndGrpToasts" },
    { key = "UI_ORDERHALL_TALENT_READY_TOAST",    id = 73280, label = "sndTalent",      grp = "sndGrpToasts" },
    { key = "UI_WORLDQUEST_COMPLETE",             id = 73277, label = "sndWorldQuest",  grp = "sndGrpToasts" },
    { key = "UI_CHALLENGES_NEW_RECORD",           id = 33338, label = "sndRecord",      grp = "sndGrpToasts" },
    { key = "UI_71_SOCIAL_QUEUEING_TOAST",        id = 79739, label = "sndSocialQueue", grp = "sndGrpToasts" },
    { key = "UI_GROUP_FINDER_RECEIVE_APPLICATION",id = 47615, label = "sndApplication", grp = "sndGrpToasts" },
    { key = "UI_SCENARIO_STAGE_END",              id = 31757, label = "sndScenario",    grp = "sndGrpToasts" },
    { key = "UI_PET_BATTLES_TRAP_READY",          id = 28814, label = "sndTrap",        grp = "sndGrpToasts" },
    { key = "UI_POWER_AURA_GENERIC",              id = 23287, label = "sndAura",        grp = "sndGrpToasts" },

    -- queues & PvP
    { key = "LFG_REWARDS",       id = 17316, label = "sndLFGReward",  grp = "sndGrpQueues" },
    { key = "LFG_ROLE_CHECK",    id = 17317, label = "sndRoleCheck",  grp = "sndGrpQueues" },
    { key = "LFG_DENIED",        id = 17341, label = "sndDenied",     grp = "sndGrpQueues" },
    { key = "PVP_ENTER_QUEUE",   id = 8458,  label = "sndQueueEnter", grp = "sndGrpQueues" },
    { key = "PVP_THROUGH_QUEUE", id = 8459,  label = "sndQueuePop",   grp = "sndGrpQueues" },

    -- quiet & quirky
    { key = "IG_MAINMENU_OPTION_CHECKBOX_ON", id = 856,   label = "sndClick",      grp = "sndGrpMisc" },
    { key = "IG_MAINMENU_OPTION",             id = 852,   label = "sndMenuClick",  grp = "sndGrpMisc" },
    { key = "U_CHAT_SCROLL_BUTTON",           id = 1115,  label = "sndChatScroll", grp = "sndGrpMisc" },
    { key = "LOOT_WINDOW_COIN_SOUND",         id = 120,   label = "sndCoins",      grp = "sndGrpMisc" },
    { key = "FISHING_REEL_IN",                id = 3407,  label = "sndBobber",     grp = "sndGrpMisc" },
    { key = "ITEM_REPAIR",                    id = 7994,  label = "sndAnvil",      grp = "sndGrpMisc" },
    { key = "JEWEL_CRAFTING_FINALIZE",        id = 10590, label = "sndJewel",      grp = "sndGrpMisc" },
    { key = "UI_MISSION_SUCCESS_CHEERS",      id = 74702, label = "sndCheers",     grp = "sndGrpMisc" },
    { key = "MURLOC_AGGRO",                   id = 416,   label = "sndMurloc",     grp = "sndGrpMisc" },
}
ns.SOUNDS = SOUNDS

local byKey = {}
for _, s in ipairs(SOUNDS) do byKey[s.key] = s end

--=========================================================================
-- LibSharedMedia (optional)
--
-- Sounds picked from here are stored as "LSM:<name>" so they can never
-- collide with a SOUNDKIT key. Looked up lazily each time, so it works no
-- matter which addon provides the library or when it loads.
--=========================================================================
local function GetLSM()
    local LibStub = _G.LibStub
    return LibStub and LibStub.GetLibrary and LibStub:GetLibrary("LibSharedMedia-3.0", true)
end

local function LSMName(key)
    return type(key) == "string" and key:match("^LSM:(.+)$")
end

-- The full picker menu: built-in sounds under their section headers, then
-- whatever LibSharedMedia has. Entries are { header = text } or
-- { key = storedKey, text = displayName }.
function ns.SoundMenu()
    local menu = {}
    local lastGrp
    for _, s in ipairs(SOUNDS) do
        if s.grp ~= lastGrp then
            menu[#menu + 1] = { header = ns.T(s.grp) }
            lastGrp = s.grp
        end
        menu[#menu + 1] = { key = s.key, text = ns.T(s.label) }
    end

    local lsm = GetLSM()
    if lsm then
        local names = {}
        for _, name in ipairs(lsm:List(lsm.MediaType.SOUND)) do
            -- "None" is LSM's silent placeholder, not a real sound
            if name ~= "None" then names[#names + 1] = name end
        end
        if #names > 0 then
            table.sort(names)
            menu[#menu + 1] = { header = ns.T("sndGrpShared") }
            for _, name in ipairs(names) do
                menu[#menu + 1] = { key = "LSM:" .. name, text = name }
            end
        end
    end
    return menu
end

-- Display name of a stored sound key (falls back to the first entry).
function ns.SoundLabel(key)
    local name = LSMName(key)
    if name then return name end
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
    if ns.db and ns.db.sound and ns.db.sound.force then ForceSoundOn() end

    local name = LSMName(key)
    if name then
        local lsm = GetLSM()
        local path = lsm and lsm:Fetch(lsm.MediaType.SOUND, name, true)
        if type(path) == "string" and path ~= "" then
            PlaySoundFile(path, "Master")
            return
        end
        -- the addon that provided the sound is gone; fall through to default
    end

    local s = byKey[key] or SOUNDS[1]
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
