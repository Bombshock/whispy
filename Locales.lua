local _, ns = ...

--=========================================================================
-- Translations
--
-- One table per client locale, keyed exactly like ns.strings in Core.lua.
-- Missing keys fall back to the English source, so a partial table is fine.
-- This file must stay UTF-8 (no BOM) or the umlauts will render as mojibake.
--=========================================================================

ns.locales.deDE = {
    recentChats = "Letzte Chats",
    allChats    = "Alle Chats",
    noChats     = "Noch keine Chats",
    today       = "Heute",
    typeHint    = "Nachricht eingeben, Enter zum Senden",
    now         = "jetzt",
    tipLeft     = "|cffaaaaaaLinksklick:|r letzte Chats",
    tipRight    = "|cffaaaaaaRechtsklick:|r Verlauf & Optionen",
    tipDrag     = "|cffaaaaaaZiehen:|r Button verschieben",
    tipUnread   = "|cffff6666%d ungelesen|r",

    btnInvite     = "Einladen",
    btnIgnore     = "Ignorieren",
    tipInvite     = "%s in die Gruppe einladen",
    tipIgnore     = "%s ignorieren und dieses Fenster schließen",
    confirmIgnore = "%s ignorieren? Du erhältst dann keine Flüsternachrichten mehr von dieser Person.",
    inviteOffline = "%s ist nicht in World of Warcraft online.",
    ignoredNow    = "%s wird jetzt ignoriert.",

    -- German writes the day first and drops the comma
    dateFmt      = "%d. %B %Y",
    dateFmtShort = "%d. %b",

    unitMin     = "m",
    unitHour    = "h",
    unitDay     = "T",

    stateOn     = "AN",
    stateOff    = "AUS",
    stateShown  = "eingeblendet",
    stateHidden = "ausgeblendet",

    cmdHeader   = "Befehle:",
    helpOpen    = "Flüsterfenster öffnen",
    helpToggle  = "Umleitung von Flüsternachrichten an/aus",
    helpSound   = "Ton bei eingehendem Flüstern an/aus",
    helpOptions = "Optionsfenster öffnen",
    helpList    = "offene Unterhaltungen auflisten",
    helpClear   = "Verlauf einer Unterhaltung löschen",
    helpClearAll= "gesamten gespeicherten Verlauf löschen",
    helpChats   = "vollständige Chatliste öffnen",
    helpMinimap = "Minikarten-Button ein-/ausblenden",
    helpTest    = "simulierte Beispielunterhaltung abspielen",
    helpSim     = "eine gefälschte eingehende Flüsternachricht einfügen",

    menuHistory = "Verlauf",
    menuOptions = "Optionen",

    optTitle      = "Whispy-Optionen",
    optGeneral    = "Allgemein",
    optRouting    = "Flüsternachrichten in Whispy anzeigen",
    optMinimapBtn = "Minikarten-Button anzeigen",
    optSounds     = "Töne",
    optSndIn      = "Ton abspielen, wenn eine Nachricht eintrifft",
    optSndBnet    = "Eigener Ton für Battle.net-Nachrichten",
    optSndOut     = "Ton abspielen, wenn du eine Nachricht sendest",
    optSndForce   = "Töne erzwingen, wenn der Spielton aus ist",
    optPreview    = "Diesen Ton anhören",

    sndTell     = "Flüstern",
    sndReady    = "Bereitschaft",
    sndWarning  = "Raidwarnung",
    sndAlarm    = "Wecker",
    sndBell     = "Glocke",
    sndPing     = "Karten-Ping",
    sndClick    = "Klick",
    sndInvite   = "Gruppeneinladung",
    sndMurloc   = "Murloc",

    minimapState = "Minikarten-Button %s",
    routingState = "Flüsterumleitung %s",
    soundState   = "Ton bei eingehenden Nachrichten %s",
    clearedFor   = "Verlauf für %s gelöscht.",
    usageClear   = "Verwendung: /whispy clear <Name>",
    wipedAll     = "Gesamter Verlauf gelöscht.",
    usageSim     = "Verwendung: /whispy sim <Name> <Text>",
    combatDefer  = "Im Kampf -- %s wird nach Kampfende geöffnet.",
    noOpenConvos = "Keine offenen Unterhaltungen.",
    demoRunning  = "Beispielunterhaltung läuft (simuliert, es wird nichts gesendet)...",
    ssOff        = "Screenshot-Modus %s -- deine Chats sind zurück.",
}
