-- =========================================================
-- NPCVendorSort - UI (panel de filtros)
-- WoW 3.3.5a
-- =========================================================

local NVS = NPCVendorSort

local ui = CreateFrame("Frame", "NPCVendorSortUI", MerchantFrame)
NPCVendorSortUI = ui

ui:SetWidth(200)
ui:SetHeight(400)
ui:SetPoint("TOPLEFT", MerchantFrame, "TOPRIGHT", 6, -12)
ui:SetFrameStrata("HIGH")
ui:Hide()

-- Se puede mover
ui:SetMovable(true)
ui:EnableMouse(true)
ui:RegisterForDrag("LeftButton")
ui:SetScript("OnDragStart", function(self) self:StartMoving() end)
ui:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

ui.bg = ui:CreateTexture(nil, "BACKGROUND")
ui.bg:SetAllPoints()
ui.bg:SetTexture(0, 0, 0, 0.75)

ui.border = CreateFrame("Frame", nil, ui)
ui.border:SetAllPoints()
ui.border:SetBackdrop({
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
})
ui.border:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

ui.title = ui:CreateFontString(nil, "OVERLAY", "GameFontNormal")
ui.title:SetPoint("TOP", ui, "TOP", 0, -8)
ui.title:SetText("Vendor Filters")

-- ---------------------------------------------------------
-- Filtro por clase
--
-- Va arriba de todo, antes que los slots, porque es el que mas items
-- esconde. Si estuviera enterrado en Options, ver un vendedor medio vacio
-- no tendria explicacion visible.
-- ---------------------------------------------------------
local function MakeOpt(key, label, y, onChange)
    local cb = CreateFrame("CheckButton", "NPCVendorSortUIOpt_" .. key, ui, "UICheckButtonTemplate")
    cb:SetWidth(20)
    cb:SetHeight(20)
    cb:SetPoint("TOPLEFT", ui, "TOPLEFT", 9, y)

    cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cb.text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cb.text:SetJustifyH("LEFT")
    cb.text:SetText(label)

    cb:SetScript("OnClick", function(self)
        local checked = self:GetChecked() and true or false
        NVS.options[key] = checked
        self:SetChecked(checked)
        PlaySound(checked and "igMainMenuOptionCheckBoxOn" or "igMainMenuOptionCheckBoxOff")
        NVS:InvalidateUseCache()
        if onChange then onChange(checked) end
        NVS:Redraw()
    end)
    return cb
end

ui.classCB = MakeOpt("classFilter", "Usable by my class", -26, function(on)
    if ui.armorCB then
        if on then ui.armorCB:Enable() else ui.armorCB:Disable() end
    end
end)
ui.armorCB = MakeOpt("classArmorOnly", "My armor type only", -46)

ui.classCB:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Usable by my class", 1, 1, 1)
    GameTooltip:AddLine("Hides weapons and armor your class cannot equip. "
        .. "A Paladin stops seeing wands, bows, crossbows and daggers.",
        0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end)
ui.classCB:SetScript("OnLeave", function() GameTooltip:Hide() end)

ui.armorCB:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("My armor type only", 1, 1, 1)
    GameTooltip:AddLine("A Paladin can wear cloth, but does not want to see it. "
        .. "Keeps only the armor type your class uses at your level. "
        .. "Rings, necks, trinkets and shields are never hidden by this.",
        0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end)
ui.armorCB:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- ---------------------------------------------------------
-- Botones Todos / Ninguno
-- ---------------------------------------------------------

local function SetAll(value)
    for _, slot in ipairs(NVS.slotOrder) do
        if NVS.detectedSlots[slot] then
            NVS:SetSlotEnabled(slot, value)
        end
    end
    ui:Refresh()
    NVS:Redraw()
end

ui.allBtn = CreateFrame("Button", nil, ui, "UIPanelButtonTemplate")
ui.allBtn:SetWidth(84)
ui.allBtn:SetHeight(20)
ui.allBtn:SetPoint("TOPLEFT", ui, "TOPLEFT", 10, -70)
ui.allBtn:SetText("All")
ui.allBtn:SetScript("OnClick", function() SetAll(true) end)

ui.noneBtn = CreateFrame("Button", nil, ui, "UIPanelButtonTemplate")
ui.noneBtn:SetWidth(84)
ui.noneBtn:SetHeight(20)
ui.noneBtn:SetPoint("TOPRIGHT", ui, "TOPRIGHT", -10, -70)
ui.noneBtn:SetText("None")
ui.noneBtn:SetScript("OnClick", function() SetAll(false) end)

-- ---------------------------------------------------------
-- Checkboxes
-- ---------------------------------------------------------

ui.checks = {}

local FIRST_Y   = -96
local ROW_H     = 22
local BOTTOM_PAD = 12
local OPT_H     = 30   -- lugar reservado abajo para el boton Options

local function GetCheck(slot)
    local cb = ui.checks[slot]
    if cb then return cb end

    cb = CreateFrame("CheckButton", "NPCVendorSortCheck_" .. slot, ui, "UICheckButtonTemplate")
    cb:SetWidth(22)
    cb:SetHeight(22)
    cb.slot = slot

    cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cb.text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cb.text:SetJustifyH("LEFT")

    cb:SetScript("OnClick", function(self)
        -- GetChecked() en 3.3.5 devuelve 1 o nil, nunca true/false.
        -- Guardarlo tal cual borraba la clave de la tabla de filtros.
        local checked = self:GetChecked() and true or false
        NVS:SetSlotEnabled(self.slot, checked)
        self:SetChecked(checked)
        PlaySound(checked and "igMainMenuOptionCheckBoxOn" or "igMainMenuOptionCheckBoxOff")
        -- Solo redibujar el vendedor. NO llamar a Refresh() aca: mover los
        -- checkbox mientras se esta procesando su propio click era lo que
        -- hacia que parecieran "no responder" o cambiar de casilla.
        NVS:Redraw()
    end)

    ui.checks[slot] = cb
    return cb
end

-- ---------------------------------------------------------
-- Boton de opciones
--
-- El menu de nivel de objeto y colores de calidad existia, pero la unica
-- forma de abrirlo era hacer CLICK DERECHO sobre un botoncito de la ventana
-- del vendedor que ademas solo aparecia si el NPC vendia equipo. O sea:
-- invisible y sin pistas. Aca queda un boton normal, siempre a la vista.
-- ---------------------------------------------------------
ui.optBtn = CreateFrame("Button", nil, ui, "UIPanelButtonTemplate")
ui.optBtn:SetWidth(178)
ui.optBtn:SetHeight(20)
ui.optBtn:SetText("Options")
ui.optBtn:SetScript("OnClick", function()
    local p = NPCVendorSortOptionsPanel
    if not p then return end
    if p:IsShown() then
        p:Hide()
    else
        if p.SyncFromDB then p:SyncFromDB() end
        p:Show()
    end
end)

-- Texto para cuando el vendedor no tiene ninguna categoria detectada
ui.empty = ui:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
ui.empty:SetPoint("TOPLEFT", ui, "TOPLEFT", 10, FIRST_Y)
ui.empty:SetWidth(180)
ui.empty:SetJustifyH("LEFT")
ui.empty:SetText("Nothing to filter here.")
ui.empty:Hide()

-- ---------------------------------------------------------
-- REFRESH
-- ---------------------------------------------------------

function ui:Refresh()
    if not NVS then return end

    -- Los checkbox de clase se ponen al dia en cada refresco: se pueden
    -- cambiar tambien desde el panel de Options y tienen que coincidir.
    local classOn = NVS.options.classFilter and true or false
    self.classCB:SetChecked(classOn)
    self.armorCB:SetChecked(NVS.options.classArmorOnly and true or false)
    if classOn then self.armorCB:Enable() else self.armorCB:Disable() end

    for _, cb in pairs(self.checks) do
        cb:Hide()
    end

    local y = FIRST_Y
    local shown = 0

    -- Recorrer SIEMPRE en el orden fijo de slotOrder. Iterar con pairs() sobre
    -- detectedSlots daba un orden distinto en cada refresco y los checkbox
    -- cambiaban de lugar.
    for _, slot in ipairs(NVS.slotOrder) do
        if NVS.detectedSlots[slot] then
            local cb = GetCheck(slot)
            cb:ClearAllPoints()
            cb:SetPoint("TOPLEFT", self, "TOPLEFT", 8, y)
            cb.text:SetText(NVS.slotNames[slot] or slot)
            cb:SetChecked(NVS:IsSlotEnabled(slot))
            cb:Show()
            y = y - ROW_H
            shown = shown + 1
        end
    end

    if shown == 0 then
        self.empty:Show()
        self:SetHeight(-FIRST_Y + 20 + OPT_H)
        self.optBtn:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 10, 8)
    else
        self.empty:Hide()
        self:SetHeight(-FIRST_Y + shown * ROW_H + OPT_H + BOTTOM_PAD)
        self.optBtn:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 10, 8)
    end
end
