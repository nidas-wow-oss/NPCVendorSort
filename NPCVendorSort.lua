-- =========================================================
-- NPCVendorSort - Core
-- WoW 3.3.5a (Interface 30300)
-- =========================================================

NPCVendorSort = {}
local NVS = NPCVendorSort

NVS.visibleItems  = {}   -- lista de indices reales del vendedor, ya filtrada
NVS.detectedSlots = {}   -- slots presentes en el vendedor actual
NVS.slotCache     = {}   -- itemID -> equipSlot (cache local)
NVS.useCache      = {}   -- itemID -> lo puede usar mi clase?
NVS.pendingCache  = false
NVS.isRedrawing   = false

local OTHER = "NVS_OTHER"   -- pseudo-slot para todo lo que no es equipo

-- Orden FIJO de los slots. pairs() en Lua no garantiza orden: usar una lista
-- ordenada es lo que evita que los checkbox salten de posicion al refrescar.
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

-- Acceso rapido: slot valido?
NVS.validSlot = {}
for _, k in ipairs(NVS.slotOrder) do NVS.validSlot[k] = true end

-- =========================================================
-- SAVED VARIABLES
-- =========================================================

local defaultOptions = {
    showItemLevel     = true,
    showQualityColors = true,
    autoShowPanel     = true,
    classFilter       = true,    -- solo lo que mi clase puede equipar
    classArmorOnly    = false,   -- ademas, solo mi tipo de armadura
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

    -- Cualquier slot desconocido arranca activado
    for _, slot in ipairs(self.slotOrder) do
        if NPCVendorSortDB.filters[slot] == nil then
            NPCVendorSortDB.filters[slot] = true
        end
    end

    -- MIGRACION: destrabar "Other".
    --
    -- Las versiones viejas escondian el panel entero cuando el vendedor no
    -- tenia equipo. Si alguna vez habias destildado "Other", quedaba en
    -- false para siempre y no habia UI para volver a prenderlo: cualquier
    -- vendedor de encantamientos, joyeria, reactivos o recetas se veia
    -- COMPLETAMENTE VACIO, porque nada de eso es equipo.
    --
    -- Se fuerza a true una sola vez. La marca queda guardada, asi que el
    -- dia de mañana lo podes volver a destildar y se respeta.
    if not NPCVendorSortDB.otherUnstuck_v2 then
        NPCVendorSortDB.otherUnstuck_v2 = true
        NPCVendorSortDB.filters[OTHER] = true
    end

    self.filters = NPCVendorSortDB.filters
    self.options = NPCVendorSortDB.options
end

-- Fallback por si algo se ejecuta antes de ADDON_LOADED
NVS.filters = {}
NVS.options = {}
for k, v in pairs(defaultOptions) do NVS.options[k] = v end
for _, slot in ipairs(NVS.slotOrder) do NVS.filters[slot] = true end

function NVS:IsSlotEnabled(slot)
    return self.filters[slot] and true or false
end

function NVS:SetSlotEnabled(slot, enabled)
    -- OJO: nunca asignar nil aqui. Poner nil borra la clave de la tabla,
    -- cambia el layout del hash y era una de las causas de los bugs.
    self.filters[slot] = enabled and true or false
end

-- =========================================================
-- SCAN DEL VENDEDOR
-- =========================================================

local function GetItemIDFromLink(link)
    if not link then return nil end
    local id = link:match("item:(%d+)")
    return id and tonumber(id) or nil
end

-- Devuelve el slot de un item, o nil si el item todavia no esta cacheado
function NVS:GetSlotForIndex(index)
    local link = GetMerchantItemLink(index)
    if not link then return OTHER, true end   -- sin link: tratar como "otros", resuelto

    local id = GetItemIDFromLink(link)
    if id and self.slotCache[id] then
        return self.slotCache[id], true
    end

    local _, _, _, _, _, _, _, _, equipSlot = GetItemInfo(link)
    if equipSlot == nil then
        -- Item aun no cacheado por el cliente. NO decidir todavia.
        return nil, false
    end

    local slot = OTHER
    if equipSlot ~= "" and self.validSlot[equipSlot] then
        slot = equipSlot
    end

    if id then self.slotCache[id] = slot end
    return slot, true
end

function NVS:ScanMerchant()
    wipe(self.detectedSlots)
    self.pendingCache = false

    local n = GetMerchantNumItems()
    for i = 1, n do
        local slot, resolved = self:GetSlotForIndex(i)
        if not resolved then
            self.pendingCache = true
        elseif slot then
            self.detectedSlots[slot] = true
        end
    end
end

function NVS:HasEquipmentSlots()
    for slot in pairs(self.detectedSlots) do
        if slot ~= OTHER then return true end
    end
    return false
end

-- Hay algo que filtrar? = el vendedor tiene al menos una categoria.
--
-- Antes se usaba HasEquipmentSlots para decidir si mostrar el panel y el
-- boton, y ese era el problema de fondo: en un vendedor de encantamientos
-- TODO cae en "Other", asi que no habia equipo, se escondia la interfaz
-- entera, y con "Other" destildado no quedaba manera de darse cuenta ni de
-- arreglarlo. La pregunta correcta no es "hay equipo" sino "hay algo".
function NVS:HasAnythingToFilter()
    return next(self.detectedSlots) ~= nil
end

-- =========================================================
-- FILTRO POR CLASE
--
-- Que puede EQUIPAR cada clase, segun las reglas del juego en 3.3.5a.
--
-- Se usa una tabla fija y no el tooltip. El truco habitual es mirar si la
-- linea del tipo de arma sale en rojo, pero ese rojo tambien aparece por
-- nivel insuficiente o reputacion faltante, y ahi te esconde items que si
-- podes usar, solo que todavia no. La tabla no se equivoca en eso.
--
-- Los nombres son los que devuelve GetItemInfo en cliente ingles, que es
-- el que usa Warmane.
-- =========================================================

local ALL_ARMOR = { Cloth = true, Leather = true, Mail = true, Plate = true }

-- Anillos, cuellos y abalorios llegan como Armor / Miscellaneous: los usa
-- cualquiera, asi que nunca se filtran.
local ARMOR_FREE = { Miscellaneous = true }

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

-- Reliquias: cada una es de una sola clase. Van aparte porque un paladin no
-- tiene que ver idolos de druida aunque ambos sean "Armor".
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

-- El tipo de armadura "propio" de la clase segun el nivel: un paladin de 30
-- todavia usa malla, no placas.
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

-- true = el item se muestra. Ante la duda, SIEMPRE true: es preferible
-- mostrar algo de mas que esconderle al usuario un item que si sirve.
function NVS:CanUse(itemType, itemSubType)
    if itemType ~= "Weapon" and itemType ~= "Armor" then return true end

    local gear = self.classGear[self:GetPlayerClass() or ""]
    if not gear then return true end          -- clase desconocida: no filtrar

    if itemType == "Weapon" then
        return gear.weapon[itemSubType] and true or false
    end

    -- Armor
    if ARMOR_FREE[itemSubType] then return true end        -- anillos, cuellos, abalorios

    local owner = RELIC_OWNER[itemSubType]
    if owner then return owner == self:GetPlayerClass() end

    if not gear.armor[itemSubType] then return false end

    -- "Solo mi tipo de armadura": un paladin puede ponerse tela, pero no
    -- quiere verla. Escudos y demas no entran en esta regla.
    if self.options.classArmorOnly and ALL_ARMOR[itemSubType] then
        local best = self:GetBestArmor()
        if best and itemSubType ~= best then return false end
    end

    return true
end

-- Cache por itemID, igual que el de slots
function NVS:IsUsableIndex(index)
    if not self.options.classFilter then return true end

    local link = GetMerchantItemLink(index)
    if not link then return true end

    local id = GetItemIDFromLink(link)
    if id and self.useCache[id] ~= nil then return self.useCache[id] end

    local _, _, _, _, _, itemType, itemSubType = GetItemInfo(link)
    if itemType == nil then return true end   -- todavia sin cachear: mostrar

    local ok = self:CanUse(itemType, itemSubType)
    if id then self.useCache[id] = ok end
    return ok
end

-- =========================================================
-- LISTA FILTRADA
-- =========================================================

function NVS:BuildVisibleList()
    wipe(self.visibleItems)

    local n = GetMerchantNumItems()
    for i = 1, n do
        local slot, resolved = self:GetSlotForIndex(i)

        -- Si el item aun no esta cacheado se muestra (mejor de mas que de menos)
        if not resolved then
            table.insert(self.visibleItems, i)
        elseif self:IsSlotEnabled(slot) and self:IsUsableIndex(i) then
            table.insert(self.visibleItems, i)
        end
    end

    self:GuardEmptyList()
end

-- Si el filtro dejo la lista en cero pero el vendedor SI tiene items, algo
-- esta mal configurado. Antes eso se veia como un vendedor vacio, sin
-- ninguna pista de por que. Ahora se muestra todo igual y se avisa: es
-- preferible mostrar de mas que hacerle creer al usuario que el NPC no
-- vende nada.
function NVS:GuardEmptyList()
    local n = GetMerchantNumItems()
    if n > 0 and #self.visibleItems == 0 then
        for i = 1, n do
            table.insert(self.visibleItems, i)
        end
        if not self.warnedEmpty then
            self.warnedEmpty = true
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99NPCVendorSort|r: "
                .. "every item here was hidden by your filters, so they are "
                .. "being shown anyway. Use /nvs reset to clear the filters.")
        end
        return true
    end
    return false
end

function NVS:IsFiltering()
    for _, slot in ipairs(self.slotOrder) do
        if not self:IsSlotEnabled(slot) then
            return true
        end
    end
    return false
end

-- =========================================================
-- REMAPEO DE LA API DEL VENDEDOR
--
-- En vez de redibujar a mano (que era lo que rompia precios, monedas
-- alternativas, stock limitado y los items no usables), dejamos que Blizzard
-- dibuje pero le mentimos sobre que items hay. Despues corregimos los IDs de
-- los botones para que comprar siga apuntando al item real.
-- =========================================================

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

-- =========================================================
-- POST-DIBUJADO: IDs reales + nivel de objeto + color de calidad
-- =========================================================

function NVS:FixButtons(filtering)
    local page = MerchantFrame.page or 1

    for i = 1, MERCHANT_ITEMS_PER_PAGE do
        local itemButton = _G["MerchantItem" .. i .. "ItemButton"]
        local holder     = _G["MerchantItem" .. i]
        local nameText   = _G["MerchantItem" .. i .. "Name"]
        if itemButton then
            local shown = holder and holder:IsShown()
            local realIndex
            if filtering then
                local virtual = (page - 1) * MERCHANT_ITEMS_PER_PAGE + i
                realIndex = self.visibleItems[virtual]
                if realIndex then
                    -- Esto es lo que hace que BuyMerchantItem y el tooltip
                    -- apunten al item correcto y no al de la lista filtrada.
                    itemButton:SetID(realIndex)
                    if holder then holder:SetID(realIndex) end
                end
            else
                realIndex = itemButton:GetID()
                -- Restaurar el ID original del contenedor (era i por XML)
                if holder then holder:SetID(i) end
            end
            if not shown then realIndex = nil end

            -- Nivel de objeto
            local levelText = itemButton.nvsLevel
            if self.options.showItemLevel and realIndex then
                local link = GetMerchantItemLink(realIndex)
                local ilvl
                if link then
                    local _, _, _, lvl = GetItemInfo(link)
                    ilvl = lvl
                end
                if ilvl and ilvl > 1 then
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

            -- Color de calidad en el nombre
            if nameText then
                local applied = false
                if self.options.showQualityColors and realIndex then
                    local link = GetMerchantItemLink(realIndex)
                    if link then
                        local _, _, quality = GetItemInfo(link)
                        if quality then
                            local r, g, b = GetItemQualityColor(quality)
                            nameText:SetTextColor(r, g, b)
                            applied = true
                        end
                    end
                end
                if not applied then
                    nameText:SetTextColor(1, 0.82, 0)
                end
            end
        end
    end
end

-- =========================================================
-- REDIBUJADO
-- =========================================================

function NVS:Redraw()
    if not MerchantFrame or not MerchantFrame:IsShown() then return end
    if MerchantFrame.selectedTab ~= 1 then return end
    if self.isRedrawing then return end
    -- No pisar la ventana de dividir pilas mientras esta abierta
    if StackSplitFrame and StackSplitFrame:IsShown() then return end

    self.isRedrawing = true
    local ok, err = pcall(MerchantFrame_Update)
    -- Pase lo que pase hay que liberar el flag y restaurar la API, si no el
    -- addon queda trabado para el resto de la sesion.
    self.isRedrawing = false
    self:EndRemap()
    if not ok then geterrorhandler()(err) end
end

-- Envoltura sobre el dibujado nativo del vendedor
local function DrawWrapper(originalFn, ...)
    if MerchantFrame.selectedTab ~= 1 then
        return originalFn(...)
    end

    -- Siempre reconstruimos la lista: asi nunca queda desactualizada.
    NVS:BuildVisibleList()

    -- Solo tocamos la API si el filtro realmente saca algo.
    local filtering = (#NVS.visibleItems ~= GetMerchantNumItems())

    if filtering then
        -- Ajustar la pagina si la lista filtrada se hizo mas corta
        local total = math.ceil(#NVS.visibleItems / MERCHANT_ITEMS_PER_PAGE)
        if total < 1 then total = 1 end
        if (MerchantFrame.page or 1) > total then
            MerchantFrame.page = total
        end
        if (MerchantFrame.page or 1) < 1 then
            MerchantFrame.page = 1
        end

        NVS:BeginRemap()
        local ok, err = pcall(originalFn, ...)
        NVS:EndRemap()
        if not ok then
            geterrorhandler()(err)
        end
    else
        originalFn(...)
    end

    local ok2, err2 = pcall(NVS.FixButtons, NVS, filtering)
    if not ok2 then geterrorhandler()(err2) end
end

-- Envolvemos MerchantFrame_Update (y no MerchantFrame_UpdateMerchantInfo)
-- porque es el unico punto de entrada: eventos, botones de pagina y cambio de
-- pestana pasan todos por aca. Ademas el estado de los botones Anterior/
-- Siguiente se calcula dentro, asi que queda bien con la lista filtrada.
local hooked = false
local function InstallHook()
    if hooked then return end
    if type(_G.MerchantFrame_Update) == "function" then
        local original = _G.MerchantFrame_Update
        _G.MerchantFrame_Update = function(...)
            return DrawWrapper(original, ...)
        end
        hooked = true
    end
end

-- Instalar lo antes posible (FrameXML ya esta cargado en este punto)
InstallHook()

-- Compatibilidad: el resto del addon llamaba a UpdateMerchant()
-- Al cambiar cualquier opcion del filtro de clase hay que tirar el cache:
-- guarda el resultado de CanUse, que depende de esas mismas opciones.
function NVS:InvalidateUseCache()
    wipe(self.useCache)
end

function NVS:UpdateMerchant()
    self:Redraw()
    if NPCVendorSortUI and NPCVendorSortUI.Refresh then
        NPCVendorSortUI:Refresh()
    end
end

-- =========================================================
-- REINTENTO PARA ITEMS NO CACHEADOS
-- Si el cliente todavia no bajo la info de un item, GetItemInfo devuelve nil
-- y el filtro no sabria a que categoria pertenece. Reintentamos un rato.
-- =========================================================

local retry = CreateFrame("Frame")
retry.elapsed = 0
retry.tries = 0
retry:Hide()
retry:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < 0.25 then return end
    self.elapsed = 0
    self.tries = self.tries + 1

    if not MerchantFrame or not MerchantFrame:IsShown() then
        self:Hide()
        return
    end

    NVS:ScanMerchant()
    if NPCVendorSortUI and NPCVendorSortUI.Refresh then
        NPCVendorSortUI:Refresh()
    end
    NVS:Redraw()

    if not NVS.pendingCache or self.tries >= 24 then
        self:Hide()
    end
end)

local function StartRetry()
    retry.elapsed = 0
    retry.tries = 0
    if NVS.pendingCache then retry:Show() else retry:Hide() end
end

-- =========================================================
-- PANEL: mostrar / ocultar
-- =========================================================

function NVS:UpdatePanelVisibility()
    if not NPCVendorSortUI then return end
    if self:HasAnythingToFilter() and self.options.autoShowPanel then
        NPCVendorSortUI:Show()
    else
        NPCVendorSortUI:Hide()
    end
end

-- =========================================================
-- EVENTOS
-- =========================================================

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("MERCHANT_SHOW")
f:RegisterEvent("MERCHANT_UPDATE")
f:RegisterEvent("MERCHANT_CLOSED")

f:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "NPCVendorSort" then
            NVS:InitDB()
            InstallHook()
        end

    elseif event == "PLAYER_LOGIN" then
        InstallHook()

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
        -- El propio MerchantFrame ya se redibuja con este evento; nuestro
        -- wrapper se encarga. No forzamos otro Redraw para no recursar.

    elseif event == "MERCHANT_CLOSED" then
        retry:Hide()
        if NPCVendorSortUI then NPCVendorSortUI:Hide() end
        wipe(NVS.detectedSlots)
        wipe(NVS.visibleItems)
        NVS:EndRemap()   -- red de seguridad
    end
end)

-- Al cambiar de pestana (Comprar / Recomprar) hay que volver a dibujar bien
if MerchantFrame then
    local tab1 = _G["MerchantFrameTab1"]
    if tab1 then
        tab1:HookScript("OnClick", function()
            if MerchantFrame:IsShown() then NVS:Redraw() end
        end)
    end
end

-- =========================================================
-- SLASH COMMANDS
-- =========================================================

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
        NPCVendorSortUI:Hide()
    else
        NPCVendorSortUI:Show()
        NPCVendorSortUI:Refresh()
    end
end
