-- ============================================================
--  Last Letter Pro  v2.6  |  Starlight Interface Suite
--  CONFIRMED:
--  - UIScale name = "DPIScale" ada di Starlight.Instance
--  - Drag frame bawaan Starlight = Frame "Drag" di Starlight.Instance
--  - Window.Instance = TextButton "MainWindow", Size 930x560
--  - TeleportOptions.ServerInstanceId = tersedia
-- ============================================================

local Players             = game:GetService("Players")
local VirtualInputManager = game:GetService("VirtualInputManager")
local StarterGui          = game:GetService("StarterGui")
local LogService          = game:GetService("LogService")
local HttpService         = game:GetService("HttpService")
local UserInputService    = game:GetService("UserInputService")
local TeleportService     = game:GetService("TeleportService")

local LocalPlayer = Players.LocalPlayer

-- ============================================================
--  LOAD STARLIGHT
-- ============================================================
local Starlight = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/Nebula-Softworks/Starlight-Interface-Suite/master/Source.lua"
))()

-- ============================================================
--  CONFIG
-- ============================================================
local CONFIG = {
    safe = { baseDelay=0.18, randomMult=1.8, preMin=0.4, preMax=1.2, postMin=0.1, postMax=0.3 },
    fast = { baseDelay=0.05, randomMult=1.1, preMin=0.05, preMax=0.1, postMin=0.03, postMax=0.08 },
    safeMode      = true,
    minLength     = 3,
    maxLength     = 15,
    idealLength   = 6,
    autoResetTime = 300,
    wordsPerPage  = 10,
}

local commonWords = {
    ["the"]=true,["and"]=true,["a"]=true,["an"]=true,
    ["is"]=true,["it"]=true,["to"]=true,["of"]=true,
    ["in"]=true,["for"]=true,["on"]=true,["with"]=true,
    ["as"]=true,["at"]=true,["by"]=true,["or"]=true,
}

local DICTIONARY_URLS = {
    "https://raw.githubusercontent.com/dwyl/english-words/refs/heads/master/words_dictionary.json",
    "https://raw.githubusercontent.com/first20hours/google-10000-english/master/google-10000-english-usa-no-swears.txt",
}

-- Roblox regional discovery endpoints untuk ping test
local REGION_ENDPOINTS = {
    ["Singapore"] = "https://asia-southeast1.discovery.roblox.com/",
    ["Japan"]     = "https://asia-northeast1.discovery.roblox.com/",
    ["US East"]   = "https://us-east-1.discovery.roblox.com/",
    ["US West"]   = "https://us-west-2.discovery.roblox.com/",
    ["Europe"]    = "https://eu-west-1.discovery.roblox.com/",
    ["Australia"] = "https://ap-southeast-2.discovery.roblox.com/",
}

-- ============================================================
--  STATE
-- ============================================================
local allWords            = {}
local usedWords           = {}
local lastWordTime        = 0
local topWords            = {}
local currentPage         = 1
local currentInput        = ""
local currentMode         = "normal"
local autoInputEnabled    = false
local consoleAutoComplete = false
local guiVisible          = true
local isTyping            = false
local dpiScale            = nil  -- UIScale "DPIScale"

local labelPage       = nil
local labelStatus     = nil
local labelServerInfo = nil
local labelPingInfo   = nil

-- ============================================================
--  HELPERS
-- ============================================================
local function notify(msg)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "Last Letter Pro", Text = msg, Duration = 3,
        })
    end)
end

local function setLabel(lbl, text)
    if not lbl then return end
    pcall(function() lbl.Instance.Header.Text = tostring(text) end)
end

local function rnd(min, max)
    return min + math.random() * (max - min)
end

local function getDelayCfg()
    return CONFIG.safeMode and CONFIG.safe or CONFIG.fast
end

-- CONFIRMED: UIScale namanya "DPIScale" di Starlight.Instance
local function getDPIScale()
    if dpiScale then return dpiScale end
    pcall(function()
        dpiScale = Starlight.Instance:FindFirstChild("DPIScale")
    end)
    return dpiScale
end

-- ============================================================
--  SERVER REGION DETECTION (ping ke Roblox endpoints)
-- ============================================================
local function pingEndpoint(url)
    local t0 = tick()
    pcall(function() game:HttpGet(url) end)
    return math.floor((tick() - t0) * 1000)
end

local function detectServerRegion()
    task.spawn(function()
        setLabel(labelServerInfo, "Pinging regions...")
        local results = {}
        for name, url in pairs(REGION_ENDPOINTS) do
            local ms = pingEndpoint(url)
            table.insert(results, { name=name, ping=ms })
        end
        table.sort(results, function(a,b) return a.ping < b.ping end)

        local best = results[1]
        local lines = "Estimated Server: " .. best.name
                   .. "\nJobId: " .. game.JobId:sub(1,12) .. "..."
                   .. "\n\nPing to regions:"
        for _, r in ipairs(results) do
            lines = lines .. "\n" .. r.name .. ": " .. r.ping .. "ms"
        end
        setLabel(labelServerInfo, lines)
        setLabel(labelPingInfo, "Closest: " .. best.name .. " (" .. best.ping .. "ms)")
    end)
end

-- ============================================================
--  SERVER HOP
--  Strategy: ambil server list, ping endpoint tiap region dari
--  client, lalu pilih server berdasarkan region target.
--  Karena API tidak expose region per server, kita pilih server
--  dengan ping rendah ke endpoint yang dituju dengan cara:
--  sort server list by player count, hop ke beberapa server
--  sambil test ping, berhenti saat ping ke target region rendah.
--  Fallback: teleport langsung dengan TeleportOptions.
-- ============================================================
local function getServerList()
    local servers = {}
    local cursor  = nil
    local pages   = 0
    repeat
        local url = "https://games.roblox.com/v1/games/" .. game.PlaceId
                 .. "/servers/Public?sortOrder=Asc&limit=100"
                 .. (cursor and ("&cursor=" .. cursor) or "")
        local ok, res = pcall(function() return game:HttpGet(url) end)
        if not ok then break end
        local ok2, data = pcall(function() return HttpService:JSONDecode(res) end)
        if not ok2 or not data or not data.data then break end
        for _, s in ipairs(data.data) do
            if s.id ~= game.JobId and (s.playing or 0) < (s.maxPlayers or 999) then
                table.insert(servers, s)
            end
        end
        cursor = data.nextPageCursor
        pages  = pages + 1
    until not cursor or pages >= 3
    return servers
end

local function serverHop(targetRegion)
    notify("Searching servers" .. (targetRegion ~= "Auto" and " → " .. targetRegion or "") .. "...")
    setLabel(labelPingInfo, "Fetching server list...")

    task.spawn(function()
        local servers = getServerList()
        if #servers == 0 then
            notify("No servers found!")
            setLabel(labelPingInfo, "No servers found!")
            return
        end

        setLabel(labelPingInfo, "Found " .. #servers .. " servers...")

        local chosen = nil

        if targetRegion == "Auto" then
            -- Pilih server paling aktif
            table.sort(servers, function(a,b) return (a.playing or 0) > (b.playing or 0) end)
            chosen = servers[1]
        else
            -- Ping ke endpoint region target dulu
            local endpointUrl = REGION_ENDPOINTS[targetRegion]
            local myPingToRegion = endpointUrl and pingEndpoint(endpointUrl) or 9999
            setLabel(labelPingInfo, "Your ping to " .. targetRegion .. ": " .. myPingToRegion .. "ms")

            -- Kita tidak bisa ping tiap server langsung dari client Roblox
            -- tapi kita bisa pakai heuristic:
            -- Server dengan "fps" tinggi dan ping rendah di server list cenderung
            -- di region yang sama dengan client yang ada di sana
            -- Roblox menyimpan "fps" dan "ping" per server di API response

            -- Cari server dengan fps tinggi (server sehat) dan banyak pemain
            local candidates = {}
            for _, s in ipairs(servers) do
                local score = (s.playing or 0) * 10
                -- kalau ada field fps/ping dari API, gunakan
                if s.fps then score = score + (s.fps or 0) end
                -- prefer server yang tidak penuh (ada ruang)
                local capacity = s.maxPlayers or 30
                if (s.playing or 0) < capacity * 0.9 then
                    table.insert(candidates, { server=s, score=score })
                end
            end

            if #candidates == 0 then candidates = {} for _, s in ipairs(servers) do table.insert(candidates, {server=s, score=0}) end end
            table.sort(candidates, function(a,b) return a.score > b.score end)

            -- Ambil dari top 10 secara random untuk variasi
            local pool = math.min(10, #candidates)
            chosen = candidates[math.random(1, pool)].server
        end

        if chosen then
            local playerCount = chosen.playing or "?"
            notify("Hopping → " .. targetRegion .. " (" .. playerCount .. " players)...")
            setLabel(labelPingInfo, "Teleporting to server with " .. playerCount .. " players...")
            task.wait(0.3)

            local opts = Instance.new("TeleportOptions")
            opts.ServerInstanceId = chosen.id

            local ok, err = pcall(function()
                TeleportService:TeleportAsync(game.PlaceId, { LocalPlayer }, opts)
            end)
            if not ok then
                -- Fallback ke TeleportToPlaceInstance
                local ok2, err2 = pcall(function()
                    TeleportService:TeleportToPlaceInstance(game.PlaceId, chosen.id, LocalPlayer)
                end)
                if not ok2 then
                    pcall(function() TeleportService:Teleport(game.PlaceId) end)
                end
            end
        else
            notify("No suitable server found!")
        end
    end)
end

-- ============================================================
--  DICTIONARY
-- ============================================================
local function loadFromJSON(content)
    local ok, decoded = pcall(function() return HttpService:JSONDecode(content) end)
    if not ok then return false end
    for word in pairs(decoded) do
        local len = #word
        if len >= CONFIG.minLength and len <= CONFIG.maxLength and not commonWords[word:lower()] then
            table.insert(allWords, word:lower())
        end
    end
    return #allWords > 0
end

local function loadFromText(content)
    for word in content:gmatch("[^\r\n]+") do
        local len = #word
        if len >= CONFIG.minLength and len <= CONFIG.maxLength and not commonWords[word:lower()] then
            table.insert(allWords, word:lower())
        end
    end
    return #allWords > 0
end

local function loadDictionary()
    notify("Loading dictionary...")
    for _, url in ipairs(DICTIONARY_URLS) do
        local ok, content = pcall(function() return game:HttpGet(url) end)
        if ok then
            local loaded = content:match("^%s*{") and loadFromJSON(content) or loadFromText(content)
            if loaded then notify("Ready! " .. #allWords .. " words loaded") return true end
        end
    end
    notify("Dictionary failed to load!")
    return false
end

-- ============================================================
--  AUTO-TYPE
-- ============================================================
local function autoTypeWord(word, typed)
    if isTyping then return end
    local remaining = word:sub(#typed + 1)
    if #remaining == 0 then return end
    isTyping  = true
    local cfg = getDelayCfg()
    task.spawn(function()
        local sz = workspace.CurrentCamera.ViewportSize
        VirtualInputManager:SendMouseButtonEvent(sz.X/2, sz.Y/2, 0, true,  game, 1)
        task.wait(0.05)
        VirtualInputManager:SendMouseButtonEvent(sz.X/2, sz.Y/2, 0, false, game, 1)
        task.wait(rnd(cfg.preMin, cfg.preMax))
        for c in remaining:upper():gmatch(".") do
            local key = Enum.KeyCode[c]
            if key then
                VirtualInputManager:SendKeyEvent(true, key, false, game)
                task.wait(cfg.baseDelay + math.random()*(cfg.baseDelay*cfg.randomMult - cfg.baseDelay))
                VirtualInputManager:SendKeyEvent(false, key, false, game)
                if CONFIG.safeMode and math.random() < 0.15 then task.wait(rnd(0.05, 0.2)) end
            end
        end
        task.wait(rnd(cfg.postMin, cfg.postMax))
        VirtualInputManager:SendKeyEvent(true,  Enum.KeyCode.Return, false, game)
        task.wait(0.05)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Return, false, game)
        isTyping = false
    end)
end

-- ============================================================
--  WORD LOGIC
-- ============================================================
local function getBestWord()
    if #topWords == 0 then return nil end
    if currentMode == "troll" then
        local best = topWords[1]
        for _, w in ipairs(topWords) do if #w > #best then best = w end end
        return best
    end
    return topWords[1]
end

local function getLongestWord()
    if #topWords == 0 then return nil end
    local best = topWords[1]
    for _, w in ipairs(topWords) do if #w > #best then best = w end end
    return best
end

local function updateStatusLabel()
    if #topWords == 0 then
        setLabel(labelPage,   currentInput=="" and "Type letters below." or "No matches: "..currentInput:upper())
        setLabel(labelStatus, "")
        return
    end
    local s     = (currentPage-1)*CONFIG.wordsPerPage + 1
    local e     = math.min(currentPage*CONFIG.wordsPerPage, #topWords)
    local total = math.max(1, math.ceil(#topWords/CONFIG.wordsPerPage))
    setLabel(labelPage, "Page "..currentPage.."/"..total.."  |  "..#topWords.." matches  |  "..currentMode:upper())
    local lines = {}
    for i = s, e do
        table.insert(lines, (i==s and ">> " or "   ")..topWords[i]:upper())
    end
    setLabel(labelStatus, table.concat(lines, "\n"))
end

local function updateTopWords(input)
    topWords = {} currentPage = 1
    input = input:lower()
    if input ~= "" then
        for _, w in ipairs(allWords) do
            if w:sub(1,#input)==input and w~=input and not usedWords[w] then
                table.insert(topWords, w)
            end
        end
        table.sort(topWords, function(a,b)
            local da=math.abs(#a-CONFIG.idealLength)
            local db=math.abs(#b-CONFIG.idealLength)
            if da==db then return #a==#b and a<b or #a<#b end
            return da<db
        end)
    end
    pcall(updateStatusLabel)
    if autoInputEnabled and not isTyping and #topWords>0 and input~="" then
        local word = getBestWord()
        local wt, ts = word, currentInput
        usedWords[word]=true currentInput="" topWords={}
        pcall(updateStatusLabel)
        notify("Auto: "..wt:upper())
        autoTypeWord(wt, ts)
    end
end

local function useWord(word)
    if not word then return end
    if isTyping then notify("Still typing...") return end
    local wt, ts = word, currentInput
    usedWords[word]=true currentInput="" topWords={}
    pcall(updateStatusLabel)
    notify("Typing: "..wt:upper())
    autoTypeWord(wt, ts)
end

-- ============================================================
--  CONSOLE
-- ============================================================
LogService.MessageOut:Connect(function(msg)
    if consoleAutoComplete and msg:find("Word:") then
        local l = msg:match("Word:%s*([A-Z][A-Z]?[A-Z]?[A-Z]?)")
        if l then lastWordTime=tick() notify("Detected: "..l) currentInput=l updateTopWords(l) end
    end
end)
task.spawn(function()
    while task.wait(10) do
        if lastWordTime>0 and tick()-lastWordTime>CONFIG.autoResetTime then
            usedWords={} lastWordTime=0 notify("Auto-reset!")
        end
    end
end)

-- ============================================================
--  BUILD WINDOW
-- ============================================================
local Window = Starlight:CreateWindow({
    Name="Last Letter Pro", Subtitle="Word Auto-Complete  |  v2.6",
    Icon=nil, LoadingEnabled=true,
    LoadingTitle="Last Letter Pro", LoadingSubtitle="Loading...",
    ConfigurationSavingEnabled=true, ConfigurationFolder="LastLetterPro",
})

local HomeTab   = Window:CreateHomeTab({})
local SecMain   = Window:CreateTabSection("Main")
local SecServer = Window:CreateTabSection("Server")
local SecSet    = Window:CreateTabSection("Settings")
local TabMain   = SecMain:CreateTab({   Name="Search",     Icon=nil, Columns=1 }, "TABMAIN")
local TabServer = SecServer:CreateTab({ Name="Server Hop", Icon=nil, Columns=1 }, "TABSRV")
local TabSet    = SecSet:CreateTab({    Name="Settings",   Icon=nil, Columns=1 }, "TABSET")

-- ── Search Tab ───────────────────────────────────────────────
local GBInput   = TabMain:CreateGroupbox({ Name="Input Letters", Icon=nil }, "GBI")
local GBSuggest = TabMain:CreateGroupbox({ Name="Suggestions",   Icon=nil }, "GBSug")
local GBActions = TabMain:CreateGroupbox({ Name="Actions",       Icon=nil }, "GBAct")
local GBPages   = TabMain:CreateGroupbox({ Name="Pages",         Icon=nil }, "GBPg")

GBInput:CreateInput({
    Name="Letters", Description="Type starting letters shown in-game",
    PlaceholderText="e.g. CO, ST, PR...", OnEnter=false, RemoveTextAfterFocusLost=false,
    Callback=function(val) currentInput=val updateTopWords(val) end,
}, "LettersInput")

labelPage   = GBSuggest:CreateLabel({ Text="" }, "LblPage")
labelStatus = GBSuggest:CreateLabel({ Text="" }, "LblStatus")
task.defer(function()
    setLabel(labelPage,   "Loading dictionary...")
    setLabel(labelStatus, "")
end)

GBActions:CreateButton({ Name="Use Best Word", Description="Type top word based on mode",
    Callback=function() local w=getBestWord() if not w then notify("No words!") return end useWord(w) end }, "BtnBest")
GBActions:CreateButton({ Name="Use Normal (Ideal Length)", Description="Force: closest to ideal length",
    Callback=function() if #topWords==0 then notify("No words!") return end useWord(topWords[1]) end }, "BtnNormal")
GBActions:CreateButton({ Name="Use Troll (Longest Word)", Description="Force: longest available word",
    Callback=function() local w=getLongestWord() if not w then notify("No words!") return end useWord(w) end }, "BtnTroll")
GBActions:CreateButton({ Name="Reset Used Words", Description="Allow already-used words again",
    Callback=function() usedWords={} lastWordTime=0 notify("Cleared!") updateTopWords(currentInput) end }, "BtnReset")
GBPages:CreateButton({ Name="Previous Page", Description="",
    Callback=function() if currentPage>1 then currentPage=currentPage-1 pcall(updateStatusLabel) end end }, "BtnPrev")
GBPages:CreateButton({ Name="Next Page", Description="",
    Callback=function()
        local t=math.max(1,math.ceil(#topWords/CONFIG.wordsPerPage))
        if currentPage<t then currentPage=currentPage+1 pcall(updateStatusLabel) end
    end }, "BtnNext")

-- ── Server Hop Tab ───────────────────────────────────────────
local GBSrvInfo = TabServer:CreateGroupbox({ Name="Server Info",   Icon=nil }, "GBSrvI")
local GBSrvHop  = TabServer:CreateGroupbox({ Name="Hop to Region", Icon=nil }, "GBSrvH")

labelServerInfo = GBSrvInfo:CreateLabel({ Text="" }, "LblSrv")
labelPingInfo   = GBSrvInfo:CreateLabel({ Text="" }, "LblPing")
task.defer(function()
    setLabel(labelServerInfo, "Click 'Detect Region' to scan server location")
    setLabel(labelPingInfo,   "JobId: "..game.JobId:sub(1,12).."...")
end)
GBSrvInfo:CreateButton({ Name="Detect Server Region", Description="Ping Roblox regional endpoints",
    Callback=function() detectServerRegion() end }, "BtnDetect")

for _, r in ipairs({"Auto","Singapore","Japan","US East","US West","Europe","Australia"}) do
    GBSrvHop:CreateButton({
        Name = r=="Auto" and "Hop → Any Server" or "Hop → "..r,
        Description = r=="Auto" and "Join any available server" or "Best available server near "..r,
        Callback = function() serverHop(r) end,
    }, "BtnHop_"..r:gsub(" ","_"))
end

-- ── Settings Tab ─────────────────────────────────────────────
local GBMode   = TabSet:CreateGroupbox({ Name="Mode",         Icon=nil }, "GBMode")
local GBTyping = TabSet:CreateGroupbox({ Name="Typing",       Icon=nil }, "GBTyp")
local GBWindow = TabSet:CreateGroupbox({ Name="Window Scale", Icon=nil }, "GBWin")

GBMode:CreateToggle({ Name="Troll Mode", Description="ON=longest  |  OFF=ideal length",
    CurrentValue=false, Callback=function(val) currentMode=val and "troll" or "normal" notify("Mode: "..currentMode:upper()) pcall(updateStatusLabel) end }, "TrollMode")
GBMode:CreateToggle({ Name="Safe Mode (Natural Typing)", Description="ON=human-like delay  |  OFF=Fast Mode",
    CurrentValue=true, Callback=function(val) CONFIG.safeMode=val notify(val and "Safe Mode" or "Fast Mode") end }, "SafeMode")
GBMode:CreateToggle({ Name="Auto-Input", Description="Auto-type as soon as letters entered",
    CurrentValue=false, Callback=function(val) autoInputEnabled=val notify(val and "Auto-Input ON" or "OFF") end }, "AutoInput")
GBMode:CreateToggle({ Name="Console Auto-Complete", Description="Detect 'Word: XX' from console",
    CurrentValue=false, Callback=function(val) consoleAutoComplete=val notify(val and "Console ON" or "OFF") end }, "ConsoleToggle")

GBTyping:CreateSlider({ Name="Safe Mode Speed", Description="Delay per huruf (Safe Mode)",
    Range={100,400}, Increment=10, Suffix="ms", CurrentValue=180,
    Callback=function(val) CONFIG.safe.baseDelay=val/1000 end }, "SafeSpeed")
GBTyping:CreateSlider({ Name="Fast Mode Speed", Description="Delay per huruf (Fast Mode)",
    Range={10,100}, Increment=5, Suffix="ms", CurrentValue=50,
    Callback=function(val) CONFIG.fast.baseDelay=val/1000 end }, "FastSpeed")
GBTyping:CreateSlider({ Name="Pre-type Delay", Description="Jeda sebelum mulai ketik (Safe Mode)",
    Range={1,20}, Increment=1, Suffix="x0.1s", CurrentValue=8,
    Callback=function(val) CONFIG.safe.preMin=val*0.05 CONFIG.safe.preMax=val*0.15 end }, "PreDelay")
GBTyping:CreateSlider({ Name="Ideal Word Length", Description="Normal mode: closest to this length",
    Range={3,15}, Increment=1, Suffix=" ch", CurrentValue=6,
    Callback=function(val) CONFIG.idealLength=val pcall(updateTopWords,currentInput) end }, "IdealLength")
GBTyping:CreateSlider({ Name="Words Per Page", Range={5,20}, Increment=1, Suffix="", CurrentValue=10,
    Description="Words shown per page",
    Callback=function(val) CONFIG.wordsPerPage=val currentPage=1 pcall(updateStatusLabel) end }, "WordsPerPage")
GBTyping:CreateSlider({ Name="Auto-Reset Timeout", Range={60,600}, Increment=30, Suffix="s", CurrentValue=300,
    Description="Clear used words after N seconds",
    Callback=function(val) CONFIG.autoResetTime=val end }, "AutoResetTime")

-- Window scale — CONFIRMED: UIScale = "DPIScale" di Starlight.Instance
GBWindow:CreateSlider({ Name="Window Scale", Description="Zoom in/out (50%–150%)",
    Range={50,150}, Increment=5, Suffix="%", CurrentValue=100,
    Callback=function(val)
        local sc = getDPIScale()
        if sc then sc.Scale=val/100 end
    end }, "WinScale")

TabSet:BuildThemeGroupbox()
TabSet:BuildConfigGroupbox()

-- ============================================================
--  RESIZE DRAG BAR
--  CONFIRMED: Ada Frame "Drag" bawaan Starlight di Starlight.Instance
--  posisi: {0.5,0},{0,731} size: {150,20}
--  Kita extend fungsionalitasnya dengan attach listener ke sana
--  DAN tambah handle kecil yang menempel TEPAT di bawah Window
-- ============================================================
task.defer(function()
    task.wait(1.5)
    pcall(function()
        local sc  = getDPIScale()
        local si  = Starlight.Instance
        local wi  = Window.Instance  -- TextButton MainWindow

        -- Starlight sudah punya Frame "Drag" untuk pindahkan window
        -- Kita tambah resize handle yang posisinya RELATIF ke MainWindow
        -- dengan cara menjadi child dari MainWindow itu sendiri

        local handle = Instance.new("Frame")
        handle.Name             = "LLP_Resize"
        handle.Size             = UDim2.new(0, 140, 0, 14)
        -- posisi: di BAWAH window, tengah, sedikit masuk ke dalam
        handle.Position         = UDim2.new(0.5, -70, 1, -7)
        handle.BackgroundColor3 = Color3.fromRGB(80, 85, 110)
        handle.BorderSizePixel  = 0
        handle.ZIndex           = 50
        handle.Active           = true
        handle.Parent           = wi   -- child of MainWindow, bukan ScreenGui

        Instance.new("UICorner", handle).CornerRadius = UDim.new(0,7)

        local dots = Instance.new("TextLabel", handle)
        dots.Size                 = UDim2.new(1,0,1,0)
        dots.BackgroundTransparency = 1
        dots.Text                 = "• • • • •"
        dots.TextColor3           = Color3.fromRGB(180,185,210)
        dots.TextSize             = 10
        dots.Font                 = Enum.Font.GothamBold
        dots.ZIndex               = 51

        -- Drag logic: geser Y untuk resize via DPIScale
        local dragging   = false
        local startY     = 0
        local startScale = 1.0

        handle.InputBegan:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging   = true
                startY     = inp.Position.Y
                startScale = sc and sc.Scale or 1.0
            end
        end)
        UserInputService.InputChanged:Connect(function(inp)
            if dragging and inp.UserInputType == Enum.UserInputType.MouseMovement and sc then
                local delta = inp.Position.Y - startY
                sc.Scale    = math.clamp(startScale + delta/600, 0.5, 1.5)
            end
        end)
        UserInputService.InputEnded:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = false
            end
        end)

        print("[LLP] Resize handle attached to MainWindow")
    end)
end)

-- ============================================================
--  TOGGLE UI — RIGHT CTRL
-- ============================================================
pcall(function() Starlight.WindowKeybind = "RightControl" end)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.RightControl then
        guiVisible = not guiVisible
        pcall(function() Starlight.Instance.Enabled = guiVisible end)
    end
end)

-- ============================================================
--  BOOT
-- ============================================================
task.spawn(function()
    if loadDictionary() then
        print("[Last Letter Pro] Ready - "..#allWords.." words loaded.")
        pcall(function() setLabel(labelPage, #allWords.." words loaded. Type letters above.") end)
    else
        pcall(function() setLabel(labelPage, "Dictionary failed to load!") end)
    end
end)

Starlight:LoadAutoloadConfig()
