NPCVendorSort = {}
local NVS = NPCVendorSort

NVS.visibleItems  = {}
NVS.detectedSlots = {}

NVS.slotCache     = {}
NVS.useCache      = {}
NVS.pendingCache  = false
NVS.pendingCount  = 0
NVS.isRedrawing   = false

local OTHER = "NVS_OTHER"

NVS.slotOrder = {
    "INVTYPE_HEAD",
    "INVTYPE_NECK",
    "INVTYPE_SHOULDER",
    "INVTYPE_CLOAK",
    "INVTYPE_CHEST",
    "INVTYPE_ROBE",
    "INVTYPE_BODY",
    "INVTYPE_TABARD",
    "INVTYPE_WRIST",
    "INVTYPE_HAND",
    "INVTYPE_WAIST",
    "INVTYPE_LEGS",
    "INVTYPE_FEET",
    "INVTYPE_FINGER",
    "INVTYPE_TRINKET",
    "INVTYPE_WEAPON",
    "INVTYPE_2HWEAPON",
    "INVTYPE_WEAPONMAINHAND",
    "INVTYPE_WEAPONOFFHAND",
    "INVTYPE_SHIELD",
    "INVTYPE_HOLDABLE",
    "INVTYPE_RANGED",
    "INVTYPE_RANGEDRIGHT",
    "INVTYPE_THROWN",
    "INVTYPE_RELIC",
    "INVTYPE_AMMO",
    "INVTYPE_BAG",
    OTHER,
}

NVS.slotNames = {
    INVTYPE_HEAD           = "Head",
    INVTYPE_NECK           = "Neck",
    INVTYPE_SHOULDER       = "Shoulder",
    INVTYPE_CLOAK          = "Back",
    INVTYPE_CHEST          = "Chest",
    INVTYPE_ROBE           = "Chest (Robe)",
    INVTYPE_BODY           = "Shirt",
    INVTYPE_TABARD         = "Tabard",
    INVTYPE_WRIST          = "Wrist",
    INVTYPE_HAND           = "Hands",
    INVTYPE_WAIST          = "Waist",
    INVTYPE_LEGS           = "Legs",
    INVTYPE_FEET           = "Feet",
    INVTYPE_FINGER         = "Ring",
    INVTYPE_TRINKET        = "Trinket",
    INVTYPE_WEAPON         = "One-Hand",
    INVTYPE_2HWEAPON       = "Two-Hand",
    INVTYPE_WEAPONMAINHAND = "Main Hand",
    INVTYPE_WEAPONOFFHAND  = "Off Hand",
    INVTYPE_SHIELD         = "Shield",
    INVTYPE_HOLDABLE       = "Held In Off-hand",
    INVTYPE_RANGED         = "Ranged",
    INVTYPE_RANGEDRIGHT    = "Wand / Gun / Bow",
    INVTYPE_THROWN         = "Thrown",
    INVTYPE_RELIC          = "Relic",
    INVTYPE_AMMO           = "Ammo",
    INVTYPE_BAG            = "Bag",
    [OTHER]                = "Other (not gear)",
}

NVS.OTHER = OTHER

NVS.validSlot = {}
for _, k in ipairs(NVS.slotOrder) do NVS.validSlot[k] = true end

local defaultOptions = {
    showItemLevel     = true,
    showQualityColors = true,
    showEnchantInfo   = true,
    autoShowPanel     = true,
    classFilter       = true,
    classArmorOnly    = false,
}

function NVS:InitDB()
    if type(NPCVendorSortDB) ~= "table" then NPCVendorSortDB = {} end
    if type(NPCVendorSortDB.filters) ~= "table" then NPCVendorSortDB.filters = {} end
    if type(NPCVendorSortDB.options) ~= "table" then NPCVendorSortDB.options = {} end

    for k, v in pairs(defaultOptions) do
        if NPCVendorSortDB.options[k] == nil then
            NPCVendorSortDB.options[k] = v
        end
    end

    for _, slot in ipairs(self.slotOrder) do
        if NPCVendorSortDB.filters[slot] == nil then
            NPCVendorSortDB.filters[slot] = true
        end
    end

    if not NPCVendorSortDB.otherUnstuck_v2 then
        NPCVendorSortDB.otherUnstuck_v2 = true
        NPCVendorSortDB.filters[OTHER] = true
    end

    self.filters = NPCVendorSortDB.filters
    self.options = NPCVendorSortDB.options
end

NVS.filters = {}
NVS.options = {}
for k, v in pairs(defaultOptions) do NVS.options[k] = v end
for _, slot in ipairs(NVS.slotOrder) do NVS.filters[slot] = true end

function NVS:IsSlotEnabled(slot)
    return self.filters[slot] and true or false
end

function NVS:SetSlotEnabled(slot, enabled)

    self.filters[slot] = enabled and true or false
end

function NVS:GetSlotForLink(link)
    if not link then return OTHER, true end

    local slot = self.slotCache[link]
    if slot then return slot, true end

    local _, _, _, _, _, _, _, _, equipSlot = GetItemInfo(link)
    if equipSlot == nil then

        return nil, false
    end

    slot = OTHER
    if equipSlot ~= "" and self.validSlot[equipSlot] then
        slot = equipSlot
    end

    self.slotCache[link] = slot
    return slot, true
end

function NVS:GetSlotForIndex(index)
    return self:GetSlotForLink(GetMerchantItemLink(index))
end

local scanTip
local requested = {}
NVS.requested = requested
local REQUESTS_PER_SCAN = 8
local REQUEST_AGAIN     = 8

function NVS:GetScanTip()
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "NPCVendorSortScanTip", nil, "GameTooltipTemplate")
    end
    return scanTip
end

local function RequestItem(link, tick, budget)
    local last = requested[link]
    if last and tick - last < REQUEST_AGAIN then return budget end
    if budget <= 0 then return budget end
    local tip = NVS:GetScanTip()
    tip:SetOwner(WorldFrame, "ANCHOR_NONE")
    tip:SetHyperlink(link)
    tip:Hide()
    requested[link] = tick
    return budget - 1
end

function NVS:ScanMerchant(tick)
    wipe(self.detectedSlots)
    local pending = 0
    local budget = REQUESTS_PER_SCAN
    tick = tick or 0

    local n = GetMerchantNumItems()
    for i = 1, n do
        local link = GetMerchantItemLink(i)
        local slot, resolved = self:GetSlotForLink(link)
        if not resolved then
            pending = pending + 1
            budget = RequestItem(link, tick, budget)
        elseif slot then
            self.detectedSlots[slot] = true
        end
    end

    self.pendingCount = pending
    self.pendingCache = pending > 0
end

function NVS:HasAnythingToFilter()
    return next(self.detectedSlots) ~= nil
end

local ALL_ARMOR = { Cloth = true, Leather = true, Mail = true, Plate = true }

local ARMOR_FREE = { Miscellaneous = true }

local WEAPON_FREE = { ["Fishing Poles"] = true, Miscellaneous = true }

NVS.classGear = {
    WARRIOR = {
        weapon = { ["One-Handed Axes"]=true, ["Two-Handed Axes"]=true,
                   ["One-Handed Maces"]=true, ["Two-Handed Maces"]=true,
                   ["One-Handed Swords"]=true, ["Two-Handed Swords"]=true,
                   Polearms=true, Staves=true, ["Fist Weapons"]=true, Daggers=true,
                   Bows=true, Guns=true, Crossbows=true, Thrown=true },
        armor  = { Cloth=true, Leather=true, Mail=true, Plate=true, Shields=true },
        best   = { [40]="Plate", [1]="Mail" },
    },
    PALADIN = {
        weapon = { ["One-Handed Axes"]=true, ["Two-Handed Axes"]=true,
                   ["One-Handed Maces"]=true, ["Two-Handed Maces"]=true,
                   ["One-Handed Swords"]=true, ["Two-Handed Swords"]=true,
                   Polearms=true },
        armor  = { Cloth=true, Leather=true, Mail=true, Plate=true, Shields=true, Librams=true },
        best   = { [40]="Plate", [1]="Mail" },
    },
    HUNTER = {
        weapon = { ["One-Handed Axes"]=true, ["Two-Handed Axes"]=true,
                   ["One-Handed Swords"]=true, ["Two-Handed Swords"]=true,
                   Polearms=true, Staves=true, Daggers=true, ["Fist Weapons"]=true,
                   Bows=true, Guns=true, Crossbows=true, Thrown=true },
        armor  = { Cloth=true, Leather=true, Mail=true },
        best   = { [40]="Mail", [1]="Leather" },
    },
    ROGUE = {
        weapon = { Daggers=true, ["Fist Weapons"]=true, ["One-Handed Maces"]=true,
                   ["One-Handed Swords"]=true, ["One-Handed Axes"]=true,
                   Bows=true, Guns=true, Crossbows=true, Thrown=true },
        armor  = { Cloth=true, Leather=true },
        best   = { [1]="Leather" },
    },
    PRIEST = {
        weapon = { Daggers=true, ["One-Handed Maces"]=true, Staves=true, Wands=true },
        armor  = { Cloth=true },
        best   = { [1]="Cloth" },
    },
    DEATHKNIGHT = {
        weapon = { ["One-Handed Axes"]=true, ["Two-Handed Axes"]=true,
                   ["One-Handed Maces"]=true, ["Two-Handed Maces"]=true,
                   ["One-Handed Swords"]=true, ["Two-Handed Swords"]=true,
                   Polearms=true },
        armor  = { Cloth=true, Leather=true, Mail=true, Plate=true, Sigils=true },
        best   = { [1]="Plate" },
    },
    SHAMAN = {
        weapon = { ["One-Handed Axes"]=true, ["Two-Handed Axes"]=true,
                   ["One-Handed Maces"]=true, ["Two-Handed Maces"]=true,
                   Daggers=true, ["Fist Weapons"]=true, Staves=true },
        armor  = { Cloth=true, Leather=true, Mail=true, Shields=true, Totems=true },
        best   = { [40]="Mail", [1]="Leather" },
    },
    MAGE = {
        weapon = { Daggers=true, ["One-Handed Swords"]=true, Staves=true, Wands=true },
        armor  = { Cloth=true },
        best   = { [1]="Cloth" },
    },
    WARLOCK = {
        weapon = { Daggers=true, ["One-Handed Swords"]=true, Staves=true, Wands=true },
        armor  = { Cloth=true },
        best   = { [1]="Cloth" },
    },
    DRUID = {
        weapon = { Daggers=true, ["Fist Weapons"]=true, ["One-Handed Maces"]=true,
                   ["Two-Handed Maces"]=true, Staves=true, Polearms=true },
        armor  = { Cloth=true, Leather=true, Idols=true },
        best   = { [1]="Leather" },
    },
}

local RELIC_OWNER = {
    Librams = "PALADIN", Idols = "DRUID", Totems = "SHAMAN", Sigils = "DEATHKNIGHT",
}

function NVS:GetPlayerClass()
    if not self.playerClass then
        local _, cls = UnitClass("player")
        self.playerClass = cls
    end
    return self.playerClass
end

function NVS:GetBestArmor()
    local gear = self.classGear[self:GetPlayerClass() or ""]
    if not gear or not gear.best then return nil end
    local lvl = UnitLevel("player") or 1
    local pick, pickAt = nil, -1
    for at, armor in pairs(gear.best) do
        if lvl >= at and at > pickAt then pick, pickAt = armor, at end
    end
    return pick
end

function NVS:CanUse(itemType, itemSubType, slot)
    if itemType ~= "Weapon" and itemType ~= "Armor" then return true end

    local gear = self.classGear[self:GetPlayerClass() or ""]
    if not gear then return true end

    if itemType == "Weapon" then
        if WEAPON_FREE[itemSubType] then return true end
        return gear.weapon[itemSubType] and true or false
    end

    if ARMOR_FREE[itemSubType] then return true end

    local owner = RELIC_OWNER[itemSubType]
    if owner then return owner == self:GetPlayerClass() end

    if not gear.armor[itemSubType] then return false end

    if self.options.classArmorOnly and ALL_ARMOR[itemSubType]
       and slot ~= "INVTYPE_CLOAK" then
        local best = self:GetBestArmor()
        if best and itemSubType ~= best then return false end
    end

    return true
end

function NVS:IsUsableLink(link, slot)
    if not self.options.classFilter then return true end
    if not link then return true end

    local ok = self.useCache[link]
    if ok ~= nil then return ok end

    local _, _, _, _, _, itemType, itemSubType = GetItemInfo(link)
    if itemType == nil then return true end

    ok = self:CanUse(itemType, itemSubType, slot)
    self.useCache[link] = ok
    return ok
end

function NVS:BuildVisibleList()
    local list = self.visibleItems
    wipe(list)

    local slotFilter = false
    for _, s in ipairs(self.slotOrder) do
        if not self.filters[s] then slotFilter = true break end
    end

    local count = 0
    local n = GetMerchantNumItems()
    for i = 1, n do
        local link = GetMerchantItemLink(i)
        local slot, resolved = self:GetSlotForLink(link)

        if (not resolved and not slotFilter)
           or (resolved and self:IsSlotEnabled(slot) and self:IsUsableLink(link, slot)) then
            count = count + 1
            list[count] = i
        end
    end

    self:GuardEmptyList()
end

function NVS:GuardEmptyList()
    local n = GetMerchantNumItems()
    if n > 0 and #self.visibleItems == 0 then
        for i = 1, n do
            self.visibleItems[i] = i
        end

        if not self.warnedEmpty and not self.pendingCache then
            self.warnedEmpty = true
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99NPCVendorSort|r: "
                .. "every item here was hidden by your filters, so they are "
                .. "being shown anyway. Use /nvs reset to clear the filters.")
        end
        return true
    end
    return false
end

local realNumItems, realItemInfo, realItemLink, realCostInfo, realCostItem, realMaxStack

local function Map(i)
    return NVS.visibleItems[i] or i
end

function NVS:BeginRemap()
    if self.remapped then return end
    self.remapped = true

    realNumItems = GetMerchantNumItems
    realItemInfo = GetMerchantItemInfo
    realItemLink = GetMerchantItemLink
    realCostInfo = GetMerchantItemCostInfo
    realCostItem = GetMerchantItemCostItem
    realMaxStack = GetMerchantItemMaxStack

    GetMerchantNumItems     = function() return #NVS.visibleItems end
    GetMerchantItemInfo     = function(i) return realItemInfo(Map(i)) end
    GetMerchantItemLink     = function(i) return realItemLink(Map(i)) end
    GetMerchantItemCostInfo = function(i) return realCostInfo(Map(i)) end
    GetMerchantItemCostItem = function(i, j) return realCostItem(Map(i), j) end
    if realMaxStack then
        GetMerchantItemMaxStack = function(i) return realMaxStack(Map(i)) end
    end
end

function NVS:EndRemap()
    if not self.remapped then return end
    self.remapped = false

    GetMerchantNumItems     = realNumItems
    GetMerchantItemInfo     = realItemInfo
    GetMerchantItemLink     = realItemLink
    GetMerchantItemCostInfo = realCostInfo
    GetMerchantItemCostItem = realCostItem
    if realMaxStack then
        GetMerchantItemMaxStack = realMaxStack
    end
end

local STAT_PATTERNS = {
    { "spell power by (%d+)",               "SP"     },
    { "attack power by (%d+)",              "AP"     },
    { "all stats by (%d+)",                 "Stats"  },
    { "agility by (%d+)",                   "Agi"    },
    { "strength by (%d+)",                  "Str"    },
    { "intellect by (%d+)",                 "Int"    },
    { "spirit by (%d+)",                    "Spi"    },
    { "stamina by (%d+)",                   "Sta"    },
    { "critical strike rating by (%d+)",    "Crit"   },
    { "hit rating by (%d+)",                "Hit"    },
    { "haste rating by (%d+)",              "Haste"  },
    { "expertise rating by (%d+)",          "Exp"    },
    { "armor penetration rating by (%d+)",  "ArP"    },
    { "defense rating by (%d+)",            "Def"    },
    { "resilience rating by (%d+)",         "Resil"  },
    { "dodge rating by (%d+)",              "Dodge"  },
    { "parry rating by (%d+)",              "Parry"  },
    { "block value by (%d+)",               "BV"     },
    { "block rating by (%d+)",              "Block"  },
    { "(%d+) mana every 5",                 "MP5"    },
    { "(%d+) mana per 5",                   "MP5"    },
    { "all resistances by (%d+)",           "Resist" },
    { "health by (%d+)",                    "HP"     },
    { "armor by (%d+)",                     "Armor"  },
    { "damage by (%d+)",                    "Dmg"    },
}

local SHORT_NAMES = {
    Berserking = "Berserk",
}

local QUALIFIERS = { "Major ", "Greater ", "Superior ", "Mighty ", "Exceptional ",
                     "Lesser ", "Minor ", "Excellent ", "Potent " }

local enchantCache = {}
NVS.enchantCache = enchantCache

local function ShortName(name)
    local suffix = name and name:match(" %- (.+)$")
    if not suffix then return nil end
    for _, q in ipairs(QUALIFIERS) do
        if suffix:sub(1, #q) == q then suffix = suffix:sub(#q + 1) break end
    end
    return SHORT_NAMES[suffix] or suffix
end

local function ReadUseText(link)
    local tip = NVS:GetScanTip()
    tip:SetOwner(WorldFrame, "ANCHOR_NONE")
    tip:SetHyperlink(link)
    local text
    for i = 2, tip:NumLines() do
        local fs = _G["NPCVendorSortScanTipTextLeft" .. i]
        local t = fs and fs:GetText()
        if t and t:find("^Use:") then text = t break end
    end
    tip:Hide()
    return text
end

function NVS:GetEnchantShort(link, name)
    local cached = enchantCache[link]
    if cached ~= nil then return cached or nil end

    local use = ReadUseText(link)

    if not use then enchantCache[link] = false return nil end
    local low = use:lower()
    if not (low:find("permanently") or low:find("attach")) then
        enchantCache[link] = false
        return nil
    end

    local result
    if not (low:find("sometimes") or low:find("chance") or low:find("occasionally")) then
        local parts, n = {}, 0
        for _, p in ipairs(STAT_PATTERNS) do
            local v = low:match(p[1])
            if v then
                n = n + 1
                parts[n] = "+" .. v .. " " .. p[2]
                if n == 2 then break end
            end
        end
        if n > 0 then result = table.concat(parts, " ") end
    end
    result = result or ShortName(name)

    enchantCache[link] = result or false
    return result
end

local itemButtons, holders, nameTexts, moneyFrames, altFrames

local function CacheButtons()
    itemButtons, holders, nameTexts, moneyFrames, altFrames = {}, {}, {}, {}, {}
    for i = 1, MERCHANT_ITEMS_PER_PAGE do
        itemButtons[i] = _G["MerchantItem" .. i .. "ItemButton"]
        holders[i]     = _G["MerchantItem" .. i]
        nameTexts[i]   = _G["MerchantItem" .. i .. "Name"]
        moneyFrames[i] = _G["MerchantItem" .. i .. "MoneyFrame"] or false
        altFrames[i]   = _G["MerchantItem" .. i .. "AltCurrencyFrame"] or false
    end
end

function NVS:FixButtons(filtering)
    if not itemButtons then CacheButtons() end
    local page = MerchantFrame.page or 1
    local showLevel  = self.options.showItemLevel
    local showColors = self.options.showQualityColors
    local showEnchant = self.options.showEnchantInfo

    for i = 1, MERCHANT_ITEMS_PER_PAGE do
        local itemButton = itemButtons[i]
        local holder     = holders[i]
        local nameText   = nameTexts[i]
        if itemButton then
            local shown = holder and holder:IsShown()
            local realIndex
            if filtering then
                local virtual = (page - 1) * MERCHANT_ITEMS_PER_PAGE + i
                realIndex = self.visibleItems[virtual]
                if realIndex then

                    itemButton:SetID(realIndex)
                    if holder then holder:SetID(realIndex) end
                end
            else

                local virtual = (page - 1) * MERCHANT_ITEMS_PER_PAGE + i
                if virtual <= GetMerchantNumItems() then realIndex = virtual end

                if holder then holder:SetID(i) end
            end
            if not shown or not itemButton:IsShown() then realIndex = nil end

            local link, name, quality, ilvl, equipSlot
            if realIndex and (showLevel or showColors or showEnchant) then
                link = GetMerchantItemLink(realIndex)
                if link then
                    local _
                    name, _, quality, ilvl, _, _, _, _, equipSlot = GetItemInfo(link)
                end
            end

            local enchText = itemButton.nvsEnchant
            local short
            if showEnchant and name and equipSlot == "" then
                short = self:GetEnchantShort(link, name)
            end
            if short and nameText then
                if not enchText then
                    enchText = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    enchText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, 2)
                    enchText:SetWidth(nameText:GetWidth() > 0 and nameText:GetWidth() or 100)
                    enchText:SetHeight(12)
                    itemButton.nvsEnchant = enchText
                end

                local money, alt = moneyFrames[i], altFrames[i]
                if (money and money:IsShown()) or (alt and alt:IsShown()) then
                    enchText:SetJustifyH("RIGHT")
                else
                    enchText:SetJustifyH("LEFT")
                end
                enchText:SetText(short)
                enchText:Show()
            elseif enchText then
                enchText:Hide()
            end

            local levelText = itemButton.nvsLevel
            if showLevel and realIndex then
                if ilvl and ilvl > 1 and equipSlot and equipSlot ~= ""
                   and equipSlot ~= "INVTYPE_BAG" then
                    if not levelText then
                        levelText = itemButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                        levelText:SetPoint("TOPLEFT", itemButton, "TOPLEFT", 2, -2)
                        itemButton.nvsLevel = levelText
                    end
                    levelText:SetText(ilvl)
                    levelText:SetTextColor(1, 1, 1)
                    levelText:Show()
                elseif levelText then
                    levelText:Hide()
                end
            elseif levelText then
                levelText:Hide()
            end

            if nameText then
                local applied = false
                if showColors and quality then
                    local r, g, b = GetItemQualityColor(quality)
                    nameText:SetTextColor(r, g, b)
                    applied = true
                end
                if not applied then
                    nameText:SetTextColor(1, 0.82, 0)
                end
            end
        end
    end
end

function NVS:Redraw()
    if not MerchantFrame or not MerchantFrame:IsShown() then return end
    if MerchantFrame.selectedTab ~= 1 then return end
    if self.isRedrawing then return end

    if StackSplitFrame and StackSplitFrame:IsShown() then return end

    self.isRedrawing = true
    local ok, err = pcall(MerchantFrame_Update)

    self.isRedrawing = false
    self:EndRemap()
    if not ok then geterrorhandler()(err) end
end

local function DoPostDraw()

    NVS:BuildVisibleList()

    local filtering = (#NVS.visibleItems ~= GetMerchantNumItems())

    if filtering then

        local total = math.ceil(#NVS.visibleItems / MERCHANT_ITEMS_PER_PAGE)
        if total < 1 then total = 1 end
        local page = MerchantFrame.page or 1
        if page > total then
            MerchantFrame.page = total
        elseif page < 1 then
            MerchantFrame.page = 1
        end

        NVS:BeginRemap()
        MerchantFrame_UpdateMerchantInfo()
        NVS:EndRemap()
    end

    NVS:FixButtons(filtering)
end

local inPostDraw = false
local function PostDraw()
    if inPostDraw or MerchantFrame.selectedTab ~= 1 then return end
    inPostDraw = true
    local ok, err = pcall(DoPostDraw)

    NVS:EndRemap()
    inPostDraw = false
    if not ok then geterrorhandler()(err) end
end

local hooked = false
local function InstallHook()
    if hooked then return end
    if type(MerchantFrame_Update) == "function"
       and type(MerchantFrame_UpdateMerchantInfo) == "function" then
        hooksecurefunc("MerchantFrame_Update", PostDraw)
        hooked = true
    end
end

InstallHook()

function NVS:InvalidateUseCache()
    wipe(self.useCache)
end

function NVS:UpdateMerchant()
    self:Redraw()
    if NPCVendorSortUI and NPCVendorSortUI.Refresh then
        NPCVendorSortUI:Refresh()
    end
end

local retry = CreateFrame("Frame")
retry.elapsed = 0
retry.tries = 0
retry:Hide()
retry:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < 0.5 then return end
    self.elapsed = 0
    self.tries = self.tries + 1

    if not MerchantFrame or not MerchantFrame:IsShown() then
        self:Hide()
        return
    end

    local before = NVS.pendingCount
    NVS:ScanMerchant(self.tries)
    if NVS.pendingCount ~= before then
        if NPCVendorSortUI and NPCVendorSortUI.Refresh then
            NPCVendorSortUI:Refresh()
        end

        NVS:UpdatePanelVisibility()
        NVS:Redraw()
    end

    if not NVS.pendingCache or self.tries >= 120 then
        self:Hide()
    end
end)

local function StartRetry()
    retry.elapsed = 0
    retry.tries = 0
    if NVS.pendingCache then retry:Show() else retry:Hide() end
end

local function EnsureRetry()
    if NVS.pendingCache and not retry:IsShown() then StartRetry() end
end

function NVS:UpdatePanelVisibility()
    if not NPCVendorSortUI then return end
    if self:HasAnythingToFilter() and self.options.autoShowPanel then
        NPCVendorSortUI:Show()
    else
        NPCVendorSortUI:Hide()
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("MERCHANT_SHOW")
f:RegisterEvent("MERCHANT_UPDATE")
f:RegisterEvent("MERCHANT_CLOSED")

f:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "NPCVendorSort" then
            NVS:InitDB()
            InstallHook()
            self:UnregisterEvent("ADDON_LOADED")
        end

    elseif event == "PLAYER_LOGIN" then
        InstallHook()

        local cls = NVS:GetPlayerClass()
        if cls and NVS.classGear[cls] then
            NVS.classGear = { [cls] = NVS.classGear[cls] }
        end
        self:UnregisterEvent("PLAYER_LOGIN")

    elseif event == "MERCHANT_SHOW" then
        InstallHook()
        NVS:ScanMerchant()
        if NPCVendorSortUI and NPCVendorSortUI.Refresh then
            NPCVendorSortUI:Refresh()
        end
        NVS:UpdatePanelVisibility()
        NVS:Redraw()
        StartRetry()

    elseif event == "MERCHANT_UPDATE" then
        NVS:ScanMerchant()
        if NPCVendorSortUI and NPCVendorSortUI.Refresh then
            NPCVendorSortUI:Refresh()
        end
        NVS:UpdatePanelVisibility()
        EnsureRetry()

    elseif event == "MERCHANT_CLOSED" then
        retry:Hide()
        if NPCVendorSortUI then NPCVendorSortUI:Hide() end
        wipe(NVS.detectedSlots)
        wipe(NVS.visibleItems)
        wipe(NVS.slotCache)
        wipe(NVS.useCache)
        wipe(NVS.requested)
        wipe(NVS.enchantCache)
        NVS.pendingCount = 0
        NVS.pendingCache = false
        NVS:EndRemap()
    end
end)

SLASH_NPCVENDORSORT1 = "/nvs"
SLASH_NPCVENDORSORT2 = "/vendorsort"
SlashCmdList["NPCVENDORSORT"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

    if msg == "reset" then
        for _, slot in ipairs(NVS.slotOrder) do
            NVS:SetSlotEnabled(slot, true)
        end
        NVS:UpdateMerchant()
        NVS.warnedEmpty = nil
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99NPCVendorSort|r: filters reset.")
        return
    end

    if not NPCVendorSortUI then return end

    if NPCVendorSortUI:IsShown() then
        NVS.options.autoShowPanel = false
        NPCVendorSortUI:Hide()
    else
        NVS.options.autoShowPanel = true
        NPCVendorSortUI:Refresh()
        NPCVendorSortUI:Show()
    end
end
