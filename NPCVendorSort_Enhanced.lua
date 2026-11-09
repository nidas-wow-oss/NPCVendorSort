local NVS = NPCVendorSort

local filterButton = CreateFrame("Button", "NPCVendorSortFilterButton", MerchantFrame)
filterButton:SetWidth(22)
filterButton:SetHeight(22)
filterButton:SetPoint("TOPRIGHT", MerchantFrame, "TOPRIGHT", -58, -10)
filterButton:Hide()

filterButton.icon = filterButton:CreateTexture(nil, "ARTWORK")
filterButton.icon:SetAllPoints()
filterButton.icon:SetTexture("Interface\\Buttons\\UI-PlusButton-Up")

filterButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

local function UpdateFilterButtonIcon()
    if NPCVendorSortUI and NPCVendorSortUI:IsShown() then
        filterButton.icon:SetTexture("Interface\\Buttons\\UI-MinusButton-Up")
    else
        filterButton.icon:SetTexture("Interface\\Buttons\\UI-PlusButton-Up")
    end
end

filterButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("NPC Vendor Sort", 1, 1, 1)
    GameTooltip:AddLine("Click: show / hide the filters", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Right-click: options", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end)

filterButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
filterButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")

local optionsPanel = CreateFrame("Frame", "NPCVendorSortOptionsPanel", MerchantFrame)
optionsPanel:SetWidth(200)
optionsPanel:SetHeight(80)
optionsPanel:SetPoint("TOPRIGHT", MerchantFrame, "BOTTOMRIGHT", 0, -6)
optionsPanel:SetFrameStrata("HIGH")
optionsPanel:Hide()

optionsPanel.bg = optionsPanel:CreateTexture(nil, "BACKGROUND")
optionsPanel.bg:SetAllPoints()
optionsPanel.bg:SetTexture(0, 0, 0, 0.75)

optionsPanel.border = CreateFrame("Frame", nil, optionsPanel)
optionsPanel.border:SetAllPoints()
optionsPanel.border:SetBackdrop({
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
})
optionsPanel.border:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

optionsPanel.title = optionsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
optionsPanel.title:SetPoint("TOPLEFT", 10, -8)
optionsPanel.title:SetText("Options")

local function MakeOptionCheck(key, label, y)
    local cb = CreateFrame("CheckButton", "NPCVendorSortOpt_" .. key, optionsPanel, "UICheckButtonTemplate")
    cb:SetWidth(22)
    cb:SetHeight(22)
    cb:SetPoint("TOPLEFT", 8, y)

    cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cb.text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cb.text:SetText(label)

    cb:SetScript("OnClick", function(self)
        local checked = self:GetChecked() and true or false
        NVS.options[key] = checked
        self:SetChecked(checked)
        PlaySound(checked and "igMainMenuOptionCheckBoxOn" or "igMainMenuOptionCheckBoxOff")
        NVS:Redraw()
    end)

    return cb
end

optionsPanel.showLevelCB  = MakeOptionCheck("showItemLevel",     "Show item level",   -28)
optionsPanel.showColorsCB = MakeOptionCheck("showQualityColors", "Quality colors",    -50)

function optionsPanel:SyncFromDB()
    self.showLevelCB:SetChecked(NVS.options.showItemLevel and true or false)
    self.showColorsCB:SetChecked(NVS.options.showQualityColors and true or false)
end

filterButton:SetScript("OnClick", function(self, button)
    if button == "RightButton" then
        if optionsPanel:IsShown() then
            optionsPanel:Hide()
        else
            optionsPanel:SyncFromDB()
            optionsPanel:Show()
        end
        return
    end

    if NPCVendorSortUI then
        if NPCVendorSortUI:IsShown() then
            NPCVendorSortUI:Hide()
            NVS.options.autoShowPanel = false
        else
            NVS.options.autoShowPanel = true
            NPCVendorSortUI:Refresh()
            NPCVendorSortUI:Show()
        end
        UpdateFilterButtonIcon()
    end
end)

local ev = CreateFrame("Frame")
ev:RegisterEvent("MERCHANT_SHOW")
ev:RegisterEvent("MERCHANT_UPDATE")
ev:RegisterEvent("MERCHANT_CLOSED")

ev:SetScript("OnEvent", function(_, event)
    if event == "MERCHANT_CLOSED" then
        optionsPanel:Hide()
        filterButton:Hide()
        return
    end

    optionsPanel:SyncFromDB()

    filterButton:Show()

    UpdateFilterButtonIcon()
end)

if NPCVendorSortUI then
    NPCVendorSortUI:HookScript("OnShow", UpdateFilterButtonIcon)
    NPCVendorSortUI:HookScript("OnHide", UpdateFilterButtonIcon)
end
