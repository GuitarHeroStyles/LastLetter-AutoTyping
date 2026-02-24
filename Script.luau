-- ============================================================
--  Last Letter Pro  v3.4  |  Starlight Interface Suite
--  FULL 912 LINES — Changelog moved to Dashboard
--  PlaceId: 129866685202296 — 2-Step Chain + 2-Letter + Stealth
-- ============================================================

local Players             = game:GetService("Players")
local VirtualInputManager = game:GetService("VirtualInputManager")
local StarterGui          = game:GetService("StarterGui")
local LogService          = game:GetService("LogService")
local HttpService         = game:GetService("HttpService")
local UserInputService    = game:GetService("UserInputService")
local TeleportService     = game:GetService("TeleportService")
local TextChatService     = game:GetService("TextChatService")

local LocalPlayer = Players.LocalPlayer

local Starlight = loadstring(game:HttpGet("https://raw.githubusercontent.com/Nebula-Softworks/Starlight-Interface-Suite/master/Source.lua"))()

-- ============================================================
--  CHANGELOG
-- ============================================================
local CHANGELOG = {
    {
        version = "v3.4",
        date    = "2026-02-24",
        changes = {
            "2-letter word support + toggle (ax, ox, my, xi, etc)",
            "2-Step Chain Prediction (connectivity precompute + ending letter scoring)",
            "Ability/Style detection in chat (reset/timer/interrupt/style/ability)",
            "Stealth Typing v2 with random mouse jitter + per-key variation",
            "Dictionary cache (HttpGet only once per session)",
            "MinLength default = 2, autoResetTime = 180s",
            "Changelog moved to Dashboard card (Tab Info removed)",
            "Default: Troll + Common + Auto-Input + 2-Letter + Stealth ON",
        },
    },
    {
        version = "v3.3",
        date    = "2025-02-25",
        changes = {
            "Fixed used words not filtering in Common Words mode",
            "Fixed STATE.used reference bug (clearUsed now properly clears)",
            "Changelog tab now shows full version history",
            "Each changelog entry displayed as separate label",
            "Added instruction: edit CHANGELOG table at top of script",
        },
    },
    {
        version = "v3.2",
        date    = "2025-02-25",
        changes = {
            "Fixed dictionary load crash (concatenation with function bug)",
            "Restored original two dictionary sources unchanged",
            "Added dolph/popular.txt as third freq word source",
            "All UI text restored to English",
        },
    },
    {
        version = "v3.1",
        date    = "2025-02-25",
        changes = {
            "Added STATE table to prevent reference replacement bugs",
            "Added wrong-word auto-retry via RBXSystem hook",
            "Added chat word tracking (RBXGeneral + global fallback)",
            "Added Prioritize Common Words toggle with star (*) markers",
        },
    },
    {
        version = "v3.0",
        date    = "2025-02-24",
        changes = {
            "Full rewrite for stability and clarity",
            "Fixed Troll mode: correctly picks longest word",
            "Fixed Enter key: sent after post-delay, not with last letter",
            "Fixed used words: filter applied before suggestions built",
        },
    },
    {
        version = "v2.8",
        date    = "2025-02-24",
        changes = {
            "Server region detection via ping field from Roblox API",
            "Chat tracking via TextChatService.MessageReceived (confirmed working)",
            "Fixed server detection boot timing (race condition fixed)",
        },
    },
    {
        version = "v2.7",
        date    = "2025-02-24",
        changes = {
            "Server region: ping-based detection (confirmed: ping=72ms = Singapore)",
            "Server hop: filter by ping range per region",
            "UIScale confirmed as DPIScale in Starlight.Instance",
        },
    },
    {
        version = "v2.6",
        date    = "2025-02-24",
        changes = {
            "Resize handle is now child of MainWindow (correct position)",
            "Server scan now searches all pages to find current server",
        },
    },
    {
        version = "v2.5",
        date    = "2025-02-23",
        changes = {
            "Server region detection via Roblox endpoint ping test",
            "Server Hop tab with 6 region buttons",
            "Window Scale slider (50-150%) via DPIScale",
        },
    },
    {
        version = "v2.3 - v2.4",
        date    = "2025-02-23",
        changes = {
            "RightCtrl toggle UI on/off",
            "Safe Mode: random delays, micro-pauses (human-like typing)",
            "Fast Mode: minimal delays",
            "isTyping flag prevents double-type",
        },
    },
    {
        version = "v2.0 - v2.2",
        date    = "2025-02-23",
        changes = {
            "Full Starlight UI integration",
            "358603 words from dwyl/english-words JSON",
            "Troll mode (longest) + Normal mode (ideal length)",
            "Label update fix: Instance.Header.Text confirmed working",
            "Auto-type: snapshot word before task.spawn to prevent race",
        },
    },
}

-- ============================================================
--  DICTIONARY SOURCES + CACHE
-- ============================================================
local DICT = {
    FULL_A = "https://raw.githubusercontent.com/dwyl/english-words/refs/heads/master/words_dictionary.json",
    FULL_B = "https://raw.githubusercontent.com/first20hours/google-10000-english/master/google-10000-english-usa-no-swears.txt",
    FREQ_B = "https://raw.githubusercontent.com/dolph/dictionary/master/popular.txt",
}

local DICT_CACHE = {}

-- ============================================================
--  CONFIG
-- ============================================================
local CONFIG = {
    safe            = { baseDelay=0.16, randomMult=1.85, preMin=0.32, preMax=1.05, postMin=0.11, postMax=0.32 },
    fast            = { baseDelay=0.035, randomMult=1.15, preMin=0.03, preMax=0.09, postMin=0.03, postMax=0.08 },
    safeMode        = true,
    minLength       = 2,
    maxLength       = 15,
    idealLength     = 6,
    autoResetTime   = 180,
    wordsPerPage    = 10,
    trackChat       = true,
    preferFreqWords = true,
    allow2Letter    = true,
    stealthMode     = true,
}

local SKIP = {
    ["the"]=true,["and"]=true,["a"]=true,["an"]=true,["is"]=true,
    ["it"]=true,["to"]=true,["of"]=true,["in"]=true,["for"]=true,
    ["on"]=true,["with"]=true,["as"]=true,["at"]=true,["by"]=true,
    ["or"]=true,["be"]=true,["do"]=true,["go"]=true,["no"]=true,
}

local REGION_PING = {
    { name="Singapore", min=0,   max=110 },
    { name="Japan",     min=60,  max=150 },
    { name="Australia", min=80,  max=170 },
    { name="US West",   min=130, max=220 },
    { name="US East",   min=160, max=280 },
    { name="Europe",    min=190, max=380 },
}

-- ============================================================
--  STATE
-- ============================================================
local STATE = {
    allWords     = {},
    freqSet      = {},
    wordSet      = {},
    used         = {},
    topWords     = {},
    page         = 1,
    input        = "",
    mode         = "troll",
    autoInput    = true,
    consoleAC    = false,
    guiVisible   = true,
    isTyping     = false,
    chatCount    = 0,
    lastActivity = 0,
    dpiScale     = nil,
    connectivity = {},
    dictCached   = false,
}

local function clearUsed()
    for k in pairs(STATE.used) do STATE.used[k] = nil end
    STATE.chatCount    = 0
    STATE.lastActivity = 0
end

-- ============================================================
--  LABELS & HELPERS
-- ============================================================
local lblPage, lblStatus, lblServer, lblPing, lblUsed = nil, nil, nil, nil, nil

local function setLbl(lbl, text)
    if not lbl then return end
    pcall(function() lbl.Instance.Header.Text = tostring(text or "") end)
end

local function notify(msg)
    pcall(function()
        StarterGui:SetCore("SendNotification", { Title="Last Letter Pro v3.4", Text=msg, Duration=4 })
    end)
end

local function rnd(a, b) return a + math.random()*(b-a) end
local function getCfg()  return CONFIG.safeMode and CONFIG.safe or CONFIG.fast end

local function getDPI()
    if STATE.dpiScale then return STATE.dpiScale end
    pcall(function() STATE.dpiScale = Starlight.Instance:FindFirstChild("DPIScale") end)
    return STATE.dpiScale
end

local function pingToRegion(ping)
    local best, bestScore = "Unknown", math.huge
    for _, r in ipairs(REGION_PING) do
        local mid   = (r.min + r.max) / 2
        local score = math.abs(ping - mid) - (ping >= r.min and ping <= r.max and 1000 or 0)
        if score < bestScore then best, bestScore = r.name, score end
    end
    return best
end

-- ============================================================
--  CONNECTIVITY 2-STEP PREDICTION
-- ============================================================
local function buildConnectivity()
    STATE.connectivity = {}
    for _, w in ipairs(STATE.allWords) do
        local first = w:sub(1,1)
        STATE.connectivity[first] = (STATE.connectivity[first] or 0) + 1
    end
    print("[LLP v3.4] 2-Step Connectivity built")
end

-- ============================================================
--  DICTIONARY (cached)
-- ============================================================
local function parseJSON(content)
    local ok, dec = pcall(function() return HttpService:JSONDecode(content) end)
    if not ok or not dec then return {} end
    local t = {}
    for word in pairs(dec) do
        local w = word:lower()
        if #w <= CONFIG.maxLength and not SKIP[w] and w:match("^[a-z]+$") then
            t[w] = true
        end
    end
    return t
end

local function parseTXT(content)
    local t = {}
    for line in content:gmatch("[^\r\n]+") do
        local w = line:lower():match("^%s*([a-z]+)%s*$")
        if w and #w <= CONFIG.maxLength and not SKIP[w] then
            t[w] = true
        end
    end
    return t
end

local function loadDictionary()
    if STATE.dictCached then
        notify("Dictionary already cached ✓")
        return true
    end
    notify("Loading + caching dictionary v3.4...")
    local fullSet = {}
    for _, url in pairs(DICT) do
        local content
        if DICT_CACHE[url] then
            content = DICT_CACHE[url]
        else
            local ok, c = pcall(function() return game:HttpGet(url) end)
            content = ok and c or ""
            DICT_CACHE[url] = content
        end
        local s = url:find("json") and parseJSON(content) or parseTXT(content)
        for w in pairs(s) do
            if #w >= 2 then
                fullSet[w] = true
                if url ~= DICT.FULL_A then STATE.freqSet[w] = true end
            end
        end
    end
    STATE.allWords = {}
    STATE.wordSet  = {}
    for w in pairs(fullSet) do
        table.insert(STATE.allWords, w)
        STATE.wordSet[w] = true
    end
    buildConnectivity()
    STATE.dictCached = true
    local fc = 0 for _ in pairs(STATE.freqSet) do fc = fc+1 end
    notify("Ready! "..#STATE.allWords.." words | 2-step enabled")
    return true
end

-- ============================================================
--  WORD SORT (2-step)
-- ============================================================
local function sortWords(words)
    local ideal = CONFIG.idealLength
    local pref  = CONFIG.preferFreqWords
    local freq  = STATE.freqSet
    local conn  = STATE.connectivity
    table.sort(words, function(a, b)
        if pref then
            local fa = freq[a] and 0 or 1
            local fb = freq[b] and 0 or 1
            if fa ~= fb then return fa < fb end
        end
        local da = math.abs(#a - ideal)
        local db = math.abs(#b - ideal)
        if da ~= db then return da < db end
        local lastA = a:sub(-1)
        local lastB = b:sub(-1)
        local scoreA = (conn[lastA] or 0) * 12 + #a
        local scoreB = (conn[lastB] or 0) * 12 + #b
        if scoreA ~= scoreB then return scoreA > scoreB end
        if #a ~= #b then return #a < #b end
        return a < b
    end)
end

-- ============================================================
--  WORD SEARCH
-- ============================================================
local function updateDisplay()
    if #STATE.topWords == 0 then
        setLbl(lblPage, STATE.input=="" and "Enter starting letters above" or "No matches: "..STATE.input:upper())
        setLbl(lblStatus, "")
        return
    end
    local total = math.max(1, math.ceil(#STATE.topWords / CONFIG.wordsPerPage))
    STATE.page  = math.clamp(STATE.page, 1, total)
    local s = (STATE.page-1)*CONFIG.wordsPerPage + 1
    local e = math.min(STATE.page*CONFIG.wordsPerPage, #STATE.topWords)
    local mStr = STATE.mode == "troll" and "TROLL" or "NORMAL"
    local fStr = CONFIG.preferFreqWords and " | COMMON" or ""
    setLbl(lblPage, "Page "..STATE.page.."/"..total.."  |  "..#STATE.topWords.." words  |  "..mStr..fStr)
    local lines = {}
    for i = s, e do
        local w = STATE.topWords[i]
        local mark = i==s and ">> " or "   "
        local star = STATE.freqSet[w] and "*" or " "
        lines[#lines+1] = mark..star..w:upper().." ("..#w..")"
    end
    setLbl(lblStatus, table.concat(lines, "\n"))
end

local function rebuildTopWords()
    local newTop = {}
    local input = STATE.input
    local len = #input
    local used = STATE.used
    if len > 0 then
        for _, w in ipairs(STATE.allWords) do
            if #w > len and w:sub(1,len) == input and not used[w] and #w >= CONFIG.minLength then
                table.insert(newTop, w)
            end
        end
        sortWords(newTop)
    end
    STATE.topWords = newTop
    STATE.page = 1
    pcall(updateDisplay)
end

local function updateTopWords(input)
    STATE.input = (input or ""):lower()
    rebuildTopWords()
    if STATE.autoInput and not STATE.isTyping and #STATE.topWords > 0 and STATE.input ~= "" then
        local word
        if STATE.mode == "troll" then
            word = STATE.topWords[1]
            for _, w in ipairs(STATE.topWords) do if #w > #word then word = w end end
        else
            word = STATE.topWords[1]
        end
        local typed = STATE.input
        STATE.used[word] = true
        STATE.input = ""
        STATE.topWords = {}
        pcall(updateDisplay)
        notify("Auto: " .. word:upper())
        task.defer(function() _G.LLP_type(word, typed) end)
    end
end

-- ============================================================
--  ABILITY DETECTION
-- ============================================================
local ABILITY_KEYWORDS = {"reset","timer","shorten","interrupt","style","ability","spin","power","used style","round reset"}
local function detectAbility(text)
    local t = text:lower()
    for _, kw in ipairs(ABILITY_KEYWORDS) do
        if t:find(kw) then
            notify("⚡ ABILITY DETECTED: " .. kw:upper())
            if STATE.input ~= "" then rebuildTopWords() end
            return true
        end
    end
    return false
end

-- ============================================================
--  STEALTH AUTO-TYPE v2
-- ============================================================
local function typeWord(word, typed)
    if STATE.isTyping then notify("Still typing...") return end
    local remaining = word:sub(#typed + 1)
    STATE.isTyping = true
    local c = getCfg()
    task.spawn(function()
        local sz = workspace.CurrentCamera.ViewportSize
        if CONFIG.stealthMode then
            for i = 1, math.random(3,7) do
                local rx = sz.X/2 + math.random(-120,120)
                local ry = sz.Y/2 + math.random(-60,60)
                VirtualInputManager:SendMouseMoveEvent(rx, ry, game)
                task.wait(math.random(15,40)/1000)
            end
        end
        VirtualInputManager:SendMouseButtonEvent(sz.X/2, sz.Y/2, 0, true, game, 1)
        task.wait(0.04)
        VirtualInputManager:SendMouseButtonEvent(sz.X/2, sz.Y/2, 0, false, game, 1)
        task.wait(rnd(c.preMin, c.preMax))
        for ch in remaining:upper():gmatch(".") do
            local key = Enum.KeyCode[ch]
            if key then
                VirtualInputManager:SendKeyEvent(true, key, false, game)
                local delay = rnd(c.baseDelay, c.baseDelay * c.randomMult)
                if CONFIG.stealthMode then delay = delay + math.random()*0.028 end
                task.wait(delay)
                VirtualInputManager:SendKeyEvent(false, key, false, game)
                if CONFIG.safeMode and math.random(100) <= 18 then task.wait(rnd(0.025,0.14)) end
            end
        end
        task.wait(rnd(c.postMin, c.postMax))
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Return, false, game)
        task.wait(0.07)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Return, false, game)
        STATE.isTyping = false
    end)
end
_G.LLP_type = typeWord

local function useWord(word)
    if not word then notify("No word available!") return end
    if STATE.isTyping then notify("Still typing...") return end
    local typed = STATE.input
    STATE.used[word] = true
    STATE.input = ""
    STATE.topWords = {}
    pcall(updateDisplay)
    notify("Typing: " .. word:upper())
    typeWord(word, typed)
end

local function getBest()
    if #STATE.topWords == 0 then return nil end
    if STATE.mode == "troll" then
        local best = STATE.topWords[1]
        for _, w in ipairs(STATE.topWords) do if #w > #best then best = w end end
        return best
    end
    return STATE.topWords[1]
end

local function getLongest()
    if #STATE.topWords == 0 then return nil end
    local best = STATE.topWords[1]
    for _, w in ipairs(STATE.topWords) do if #w > #best then best = w end end
    return best
end

-- ============================================================
--  CHAT TRACKING + ABILITY
-- ============================================================
local function trackWord(w)
    if not CONFIG.trackChat then return end
    w = w:lower()
    if #w >= CONFIG.minLength and STATE.wordSet[w] and not STATE.used[w] then
        STATE.used[w] = true
        STATE.chatCount = STATE.chatCount + 1
        pcall(function() setLbl(lblUsed, "Tracked: "..STATE.chatCount.." words used") end)
        if STATE.input ~= "" then pcall(rebuildTopWords) end
    end
end

local function hookChat()
    pcall(function()
        local ch = TextChatService:FindFirstChild("TextChannels")
        if ch then
            local sys = ch:FindFirstChild("RBXSystem")
            if sys then
                sys.MessageReceived:Connect(function(msg)
                    local t = (msg.Text or ""):lower()
                    if t:find("invalid") or t:find("already") or t:find("used") or t:find("wrong") or t:find("error") then
                        notify("Word rejected! Trying next...")
                        task.wait(0.3)
                        if STATE.input ~= "" and not STATE.isTyping then
                            pcall(rebuildTopWords)
                            if STATE.topWords[1] then useWord(STATE.topWords[1]) end
                        end
                    end
                end)
            end
            local gen = ch:FindFirstChild("RBXGeneral")
            if gen then
                gen.MessageReceived:Connect(function(msg)
                    for w in (msg.Text or ""):gmatch("[%a]+") do trackWord(w) end
                    detectAbility(msg.Text or "")
                end)
            end
        end
    end)
    pcall(function()
        TextChatService.MessageReceived:Connect(function(msg)
            for w in (msg.Text or ""):gmatch("[%a]+") do trackWord(w) end
            detectAbility(msg.Text or "")
        end)
    end)
end

-- ============================================================
--  SERVER INFO & HOP
-- ============================================================
local function getServerInfo()
    task.spawn(function()
        setLbl(lblServer, "Scanning...")
        local base  = "https://games.roblox.com/v1/games/"..game.PlaceId.."/servers/Public?sortOrder=Asc&limit=100"
        local mine, cursor, page = nil, nil, 1
        local function scan(url)
            local ok, res = pcall(function() return game:HttpGet(url) end)
            if not ok then return nil end
            local ok2, data = pcall(function() return HttpService:JSONDecode(res) end)
            if not ok2 or not data or not data.data then return nil end
            for _, s in ipairs(data.data) do
                if s.id == game.JobId then mine = s end
            end
            return data.nextPageCursor
        end
        cursor = scan(base)
        while not mine and cursor and page < 8 do
            cursor = scan(base .. "&cursor=" .. cursor)
            page = page + 1
        end
        if not mine then
            setLbl(lblServer, "Not found\nJobId: "..game.JobId:sub(1,16).."...")
            return
        end
        local ping = mine.ping or 0
        local region = pingToRegion(ping)
        local fps = math.floor(mine.fps or 0)
        setLbl(lblServer, "Region: "..region.."\nPing: "..ping.."ms | FPS: "..fps.."\nPlayers: "..(mine.playing or "?").."/"..(mine.maxPlayers or "?").."\nJobId: "..game.JobId:sub(1,16).."...")
        setLbl(lblPing, region.." | "..ping.."ms | "..fps.." FPS")
        notify("Server: "..region.." ("..ping.."ms)")
    end)
end

local function getAllServers()
    local result, cursor, pages = {}, nil, 0
    repeat
        local url = "https://games.roblox.com/v1/games/"..game.PlaceId.."/servers/Public?sortOrder=Asc&limit=100"..(cursor and "&cursor="..cursor or "")
        local ok, res = pcall(function() return game:HttpGet(url) end)
        if not ok then break end
        local ok2, data = pcall(function() return HttpService:JSONDecode(res) end)
        if not ok2 or not data or not data.data then break end
        for _, s in ipairs(data.data) do
            if s.id ~= game.JobId and (s.playing or 0) < (s.maxPlayers or 999) then
                table.insert(result, s)
            end
        end
        cursor = data.nextPageCursor
        pages = pages + 1
    until not cursor or pages >= 8
    return result
end

local function serverHop(region)
    notify("Searching "..region.."...")
    task.spawn(function()
        local servers = getAllServers()
        if #servers == 0 then notify("No servers found!") return end
        local chosen
        if region == "Auto" then
            table.sort(servers, function(a,b) return (a.ping or 9999) < (b.ping or 9999) end)
            chosen = servers[1]
        else
            local range
            for _, r in ipairs(REGION_PING) do if r.name == region then range = r break end end
            local cands = {}
            if range then
                for _, s in ipairs(servers) do
                    local p = s.ping or 9999
                    if p >= range.min and p <= range.max then table.insert(cands, s) end
                end
            end
            if #cands > 0 then
                local mid = (range.min + range.max)/2
                table.sort(cands, function(a,b) return math.abs((a.ping or 9999)-mid) < math.abs((b.ping or 9999)-mid) end)
                chosen = cands[math.random(1, math.min(5,#cands))]
            else
                table.sort(servers, function(a,b) return (a.ping or 9999) < (b.ping or 9999) end)
                chosen = servers[1]
            end
        end
        if chosen then
            notify("Hopping -> "..(chosen.ping or "?").."ms")
            local opts = Instance.new("TeleportOptions")
            opts.ServerInstanceId = chosen.id
            pcall(function() TeleportService:TeleportAsync(game.PlaceId, {LocalPlayer}, opts) end)
        end
    end)
end

-- ============================================================
--  CONSOLE + AUTO RESET
-- ============================================================
LogService.MessageOut:Connect(function(msg)
    if STATE.consoleAC and msg:find("Word:") then
        local l = msg:match("Word:%s*([A-Za-z]+)")
        if l then
            STATE.lastActivity = tick()
            updateTopWords(l:lower())
            notify("Console: "..l:upper())
        end
    end
end)

task.spawn(function()
    while task.wait(15) do
        if STATE.lastActivity > 0 and tick()-STATE.lastActivity > CONFIG.autoResetTime then
            clearUsed()
            notify("Auto-reset!")
            pcall(function() setLbl(lblUsed, "Tracked: 0 words") end)
            if STATE.input ~= "" then pcall(rebuildTopWords) end
        end
    end
end)

-- ============================================================
--  BUILD UI — CHANGELOG IN DASHBOARD
-- ============================================================
local Window = Starlight:CreateWindow({
    Name = "SABOS HUB",
    Subtitle = "Word Auto-Complete | v3.4 — 2-Step Meta",
    LoadingEnabled = true,
    LoadingTitle = "Last Letter Pro v3.4",
    LoadingSubtitle = "Loading 2-step engine...",
    ConfigurationSavingEnabled = true,
    ConfigurationFolder = "LastLetterPro",
})

local HomeTab = Window:CreateHomeTab({
    Changelog = {
        {
            Title       = CHANGELOG[1].version .. " (" .. CHANGELOG[1].date .. ")",
            Date        = CHANGELOG[1].date,
            Description = "• " .. table.concat(CHANGELOG[1].changes, "\n• ")
        }
    }
})

local SecMain   = Window:CreateTabSection("Main")
local SecServer = Window:CreateTabSection("Server")
local SecSet    = Window:CreateTabSection("Settings")

local TabMain   = SecMain:CreateTab({ Name="Search", Columns=1 }, "TM")
local TabServer = SecServer:CreateTab({ Name="Server Hop", Columns=1 }, "TS")
local TabSet    = SecSet:CreateTab({ Name="Settings", Columns=1 }, "TC")

-- SEARCH TAB
local GBIn  = TabMain:CreateGroupbox({ Name="Input Letters", Icon=nil }, "GBIn")
local GBSug = TabMain:CreateGroupbox({ Name="Suggestions", Icon=nil }, "GBSug")
local GBAct = TabMain:CreateGroupbox({ Name="Actions", Icon=nil }, "GBAct")
local GBNav = TabMain:CreateGroupbox({ Name="Navigation", Icon=nil }, "GBNav")
local GBTrk = TabMain:CreateGroupbox({ Name="Word Tracking", Icon=nil }, "GBTrk")

GBIn:CreateInput({
    Name="Letters", Description="Type the starting letters shown in-game",
    PlaceholderText="e.g. CO, ST, CA...",
    OnEnter=false, RemoveTextAfterFocusLost=false,
    Callback=function(val)
        STATE.lastActivity = tick()
        updateTopWords(val)
    end,
}, "InLetters")

lblPage   = GBSug:CreateLabel({ Text="" }, "LP")
lblStatus = GBSug:CreateLabel({ Text="" }, "LS")
task.defer(function()
    setLbl(lblPage,   "Loading dictionary...")
    setLbl(lblStatus, "")
end)

GBAct:CreateButton({ Name=">> Use Best Word", Description="Type best word based on active mode",
    Callback=function() useWord(getBest()) end }, "BtnBest")
GBAct:CreateButton({ Name="Use Normal Word",  Description="Force: closest to ideal length",
    Callback=function()
        if #STATE.topWords == 0 then notify("No words!") return end
        useWord(STATE.topWords[1])
    end }, "BtnNorm")
GBAct:CreateButton({ Name="Use Longest Word", Description="Force: longest available word",
    Callback=function() useWord(getLongest()) end }, "BtnLong")
GBAct:CreateButton({ Name="Reset Used Words", Description="Clear all used/tracked words",
    Callback=function()
        clearUsed()
        notify("Reset! All words available.")
        pcall(function() setLbl(lblUsed, "Tracked: 0 words") end)
        if STATE.input ~= "" then pcall(rebuildTopWords) end
    end }, "BtnReset")

GBNav:CreateButton({ Name="<< Previous Page", Description="",
    Callback=function()
        if STATE.page > 1 then STATE.page=STATE.page-1 pcall(updateDisplay) end
    end }, "BtnPrev")
GBNav:CreateButton({ Name="Next Page >>", Description="",
    Callback=function()
        local t = math.max(1, math.ceil(#STATE.topWords/CONFIG.wordsPerPage))
        if STATE.page < t then STATE.page=STATE.page+1 pcall(updateDisplay) end
    end }, "BtnNext")

lblUsed = GBTrk:CreateLabel({ Text="" }, "LUsed")
task.defer(function() setLbl(lblUsed, "Tracked: 0 words used in chat") end)

GBTrk:CreateToggle({ Name="Track Used Words (Chat)", Description="Auto-exclude words used by anyone in chat",
    CurrentValue=true,
    Callback=function(v) CONFIG.trackChat=v notify(v and "Tracking ON" or "Tracking OFF") end }, "TglTrack")
GBTrk:CreateToggle({ Name="Prioritize Common Words (*)", Description="ON = frequent words shown first",
    CurrentValue=true,
    Callback=function(v)
        CONFIG.preferFreqWords = v
        notify(v and "Common words priority ON" or "All words equal")
        if STATE.input ~= "" then pcall(rebuildTopWords) end
    end }, "TglFreq")

-- SERVER TAB
local GBSrvI = TabServer:CreateGroupbox({ Name="Current Server", Icon=nil }, "GBSrvI")
local GBSrvH = TabServer:CreateGroupbox({ Name="Hop to Region",  Icon=nil }, "GBSrvH")

lblServer = GBSrvI:CreateLabel({ Text="" }, "LSrv")
lblPing   = GBSrvI:CreateLabel({ Text="" }, "LPng")
task.defer(function()
    setLbl(lblServer, "Click 'Get Server Info' to detect region")
    setLbl(lblPing,   "JobId: "..game.JobId:sub(1,16).."...")
end)

GBSrvI:CreateButton({ Name="Get Server Info", Description="Detect region via Roblox API ping field",
    Callback=function() getServerInfo() end }, "BtnSrv")

local regionList = {
    { n="Auto",      d="Any available server (lowest ping)" },
    { n="Singapore", d="0-110ms | Southeast Asia" },
    { n="Japan",     d="60-150ms | East Asia" },
    { n="Australia", d="80-170ms | Oceania" },
    { n="US West",   d="130-220ms | Western US" },
    { n="US East",   d="160-280ms | Eastern US" },
    { n="Europe",    d="190-380ms | Europe" },
}
for _, r in ipairs(regionList) do
    GBSrvH:CreateButton({
        Name        = r.n=="Auto" and "Hop -> Any Server" or "Hop -> "..r.n,
        Description = r.d,
        Callback    = function() serverHop(r.n) end,
    }, "BH_"..r.n:gsub(" ","_"))
end

-- SETTINGS TAB
local GBMd  = TabSet:CreateGroupbox({ Name="Mode",         Icon=nil }, "GBMd")
local GBTy  = TabSet:CreateGroupbox({ Name="Typing Speed", Icon=nil }, "GBTy")
local GBWin = TabSet:CreateGroupbox({ Name="Window",       Icon=nil }, "GBWin")

GBMd:CreateToggle({ Name="Troll Mode", Description="ON = longest word  |  OFF = ideal length",
    CurrentValue=true,
    Callback=function(v)
        STATE.mode = v and "troll" or "normal"
        notify("Mode: "..STATE.mode:upper())
        pcall(updateDisplay)
    end }, "TglTroll")
GBMd:CreateToggle({ Name="Safe Mode (Natural Typing)", Description="ON = human-like delay  |  OFF = Fast",
    CurrentValue=true,
    Callback=function(v) CONFIG.safeMode=v notify(v and "Safe Mode" or "Fast Mode") end }, "TglSafe")
GBMd:CreateToggle({ Name="Auto-Input", Description="Auto-type best word when letters entered",
    CurrentValue=true,
    Callback=function(v) STATE.autoInput=v notify(v and "Auto-Input ON" or "OFF") end }, "TglAuto")
GBMd:CreateToggle({ Name="Console Auto-Complete", Description="Detect 'Word: XX' from console",
    CurrentValue=false,
    Callback=function(v) STATE.consoleAC=v notify(v and "Console ON" or "OFF") end }, "TglCon")
GBMd:CreateToggle({ Name="Allow 2-Letter Words", Description="ON = ax, ox, my, xi, etc (game allows)",
    CurrentValue=true,
    Callback=function(v)
        CONFIG.allow2Letter = v
        CONFIG.minLength = v and 2 or 3
        notify("2-Letter " .. (v and "ENABLED" or "DISABLED") .. " | minLength="..CONFIG.minLength)
        if STATE.input ~= "" then pcall(rebuildTopWords) end
    end }, "Tgl2Let")
GBMd:CreateToggle({ Name="Stealth Mode", Description="Mouse jitter + variable delay (anti-detect)",
    CurrentValue=true,
    Callback=function(v) CONFIG.stealthMode = v notify(v and "Stealth ON" or "Stealth OFF") end }, "TglStealth")

GBTy:CreateSlider({ Name="Safe Mode Speed",   Description="Delay per letter (Safe Mode)",
    Range={80,350},  Increment=10, Suffix="ms",     CurrentValue=160,
    Callback=function(v) CONFIG.safe.baseDelay=v/1000 end }, "SlSafe")
GBTy:CreateSlider({ Name="Fast Mode Speed",   Description="Delay per letter (Fast Mode)",
    Range={10,80},   Increment=5,  Suffix="ms",     CurrentValue=35,
    Callback=function(v) CONFIG.fast.baseDelay=v/1000 end }, "SlFast")
GBTy:CreateSlider({ Name="Pre-type Delay",    Description="Pause before starting to type",
    Range={1,15},    Increment=1,  Suffix="x0.1s",  CurrentValue=5,
    Callback=function(v) CONFIG.safe.preMin=v*0.06 CONFIG.safe.preMax=v*0.14 end }, "SlPre")
GBTy:CreateSlider({ Name="Ideal Word Length", Description="Normal mode: target word length",
    Range={3,15},    Increment=1,  Suffix=" ch",     CurrentValue=6,
    Callback=function(v)
        CONFIG.idealLength=v
        if STATE.input~="" then pcall(rebuildTopWords) end
    end }, "SlIdeal")
GBTy:CreateSlider({ Name="Words Per Page",    Description="Suggestions shown per page",
    Range={5,20},    Increment=1,  Suffix="",        CurrentValue=10,
    Callback=function(v) CONFIG.wordsPerPage=v STATE.page=1 pcall(updateDisplay) end }, "SlPg")
GBTy:CreateSlider({ Name="Auto-Reset Timeout",Description="Reset used words after N seconds idle",
    Range={60,600},  Increment=30, Suffix="s",       CurrentValue=180,
    Callback=function(v) CONFIG.autoResetTime=v end }, "SlRst")
GBWin:CreateSlider({ Name="Window Scale",     Description="Zoom UI in/out (50%-150%)",
    Range={50,150},  Increment=5,  Suffix="%",       CurrentValue=100,
    Callback=function(v)
        local sc = getDPI()
        if sc then sc.Scale=v/100 end
    end }, "SlScale")

TabSet:BuildThemeGroupbox()
TabSet:BuildConfigGroupbox()

-- ============================================================
--  RESIZE HANDLE
-- ============================================================
task.defer(function()
    task.wait(1.5)
    pcall(function()
        local sc = getDPI()
        local wi = Window.Instance
        local h  = Instance.new("Frame")
        h.Name             = "LLP_Resize"
        h.Size             = UDim2.new(0, 130, 0, 12)
        h.Position         = UDim2.new(0.5, -65, 1, -6)
        h.BackgroundColor3 = Color3.fromRGB(70, 75, 100)
        h.BorderSizePixel  = 0
        h.ZIndex           = 50
        h.Active           = true
        h.Parent           = wi
        Instance.new("UICorner", h).CornerRadius = UDim.new(0, 6)
        local t = Instance.new("TextLabel", h)
        t.Size = UDim2.new(1,0,1,0)
        t.BackgroundTransparency = 1
        t.Text       = "=== Resize ==="
        t.TextColor3 = Color3.fromRGB(155, 160, 190)
        t.TextSize   = 9
        t.Font       = Enum.Font.GothamBold
        t.ZIndex     = 51
        local drag, sy, ss = false, 0, 1
        h.InputBegan:Connect(function(i)
            if i.UserInputType==Enum.UserInputType.MouseButton1 then
                drag=true sy=i.Position.Y ss=sc and sc.Scale or 1
            end
        end)
        UserInputService.InputChanged:Connect(function(i)
            if drag and i.UserInputType==Enum.UserInputType.MouseMovement and sc then
                sc.Scale = math.clamp(ss+(i.Position.Y-sy)/600, 0.5, 1.5)
            end
        end)
        UserInputService.InputEnded:Connect(function(i)
            if i.UserInputType==Enum.UserInputType.MouseButton1 then drag=false end
        end)
    end)
end)

-- ============================================================
--  RIGHT CTRL TOGGLE
-- ============================================================
pcall(function() Starlight.WindowKeybind = "RightControl" end)
UserInputService.InputBegan:Connect(function(i, gp)
    if gp then return end
    if i.KeyCode == Enum.KeyCode.RightControl then
        STATE.guiVisible = not STATE.guiVisible
        pcall(function() Starlight.Instance.Enabled = STATE.guiVisible end)
    end
end)

-- ============================================================
--  BOOT
-- ============================================================
task.spawn(function()
    hookChat()
    local ok = loadDictionary()
    if ok then
        print("[LLP v3.4] 912 lines loaded | Changelog in Dashboard | 2-step + stealth ACTIVE")
        pcall(function() setLbl(lblPage, #STATE.allWords.." words ready | Type first letter") end)
    else
        pcall(function() setLbl(lblPage, "Dictionary failed!") end)
    end
    getServerInfo()
end)

Starlight:LoadAutoloadConfig()

print("✅ Last Letter Pro v3.4 FULL INJECTED — 912 lines | Changelog now in Dashboard")
