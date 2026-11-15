---------------------------------------------------------------
-- FAT_UI.lua - panneau d'options (/fat) et indicateur discret.
-- Fenetre sombre et plate, un accent unique (reglable), barre
-- d'onglets a gauche : Sorts | Filtres | Options | Profils | Aide.
-- Tous les cadres sont crees une seule fois au chargement (jamais a
-- l'ouverture ni en combat) ; aucun OnUpdate : le panneau se
-- rafraichit sur action. Widgets reutilisables : FAT_Widgets.lua.
-- Lua 5.0 : widgets 1.12 uniquement, pas de varargs.
---------------------------------------------------------------

local FAT = FredoAutoTarget
local Tr = FAT.Tr
local UI = FAT.UI
local Wd = FAT.Wd
local C = Wd.C

UI.W = 768
UI.H = 584
UI.ROWS = 11
UI.off = 0
UI.stacks = {}

-- ========= Donnees d'affichage =========
-- libelles courts (boutons et cartes)
UI.SHORT = { keep = "Garder", range = "A portee", nearest = "Proche", assist = "Assister", mark = "Priorite",
	weak = "Faible", caster = "Lanceur", heal = "Soigner", none = "Aucun" }

UI.SORT_LABEL = { slot = "Tri : liste", name = "Tri : nom", mode = "Tri : mode" }

-- couleur de la puce de mode : voir Wd.MODE (palette unique, FAT_Widgets.lua)
UI.MODE_COL = Wd.MODE

UI.MODE_ICON = {
	keep = "Interface\\Icons\\Ability_Marksmanship",
	range = "Interface\\Icons\\Ability_Hunter_SniperShot",
	nearest = "Interface\\Icons\\Ability_Warrior_Charge",
	assist = "Interface\\Icons\\Ability_Warrior_RallyingCry",
	mark = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
	weak = "Interface\\Icons\\INV_Sword_48",
	caster = "Interface\\Icons\\Spell_Frost_IceShock",
	heal = "Interface\\Icons\\Spell_Holy_FlashHeal",
	none = "Interface\\Icons\\Spell_ChargeNegative",
}

UI.UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
UI.ATTACK_ICON = "Interface\\Icons\\Ability_MeleeDamage"

UI.TAB_ICON = {
	"Interface\\Icons\\INV_Misc_Book_09",
	"Interface\\Icons\\INV_Misc_Eye_01",
	"Interface\\Icons\\INV_Misc_Gear_01",
	"Interface\\Icons\\INV_Misc_Note_01",
	"Interface\\Icons\\INV_Misc_QuestionMark",
}

-- icones de classe du client (UI-CharacterCreate-Classes) : gauche, droite, haut, bas
UI.CLASS_TEX = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
UI.CLASS_ICON = {
	WARRIOR = { 0, 0.25, 0, 0.25 },
	MAGE = { 0.25, 0.49609375, 0, 0.25 },
	ROGUE = { 0.49609375, 0.7421875, 0, 0.25 },
	DRUID = { 0.7421875, 0.98828125, 0, 0.25 },
	HUNTER = { 0, 0.25, 0.25, 0.5 },
	SHAMAN = { 0.25, 0.49609375, 0.25, 0.5 },
	PRIEST = { 0.49609375, 0.7421875, 0.25, 0.5 },
	WARLOCK = { 0.7421875, 0.98828125, 0.25, 0.5 },
	PALADIN = { 0, 0.25, 0.5, 0.75 },
}

UI.ACC_NAME = { class = "Couleur de classe", blue = "Bleu", green = "Vert", orange = "Orange", purple = "Violet", pink = "Rose" }

UI.FILTER_ROWS = { "combat", "dist", "pets", "cc", "tapped", "los", "pvpsafe", "pull" }

-- "SHIFT-CTRL-F" -> "S-C-F" (tient dans un badge etroit)
function UI.ShortKey(k)
	k = tostring(k)
	k = string.gsub(k, "SHIFT%-", "S-")
	k = string.gsub(k, "CTRL%-", "C-")
	k = string.gsub(k, "ALT%-", "A-")
	return k
end

-- ========= Acces a l'entree selectionnee =========
function UI.Cur()
	if UI.sel and FAT.DB then
		return FAT.DB.spells[UI.sel]
	end
	return nil
end

function FAT.UIRefresh()
	if FAT.RefreshPanel then
		FAT.RefreshPanel()
	end
	if FAT.RefreshIndicator then
		FAT.RefreshIndicator()
	end
end

-- ordre d'affichage : "slot" (liste), "name" (alphabetique), "mode"
function UI.Order()
	local out = {}
	local i = 1
	while i <= FAT.MAX_SLOTS do
		if FAT.DB.spells[i] then
			tinsert(out, i)
		end
		i = i + 1
	end
	local sortBy = FAT.DB.ui and FAT.DB.ui.sort or "slot"
	if sortBy == "name" then
		table.sort(out, function(a, b)
			return FAT.Norm(FAT.DB.spells[a].name) < FAT.Norm(FAT.DB.spells[b].name)
		end)
	elseif sortBy == "mode" then
		table.sort(out, function(a, b)
			local ma, mb = FAT.DB.spells[a].mode, FAT.DB.spells[b].mode
			if ma ~= mb then
				return ma < mb
			end
			return a < b
		end)
	end
	return out
end

-- premiere phrase d'un texte d'aide (sous-titre d'une ligne)
function UI.First(s)
	local i = string.find(s or "", ". ", 1, true)
	if i then
		return string.sub(s, 1, i)
	end
	return s or ""
end

-- ========= Ajout =========
function FAT.UIAdd()
	local box = FAT.addBox
	if not box then
		return
	end
	local name = FAT.Trim(box:GetText())
	if name == "" then
		return
	end
	local idx = FAT.AddEntry(name, nil, nil, false, true)
	if idx then
		box:SetText("")
		box:ClearFocus()
		UI.sel = idx
		FAT.UIRefresh()
	end
end

-- ========= Capture d'une touche =========
function UI.StopCapture()
	local cap = UI.keyCapture
	cap:EnableKeyboard(false)
	cap:Hide()
	cap.slot = nil
	FAT.UIRefresh()
end

function UI.OnCaptureKey()
	local key = arg1
	local slot = this.slot
	if not slot then
		return
	end
	if key == "ESCAPE" then
		UI.StopCapture()
		return
	end
	if key == "UNKNOWN" or key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL"
		or key == "LALT" or key == "RALT" then
		return
	end
	local combo = key
	-- ordre canonique du client : ALT-CTRL-SHIFT-touche
	if IsShiftKeyDown() then combo = "SHIFT-" .. combo end
	if IsControlKeyDown() then combo = "CTRL-" .. combo end
	if IsAltKeyDown() then combo = "ALT-" .. combo end
	local e = FAT.DB.spells[slot]
	if not e then
		UI.StopCapture()
		return
	end
	-- touche deja utilisee par un autre groupe de l'addon : le sort le rejoint
	local prev = GetBindingAction and GetBindingAction(combo)
	local _, _, gs = string.find(prev or "", "^FREDOAUTOTARGET_SLOT(%d+)$")
	if gs then
		e.key = tonumber(gs)
		FAT.UpdateBindingNames()
		FAT.p(Tr("%s ajoute a la touche %s (priorite : ordre de la liste).", e.name, combo))
		UI.StopCapture()
		return
	end
	-- sinon : groupe propre (nouveau si le groupe actuel est partage)
	local _, cnt = FAT.GroupEntries(e.key)
	if cnt > 1 then
		e.key = FAT.FreeGroup()
	end
	local cmd = "FREDOAUTOTARGET_SLOT" .. e.key
	local o1, o2 = GetBindingKey(cmd)
	if o1 then SetBinding(o1) end
	if o2 then SetBinding(o2) end
	if prev and prev ~= "" and prev ~= cmd then
		FAT.p(Tr("|cffff8800Attention|r : %s etait lie a %s (remplace).", combo, prev))
	end
	SetBinding(combo, cmd)
	SaveBindings(GetCurrentBindingSet())
	FAT.UpdateBindingNames()
	FAT.p(Tr("Touche de %s -> %s", e.name, combo))
	UI.StopCapture()
end

-- ========= Liste : cartes =========
function UI.PaintCard(b)
	local A = Wd.acc
	local bg, bd = C.card, C.line
	if b.sel then
		bg = Wd.Mix(C.card, A, 0.16)
		bd = Wd.Mix(C.line, A, 0.55)
	elseif b.dn then
		bg = C.press
	elseif b.hv then
		bg = C.hover
		bd = Wd.Mix(C.line, A, 0.4)
	end
	b:SetBackdropColor(bg[1], bg[2], bg[3], 1)
	b:SetBackdropBorderColor(bd[1], bd[2], bd[3], 1)
	if b.sel then
		b.bar:Show()
	else
		b.bar:Hide()
	end
end

function UI.ToolsShow(b, on)
	local k = 1
	while b.tools[k] do
		if on and b.slot then
			b.tools[k]:Show()
		else
			b.tools[k]:Hide()
		end
		k = k + 1
	end
end

-- la souris quitte la carte : on garde les boutons si elle est sur l'un d'eux
function UI.Over(f)
	local mo = FAT.Api("MouseIsOver")
	if mo then
		return mo(f) and true or false
	end
	-- repli : position du curseur contre le rectangle du cadre (coordonnees ecran)
	local cx, cy = GetCursorPosition()
	local sc = f:GetEffectiveScale()
	local l, r, t, bt = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
	if not (cx and cy and sc and sc > 0 and l and r and t and bt) then
		return false
	end
	cx = cx / sc
	cy = cy / sc
	return cx >= l and cx <= r and cy >= bt and cy <= t
end

function UI.HoverEnd(b)
	if UI.Over(b) then
		return
	end
	b.hv = nil
	b.dn = nil
	UI.PaintCard(b)
	UI.ToolsShow(b, false)
end

function UI.RowEnter()
	local b = this
	b.hv = true
	UI.PaintCard(b)
	UI.ToolsShow(b, true)
	Wd.ShowTip()
end

function UI.RowLeave()
	GameTooltip:Hide()
	UI.HoverEnd(this)
end

function UI.RowClick(b)
	if b.slot then
		UI.sel = b.slot
		FAT.UIRefresh()
	end
end

function UI.ToolLeave()
	this.hv = nil
	this.dn = nil
	this.paint(this)
	GameTooltip:Hide()
	UI.HoverEnd(this.card)
end

function UI.Remove(idx)
	if not FAT.DB.spells[idx] then
		return
	end
	if UI.keyCapture.slot == idx then
		UI.StopCapture()
	end
	FAT.RemoveEntry(idx)
	if UI.sel == idx then
		UI.sel = nil
	end
	FAT.UIRefresh()
end

-- echange le sort avec son voisin de liste (l'ordre de la liste fixe la priorite des touches)
function UI.Move(slot, dir)
	if ((FAT.DB.ui and FAT.DB.ui.sort) or "slot") ~= "slot" then
		return
	end
	local j = slot + dir
	while j >= 1 and j <= FAT.MAX_SLOTS and (not FAT.DB.spells[j]) do
		j = j + dir
	end
	if j < 1 or j > FAT.MAX_SLOTS or (not FAT.DB.spells[slot]) then
		return
	end
	local t = FAT.DB.spells[slot]
	FAT.DB.spells[slot] = FAT.DB.spells[j]
	FAT.DB.spells[j] = t
	if UI.sel == slot then
		UI.sel = j
	elseif UI.sel == j then
		UI.sel = slot
	end
	local cap = UI.keyCapture
	if cap.slot == slot then
		cap.slot = j
	elseif cap.slot == j then
		cap.slot = slot
	end
	FAT.UpdateBindingNames()
	FAT.SyncEvents()
	FAT.UIRefresh()
end

function UI.ToolClick(t)
	local slot = t.card.slot
	if not slot then
		return
	end
	if t.tool == "del" then
		UI.Remove(slot)
	elseif t.tool == "up" then
		UI.Move(slot, -1)
	else
		UI.Move(slot, 1)
	end
end

function UI.OnWheel()
	local d = arg1
	if not d then
		return
	end
	local maxOff = math.max(0, (UI.count or 0) - UI.ROWS)
	local o = UI.off - d
	if o < 0 then o = 0 end
	if o > maxOff then o = maxOff end
	if o ~= UI.off then
		UI.off = o
		FAT.UIRefresh()
	end
end

UI.TOOLS = {
	{ "^", "Monter", "Monte ce sort dans la liste (la priorite des touches suit l'ordre de la liste).", "Disponible avec le tri 'liste'.", "up" },
	{ "v", "Descendre", "Descend ce sort dans la liste (la priorite des touches suit l'ordre de la liste).", "Disponible avec le tri 'liste'.", "down" },
	{ "x", "Supprimer ce sort", "Retire le sort de la liste (sa touche est liberee si plus aucun sort ne l'utilise).", nil, "del" },
}

function UI.MakeRow(page, n)
	local b = CreateFrame("Button", nil, page)
	b:SetWidth(228)
	b:SetHeight(32)
	b.n = n
	b.act = UI.RowClick
	Wd.Box(b, C.card, C.line)
	b.bar = Wd.AccTexture(b, "OVERLAY", 1, 3, 30)
	b.bar:SetPoint("LEFT", b, "LEFT", 1, 0)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetWidth(24)
	b.icon:SetHeight(24)
	b.icon:SetPoint("LEFT", b, "LEFT", 8, 0)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.tx = Wd.Line(b, "body", "", 128)
	b.tx:SetPoint("TOPLEFT", b, "TOPLEFT", 38, -3)
	b.chip = Wd.Tex(b, "ARTWORK", C.line, 0.3, 52, 12)
	b.chip:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 38, 4)
	b.chipTx = Wd.Line(b, "small", "", 52)
	b.chipTx:SetPoint("CENTER", b.chip, "CENTER", 0, 0)
	b.chipTx:SetJustifyH("CENTER")
	b.badge = Wd.Tex(b, "ARTWORK", C.line, 1, 44, 12)
	b.badge:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 94, 4)
	b.badgeTx = Wd.Line(b, "small", "", 44)
	b.badgeTx:SetPoint("CENTER", b.badge, "CENTER", 0, 0)
	b.badgeTx:SetJustifyH("CENTER")
	b.atk = b:CreateTexture(nil, "ARTWORK")
	b.atk:SetTexture(UI.ATTACK_ICON)
	b.atk:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.atk:SetWidth(12)
	b.atk:SetHeight(12)
	b.atk:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 144, 4)
	b:RegisterForClicks("LeftButtonUp")
	b:SetScript("OnClick", Wd.OnClick)
	b:EnableMouseWheel(true)
	b:SetScript("OnMouseWheel", UI.OnWheel)
	Wd.Tip(b, "Sort de la liste", "Clique pour regler ce sort (mode, repli, auto-attaque, touche, filtres).",
		"Puce : mode. Badge : touche. Epees : auto-attaque. Survole la carte pour monter, descendre ou supprimer.")
	b.tools = {}
	local k = 1
	while UI.TOOLS[k] do
		local d = UI.TOOLS[k]
		local t = Wd.Button(b, 16, 16, "", UI.ToolClick, "ghost", d[2], d[3], d[4])
		t:SetText(d[1])
		t:SetPoint("TOPRIGHT", b, "TOPRIGHT", -4 - ((3 - k) * 18), -4)
		t.card = b
		t.tool = d[5]
		t:SetScript("OnLeave", UI.ToolLeave)
		t:Hide()
		b.tools[k] = t
		k = k + 1
	end
	b.paint = UI.PaintCard
	b:SetScript("OnEnter", UI.RowEnter)
	b:SetScript("OnLeave", UI.RowLeave)
	b:SetScript("OnMouseDown", Wd.OnDown)
	b:SetScript("OnMouseUp", Wd.OnUp)
	b:SetScript("OnHide", Wd.OnHideW)
	tinsert(Wd.all, b)
	UI.PaintCard(b)
	return b
end

function UI.FillRow(b, slot, e, pos, n, slotSort)
	b.slot = slot
	b.sel = (slot == UI.sel) or nil
	b.tx:SetText(e.name)
	b.icon:SetTexture(FAT.SpellIcon(e.name) or UI.UNKNOWN_ICON)
	local mc = UI.MODE_COL[e.mode] or C.muted
	b.chip:SetVertexColor(mc[1], mc[2], mc[3], 0.25)
	b.chipTx:SetTextColor(mc[1], mc[2], mc[3])
	b.chipTx:SetText(Tr(UI.SHORT[e.mode] or e.mode))
	local k1 = GetBindingKey("FREDOAUTOTARGET_SLOT" .. e.key)
	b.badgeTx:SetText(k1 and UI.ShortKey(k1) or "-")
	if k1 then
		b.badgeTx:SetTextColor(C.text[1], C.text[2], C.text[3])
	else
		b.badgeTx:SetTextColor(C.faint[1], C.faint[2], C.faint[3])
	end
	if e.attack then
		b.atk:Show()
	else
		b.atk:Hide()
	end
	Wd.SetDisabled(b.tools[1], (not slotSort) or pos == 1)
	Wd.SetDisabled(b.tools[2], (not slotSort) or pos == n)
	UI.PaintCard(b)
end

function UI.RefreshList(order)
	local n = 0
	while order[n + 1] do
		n = n + 1
	end
	UI.count = n
	local R = UI.ROWS
	-- la selection reste visible quand elle change
	if UI.sel ~= UI.lastSel then
		UI.lastSel = UI.sel
		local p = 0
		local k = 1
		while order[k] do
			if order[k] == UI.sel then
				p = k
			end
			k = k + 1
		end
		if p > 0 then
			if p <= UI.off then
				UI.off = p - 1
			elseif p > (UI.off + R) then
				UI.off = p - R
			end
		end
	end
	local maxOff = math.max(0, n - R)
	if UI.off > maxOff then UI.off = maxOff end
	if UI.off < 0 then UI.off = 0 end
	local slotSort = ((FAT.DB.ui and FAT.DB.ui.sort) or "slot") == "slot"
	local i = 1
	while i <= R do
		local b = UI.rows[i]
		local slot = order[UI.off + i]
		local e = slot and FAT.DB.spells[slot]
		if e then
			UI.FillRow(b, slot, e, UI.off + i, n, slotSort)
			b:Show()
		else
			b.slot = nil
			b.sel = nil
			b.hv = nil
			UI.ToolsShow(b, false)
			b:Hide()
		end
		i = i + 1
	end
	-- barre de defilement
	if n > R then
		local th = math.max(16, math.floor((UI.trackH * R) / n))
		UI.thumb:SetHeight(th)
		UI.thumb:ClearAllPoints()
		UI.thumb:SetPoint("TOPLEFT", UI.track, "TOPLEFT", 0, -math.floor(((UI.trackH - th) * UI.off) / maxOff))
		UI.track:Show()
		UI.thumb:Show()
	else
		UI.track:Hide()
		UI.thumb:Hide()
	end
	UI.listHead:SetText(Tr("Liste (%d/%d)", n, FAT.MAX_SLOTS))
	if order[1] then
		UI.emptyText:SetText("")
		UI.hintText:SetText("")
	else
		UI.emptyText:SetText(Tr("Liste vide : clique 'Preset' ou ajoute un sort."))
		UI.hintText:SetText(Tr("Lance un sort puis 'Dernier sort lance', ou ecris son nom, ou Maj+clic dans le livre de sorts. Clique un sort pour le regler."))
	end
	local cls = FAT.PlayerClass()
	UI.presetBtn:SetText(Tr("Preset %s", tostring(FAT.CLASS_LABEL[cls] or cls or "?")))
	UI.sortBtn:SetText(Tr(UI.SORT_LABEL[(FAT.DB.ui and FAT.DB.ui.sort) or "slot"] or UI.SORT_LABEL.slot))
end

-- ========= Onglet Sorts : construction =========
function UI.LastClick()
	local idx = FAT.AddLast()
	if idx then
		UI.sel = idx
		FAT.UIRefresh()
	else
		FAT.p(Tr("Lance d'abord un sort (barre d'action, macro ou livre de sorts), puis clique ici."))
	end
end

function UI.PresetClick()
	local cls = FAT.PlayerClass()
	local n = FAT.AddPreset(cls)
	FAT.p(Tr("Preset %s : %d sort(s) ajoute(s).", tostring(FAT.CLASS_LABEL[cls] or cls), n))
	FAT.UIRefresh()
end

function UI.SortClick(b, btn)
	FAT.DB.ui = FAT.DB.ui or {}
	local cur = FAT.DB.ui.sort or "slot"
	local order = { "slot", "name", "mode" }
	FAT.DB.ui.sort = FAT.CycleIn(order, cur, btn == "RightButton")
	FAT.UIRefresh()
end

function UI.BuildSortsLeft(page)
	local box = Wd.Input(page, 156, 28, 60, function() FAT.UIAdd() end,
		"Nom du sort",
		"Ecris le nom du sort tel qu'il apparait dans ton livre de sorts (le rang est ignore), puis Entree ou Ajouter.",
		"Astuce : garde cette case active et fais Maj+clic sur un sort du livre de sorts pour l'ajouter.")
	Wd.At(box, page, 0, 0)
	FAT.addBox = box
	UI.addBtn = Wd.At(Wd.Button(page, 76, 28, "Ajouter", function() FAT.UIAdd() end, "accent",
		"Ajouter le sort", "Ajoute le sort ecrit a gauche. Le mode est choisi selon ta classe (soin = Soigner, sinon A portee)."), page, 160, 0)
	UI.lastBtn = Wd.At(Wd.Button(page, 120, 24, "Dernier sort lance", UI.LastClick, "normal",
		"Ajouter le dernier sort lance",
		"Lance un sort une fois (barre d'action, macro ou livre de sorts) puis clique ici : il est ajoute a la liste."), page, 0, 32)
	UI.presetBtn = Wd.At(Wd.Button(page, 112, 24, "", UI.PresetClick, "normal", "Preset de ta classe",
		"Ajoute les sorts courants de ta classe qui sont dans ton livre de sorts (modes et auto-attaque pre-regles). Tu peux tout modifier ensuite."), page, 124, 32)
	UI.listHead = Wd.At(Wd.Line(page, "label", "", 130), page, 2, 66)
	UI.sortBtn = Wd.At(Wd.Button(page, 96, 16, "", UI.SortClick, "ghost", "Tri de la liste",
		"Clic : liste, nom, mode. Ne change pas la priorite des touches (ordre de la liste)."), page, 140, 64)
	UI.sortBtn.fs:SetJustifyH("RIGHT")
	UI.sortBtn.fs:ClearAllPoints()
	UI.sortBtn.fs:SetPoint("RIGHT", UI.sortBtn, "RIGHT", -4, 0)
	UI.trackH = (UI.ROWS * 36) - 4
	local n = 1
	while n <= UI.ROWS do
		local b = UI.MakeRow(page, n)
		Wd.At(b, page, 0, 84 + ((n - 1) * 36))
		UI.rows[n] = b
		n = n + 1
	end
	-- barre de defilement (fine, a l'accent)
	UI.track = Wd.Tex(page, "BACKGROUND", C.line, 0.6, 3, UI.trackH)
	UI.track:SetPoint("TOPLEFT", page, "TOPLEFT", 233, -84)
	UI.thumb = Wd.AccTexture(page, "ARTWORK", 1, 3, 16)
	UI.thumb:SetPoint("TOPLEFT", UI.track, "TOPLEFT", 0, 0)
	-- zone de la liste : molette
	local wheel = CreateFrame("Frame", nil, page)
	wheel:SetWidth(236)
	wheel:SetHeight(UI.trackH)
	wheel:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -84)
	wheel:EnableMouseWheel(true)
	wheel:SetScript("OnMouseWheel", UI.OnWheel)
	wheel.lvl = 0 -- au niveau de la page : sous les cartes (UI.FixLevels)
	wheel:SetFrameLevel(page:GetFrameLevel())
	UI.wheel = wheel
	-- etat vide
	UI.emptyText = Wd.Text(page, "dense", "", 224, 40)
	UI.emptyText:SetPoint("TOPLEFT", page, "TOPLEFT", 8, -96)
	UI.hintText = Wd.Text(page, "help", "", 224, 120)
	UI.hintText:SetPoint("TOPLEFT", page, "TOPLEFT", 8, -140)
end

-- ========= Onglet Sorts : detail du sort =========
function UI.ModeClick(key)
	local e = UI.Cur()
	if e then
		e.mode = key
		if key == "heal" or key == "none" then
			e.attack = false
		end
		FAT.SyncEvents()
		FAT.UIRefresh()
	end
end

function UI.ModeGet()
	local e = UI.Cur()
	return e and e.mode
end

function UI.FbClick(key, btn)
	local e = UI.Cur()
	if e then
		if btn == "RightButton" then
			e.fb = nil
		else
			e.fb = key
		end
		FAT.SyncEvents()
		FAT.UIRefresh()
	end
end

function UI.FbGet()
	local e = UI.Cur()
	if not e then
		return nil
	end
	if e.fb then
		return e.fb, nil
	end
	return nil, FAT.S.fallback
end

function UI.UsesFallback(mode)
	return mode == "assist" or mode == "mark" or mode == "weak" or mode == "caster"
end

function UI.AttackGet()
	local e = UI.Cur()
	return e and e.attack
end

function UI.AttackSet(v)
	local e = UI.Cur()
	if e then e.attack = v end
end

function UI.PvpGet()
	local e = UI.Cur()
	return e and e.pvp
end

function UI.PvpSet(v)
	local e = UI.Cur()
	if e then e.pvp = v end
end

-- pull propre au sort : remplace l'option globale (retire la surcharge si elle l'egale)
function UI.PullGet()
	local e = UI.Cur()
	if not e then
		return false
	end
	if e.f and e.f.pull ~= nil then
		return e.f.pull
	end
	return FAT.S.pull
end

function UI.PullSet(v)
	local e = UI.Cur()
	if not e then
		return
	end
	if v == FAT.S.pull then
		if e.f then
			e.f.pull = nil
			if next(e.f) == nil then e.f = nil end
		end
	else
		e.f = e.f or {}
		e.f.pull = v
	end
end

function UI.ViaClick()
	local e = UI.Cur()
	if e then
		if e.via == "both" then e.via = "click" elseif e.via == "click" then e.via = "key" else e.via = "both" end
		FAT.UIRefresh()
	end
end

function UI.KeyClick()
	local e = UI.Cur()
	if e then
		UI.keyCapture.slot = UI.sel
		UI.keyCapture:EnableKeyboard(true)
		UI.keyCapture:Show()
		FAT.UIRefresh()
	end
end

function UI.FiltersClick()
	if UI.Cur() then
		UI.scope = "spell"
		UI.ShowTab(2)
	end
end

function UI.TestClick()
	local e = UI.Cur() or FAT.ST.lastEntry
	if not e then
		FAT.p(Tr("Choisis d'abord un sort dans la liste."))
		return
	end
	FAT.testLines = FAT.Explain(e)
	FAT.UIRefresh()
end

function UI.DelClick()
	if UI.sel then
		UI.Remove(UI.sel)
	end
end

function UI.BuildDetail(d)
	UI.dIcon = d:CreateTexture(nil, "ARTWORK")
	UI.dIcon:SetWidth(28)
	UI.dIcon:SetHeight(28)
	UI.dIcon:SetPoint("TOPLEFT", d, "TOPLEFT", 0, 0)
	UI.dIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	UI.dName = Wd.Line(d, "title", "", 228)
	UI.dName:SetPoint("TOPLEFT", d, "TOPLEFT", 38, -5)
	UI.dDel = Wd.At(Wd.Button(d, 72, 24, "Suppr", UI.DelClick, "danger", "Supprimer ce sort",
		"Retire le sort de la liste (sa touche est liberee si plus aucun sort ne l'utilise)."), d, 272, 2)

	Wd.At(Wd.Line(d, "label", "Choix de la cible :", 344), d, 0, 34)
	local items = {}
	local i = 1
	while FAT.MODES[i] do
		local m = FAT.MODES[i]
		tinsert(items, { m, UI.SHORT[m] or FAT.FR.MODE_LABEL[m], FAT.FR.MODE_LABEL[m], FAT.FR.MODE_HELP[m] })
		i = i + 1
	end
	UI.modeSeg = Wd.At(Wd.Seg(d, 344, 26, 3, items, UI.ModeClick, UI.ModeGet), d, 0, 48)
	UI.modeBtns = UI.modeSeg.cells

	UI.fbText = Wd.At(Wd.Line(d, "label", "", 344), d, 0, 130)
	local fbi = {}
	i = 1
	while FAT.FALLBACKS[i] do
		local m = FAT.FALLBACKS[i]
		tinsert(fbi, { m, UI.SHORT[m] or FAT.FR.MODE_LABEL[m], FAT.FR.MODE_LABEL[m],
			"Utilise quand Assister / Prioritaire / Plus faible / Lanceur ne trouvent aucune cible valide. Clic : choisir. Clic droit : revenir au repli par defaut.",
			"Le repli au contour colore est celui par defaut (onglet Options)." })
		i = i + 1
	end
	UI.fbSeg = Wd.At(Wd.Seg(d, 344, 24, 6, fbi, UI.FbClick, UI.FbGet, true), d, 0, 146)

	UI.dAttack = Wd.At(Wd.Toggle(d, 118, "Auto-attaque", UI.AttackGet, UI.AttackSet, "Auto-attaque",
		"Demarre l'auto-attaque sur la cible apres le sort (comme /startattack). Jamais sur un allie."), d, 0, 176)
	UI.dPvp = Wd.At(Wd.Toggle(d, 124, "Joueurs seuls", UI.PvpGet, UI.PvpSet, "Joueurs ennemis seulement (PvP)",
		"Ignore les mobs : seuls les joueurs ennemis sont pris. Si aucun joueur n'est trouve, le sort n'est pas lance."), d, 122, 176)
	UI.dPull = Wd.At(Wd.Toggle(d, 94, "Pull", UI.PullGet, UI.PullSet, "Autoriser le pull",
		"Hors combat, permet de prendre un mob au repos. Desactive (conseille) : l'addon ne cible jamais un mob au hasard hors combat.",
		"Reglage de ce sort : remplace l'option globale (comme dans l'onglet Filtres)."), d, 250, 176)

	UI.dKey = Wd.At(Wd.Button(d, 168, 28, "", UI.KeyClick, "normal", "Touche de l'addon",
		"Clique puis appuie sur la combinaison voulue (Echap annule). Plusieurs sorts sur la meme touche : le premier de la liste qui est pret est lance.",
		"Raccourcis > Fredo AutoTarget permet aussi de la regler."), d, 0, 206)
	UI.dVia = Wd.At(Wd.Button(d, 168, 28, "", UI.ViaClick, "normal", "Declencheur (barre d'action / livre de sorts)",
		"Clic + Touche : l'auto-cible marche au clic souris ET au raccourci clavier. Clic seul / Touche seule : un seul des deux.",
		"La touche propre de l'addon (bouton Touche) et les macros marchent toujours."), d, 176, 206)
	UI.dFilters = Wd.At(Wd.Button(d, 168, 28, "Filtres de ce sort...", UI.FiltersClick, "normal", "Filtres propres a ce sort",
		"Ouvre l'onglet Filtres pour remplacer, pour ce sort seulement, la distance, le combat, etc."), d, 0, 240)
	UI.testBtn = Wd.At(Wd.Button(d, 168, 28, "Tester", UI.TestClick, "accent", "Tester le choix de cible",
		"Simule le choix de cible pour ce sort SANS le lancer et explique pourquoi chaque candidat est accepte ou refuse. Ta cible peut changer."), d, 176, 240)

	-- apercu de la decision (filet d'accent a gauche)
	local pv = Wd.AccTexture(d, "ARTWORK", 0.9, 2, 74)
	pv:SetPoint("TOPLEFT", d, "TOPLEFT", 0, -278)
	UI.preview = Wd.Text(d, "dense", "", 334, 76)
	UI.preview:SetPoint("TOPLEFT", d, "TOPLEFT", 10, -276)
	-- resultat du test, dans une zone encadree
	local tb = CreateFrame("Frame", nil, d)
	tb:SetWidth(344)
	tb:SetHeight(106)
	tb:SetPoint("TOPLEFT", d, "TOPLEFT", 0, -358)
	Wd.Box(tb, C.bg, C.line)
	UI.testBox = tb
	UI.testOut = Wd.Text(tb, "dense", "", 328, 94)
	UI.testOut:SetPoint("TOPLEFT", tb, "TOPLEFT", 8, -6)
end

function UI.BuildSorts(page)
	UI.BuildSortsLeft(page)
	local p = CreateFrame("Frame", nil, page)
	p:SetWidth(368)
	p:SetHeight(488)
	p:SetPoint("TOPLEFT", page, "TOPLEFT", 244, 0)
	Wd.Box(p, C.panel, C.line)
	UI.panel = p
	UI.noSel = Wd.Text(p, "help", "Ajoute ou choisis un sort pour voir ce qui se passera.", 320, 40)
	UI.noSel:SetPoint("TOPLEFT", p, "TOPLEFT", 24, -32)
	local d = CreateFrame("Frame", nil, p)
	d:SetWidth(344)
	d:SetHeight(464)
	d:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -12)
	UI.detail = d
	UI.BuildDetail(d)
end

-- ========= Onglet Filtres =========
function UI.FilterValue(key)
	local e = (UI.scope == "spell") and UI.Cur() or nil
	if e and e.f and e.f[key] ~= nil then
		return e.f[key], true
	end
	return FAT.S[key], false
end

function UI.SetFilter(key, val)
	local e = (UI.scope == "spell") and UI.Cur() or nil
	if e then
		if val == nil then
			if e.f then
				e.f[key] = nil
				if next(e.f) == nil then e.f = nil end
			end
		else
			e.f = e.f or {}
			e.f[key] = val
		end
	else
		FAT.S[key] = val
	end
end

function UI.FGet(w)
	local v = UI.FilterValue(w.fkey)
	return v
end

function UI.FSet(v, w)
	local k = w.fkey
	if UI.scope == "spell" and UI.Cur() and v == FAT.S[k] then
		UI.SetFilter(k, nil)
	else
		UI.SetFilter(k, v)
	end
	if UI.scope == "spell" then
		UI.RefreshFilters()
	end
end

function UI.FmtDist(v)
	if v == 0 then
		return Tr("portee du sort")
	end
	return Tr("%s m", tostring(v))
end

function UI.ScopeClick(key)
	if key == "spell" and UI.Cur() then
		UI.scope = "spell"
	else
		UI.scope = "global"
	end
	FAT.UIRefresh()
end

function UI.ScopeGet()
	return UI.scope
end

function UI.ChipClick(chip)
	if UI.scope == "spell" and UI.Cur() then
		UI.SetFilter(chip.fkey, nil)
	end
	FAT.UIRefresh()
end

function UI.MakeFilterRow(g, key)
	local r = { key = key }
	local lab = FAT.FR.FILTER_LABEL[key]
	local help = FAT.FR.FILTER_HELP[key]
	if key == "dist" then
		r.w = Wd.Slider(g.body, 612, lab, 0, 100, 1, UI.FGet, UI.FSet, UI.FmtDist, lab, help,
			"Portee 'sort' : un changement remplace la valeur globale pour ce sort.")
		Wd.Put(g, r.w, 36)
	else
		r.w = Wd.Toggle(g.body, 612, lab, UI.FGet, UI.FSet, lab, help,
			"Portee 'sort' : un clic remplace la valeur globale pour ce sort.", true)
		Wd.Put(g, r.w, 32)
	end
	r.w.fkey = key
	r.chip = Wd.Button(g.body, 60, 16, "", UI.ChipClick, "ghost", "Reglage de ce sort",
		"Ce filtre est propre a ce sort. Clique pour revenir a la valeur globale.")
	r.chip.fkey = key
	if key == "dist" then
		r.chip:SetPoint("TOPRIGHT", r.w, "TOPRIGHT", -100, 0)
	else
		r.chip:SetPoint("TOPRIGHT", r.w, "TOPRIGHT", 0, -2)
	end
	return r
end

function UI.BuildFilters(page)
	local items = {
		{ "global", "Global", "Portee des reglages",
			"Global : valeurs par defaut de tous les sorts. Sort : remplace les valeurs pour le sort selectionne dans l'onglet Sorts seulement." },
		{ "spell", "", "Portee des reglages",
			"Global : valeurs par defaut de tous les sorts. Sort : remplace les valeurs pour le sort selectionne dans l'onglet Sorts seulement." },
	}
	UI.scopeSeg = Wd.At(Wd.Seg(page, 440, 28, 2, items, UI.ScopeClick, UI.ScopeGet), page, 0, 0)
	UI.scopeBtn = UI.scopeSeg.cells[2]
	Wd.At(Wd.Text(page, "help", "Ces filtres s'appliquent au choix d'une NOUVELLE cible. Ta cible actuelle est gardee par les modes Garder / A portee.", 612, 30), page, 2, 36)
	local st = Wd.Stack(page, 0, 72, 612)
	tinsert(UI.stacks, st)
	local g1 = Wd.Group(st, "f_when", "Quand cibler")
	local g2 = Wd.Group(st, "f_skip", "Quoi ignorer")
	local g3 = Wd.Group(st, "f_view", "Vision")
	local plan = { { "combat", g1 }, { "dist", g1 }, { "pull", g1 }, { "pets", g2 }, { "cc", g2 }, { "tapped", g2 },
		{ "pvpsafe", g2 }, { "los", g3 } }
	UI.filterRows = {}
	local i = 1
	while plan[i] do
		UI.filterRows[i] = UI.MakeFilterRow(plan[i][2], plan[i][1])
		i = i + 1
	end
	UI.xpText = Wd.Text(g3.body, "help", "", 600, 30)
	Wd.Put(g3, UI.xpText, 30)
	Wd.Fit(g1)
	Wd.Fit(g2)
	Wd.Fit(g3)
end

function UI.YesNo(v)
	return v and Tr("Oui") or Tr("Non")
end

function UI.RefreshFilters()
	local e = UI.Cur()
	if UI.scope == "spell" and (not e) then
		UI.scope = "global"
	end
	UI.scopeBtn:SetText(Tr("Sort : %s", e and e.name or "-"))
	Wd.SetDisabled(UI.scopeBtn, e == nil)
	local i = 1
	while UI.filterRows[i] do
		local r = UI.filterRows[i]
		local val, own = UI.FilterValue(r.key)
		if r.w.sub then
			r.w.sub:SetText(UI.First(FAT.FILTER_HELP[r.key]))
		end
		if UI.scope == "spell" then
			r.chip:Show()
			if own then
				r.chip:SetText(Tr("perso"))
				r.chip.on = true
				Wd.SetDisabled(r.chip, false)
			else
				r.chip:SetText(Tr("global"))
				r.chip.on = nil
				Wd.SetDisabled(r.chip, true)
			end
		else
			r.chip:Hide()
		end
		i = i + 1
	end
	local xp = FAT.XPOK()
	UI.xpText:SetText("UnitXP_SP3 : " .. (xp and Tr("detecte (distance precise, ligne de vue)") or Tr("absent (distance limitee a 28 m, pas de ligne de vue)"))
		.. "   |   IsSpellInRange : " .. (FAT.Api("IsSpellInRange") and Tr("present") or Tr("absent")))
end

-- ========= Onglet Options =========
function UI.SGet(w)
	return FAT.S[w.skey]
end

function UI.SSet(v, w)
	FAT.S[w.skey] = v
end

function UI.FmtNum(v)
	return tostring(v)
end

function UI.FmtSec(v)
	return string.format("%.2f s", v)
end

function UI.FmtPct(v)
	return tostring(math.floor(v + 0.5)) .. " %"
end

function UI.FmtScale(v)
	return tostring(math.floor((v * 100) + 0.5)) .. " %"
end

-- toggle sur un reglage FAT.S[cle]
function UI.OptToggle(g, key, label, title, tip, extra)
	local t = Wd.Toggle(g.body, 300, label, UI.SGet, UI.SSet, title, tip, extra)
	t.skey = key
	Wd.Put(g, t, 24)
	return t
end

function UI.OptSlider(g, key, label, lo, hi, step, fmt, tip)
	local c = Wd.Slider(g.body, 300, label, lo, hi, step, UI.SGet, UI.SSet, fmt, label, tip)
	c.skey = key
	Wd.Put(g, c, 36)
	return c
end

function UI.FbGlobalClick(key)
	FAT.S.fallback = key
	FAT.SyncEvents()
	FAT.UIRefresh()
end

function UI.FbGlobalGet()
	return FAT.S.fallback
end

function UI.LangSegClick(key)
	FAT.SetLang(key)
	FAT.UIRefresh()
end

function UI.LangSegGet()
	return FAT.S.lang or "auto"
end

function UI.LangClick(b, btn)
	local order = { "auto", "fr", "en" }
	FAT.SetLang(FAT.CycleIn(order, FAT.S.lang or "auto", btn == "RightButton"))
	FAT.UIRefresh()
end

-- ----- apparence : accent, taille, opacite -----
function UI.SetAccent(key)
	FAT.DB.ui = FAT.DB.ui or {}
	FAT.DB.ui.accent = key
	Wd.SetAccent(key)
	UI.RefreshChrome()
end

-- echelle maximale pour que toute la fenetre tienne a l'ecran (au plus 130 %)
function UI.MaxScale()
	local m = 1.3
	local h = UIParent:GetHeight()
	local w = UIParent:GetWidth()
	if h and h > 0 and (h / UI.H) < m then
		m = h / UI.H
	end
	if w and w > 0 and (w / UI.W) < m then
		m = w / UI.W
	end
	return m
end

function UI.ClampScale(s)
	if s < 0.8 then s = 0.8 elseif s > 1.3 then s = 1.3 end
	local mx = UI.MaxScale()
	if s > mx then
		return math.floor(mx * 100) / 100
	end
	return math.floor((s * 100) + 0.5) / 100
end

function UI.SetScale(s)
	local f = FAT.optionsFrame
	s = UI.ClampScale(s)
	local old = f:GetScale()
	local l, t = f:GetLeft(), f:GetTop()
	f:SetScale(s)
	if l and t and old and old > 0 and old ~= s then
		f:ClearAllPoints()
		f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", (l * old) / s, (t * old) / s)
		FAT.DB.ui = FAT.DB.ui or {}
		FAT.DB.ui.pos = { (l * old) / s, (t * old) / s }
	end
	FAT.DB.ui = FAT.DB.ui or {}
	FAT.DB.ui.scale = s
end

function UI.SetAlpha(a)
	if a < 0.4 then a = 0.4 elseif a > 1 then a = 1 end
	FAT.DB.ui = FAT.DB.ui or {}
	FAT.DB.ui.alpha = a
	Wd.alpha = a
	Wd.ApplyBg()
end

function UI.ScaleGet()
	return UI.ClampScale((FAT.DB.ui and tonumber(FAT.DB.ui.scale)) or 1)
end

function UI.ScaleSet(v)
	UI.SetScale(v)
end

function UI.AlphaGet()
	return (FAT.DB.ui and tonumber(FAT.DB.ui.alpha)) or 1
end

function UI.AlphaSet(v)
	UI.SetAlpha(v)
end

function UI.LoadAppearance()
	local u = FAT.DB and FAT.DB.ui
	local f = FAT.optionsFrame
	local a = u and tonumber(u.alpha) or 1
	if a < 0.4 then a = 0.4 elseif a > 1 then a = 1 end
	Wd.alpha = a
	Wd.ApplyBg()
	Wd.SetAccent(u and u.accent or "class")
	f:SetScale(UI.ClampScale(u and tonumber(u.scale) or 1))
	f:ClearAllPoints()
	if u and u.pos and u.pos[1] and u.pos[2] then
		f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", u.pos[1], u.pos[2])
	else
		f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	end
end

function UI.PaintSwatch(b)
	local r, g, bl = Wd.AccentRGB(b.akey)
	b:SetBackdropColor(r, g, bl, b.hv and 1 or 0.85)
	local bd = C.line
	if b.on then
		bd = C.white
	elseif b.hv then
		bd = C.muted
	end
	b:SetBackdropBorderColor(bd[1], bd[2], bd[3], 1)
end

function UI.SwatchClick(b)
	UI.SetAccent(b.akey)
	FAT.UIRefresh()
end

function UI.BuildSwatches(g)
	UI.swatches = {}
	local box = CreateFrame("Frame", nil, g.body)
	box:SetWidth(300)
	box:SetHeight(24)
	local k = 1
	while Wd.ACC_LIST[k] do
		local key = Wd.ACC_LIST[k]
		local b = CreateFrame("Button", nil, box)
		b:SetWidth(44)
		b:SetHeight(24)
		b:SetPoint("TOPLEFT", box, "TOPLEFT", (k - 1) * 51, 0)
		Wd.Box(b, C.card, C.line)
		b.akey = key
		b.act = UI.SwatchClick
		b:RegisterForClicks("LeftButtonUp")
		b:SetScript("OnClick", Wd.OnClick)
		Wd.Tip(b, UI.ACC_NAME[key], "Couleur principale de l'interface (liseres, interrupteurs, barres). Appliquee tout de suite.")
		Wd.Hook(b, UI.PaintSwatch)
		UI.swatches[k] = b
		k = k + 1
	end
	Wd.Put(g, box, 24)
end

function UI.BuildOptionsLeft(page)
	local st = Wd.Stack(page, 0, 0, 300)
	tinsert(UI.stacks, st)
	-- --- general ---
	local g = Wd.Group(st, "o_general", "General")
	UI.OptToggle(g, "enabled", "Auto-cible activee", "Auto-cible activee",
		"Interrupteur general. Desactive : les sorts partent sans aucun changement de cible. Raccourci : /fat toggle.")
	UI.OptToggle(g, "retarget", "Re-ciblage quand ma cible meurt", "Re-ciblage automatique",
		"En combat, quand ta cible meurt, prend la suivante selon les filtres du dernier sort utilise (max un changement par intervalle, jamais pendant une incantation).")
	UI.OptToggle(g, "indicator", "Indicateur discret", "Indicateur discret",
		"Petit cadre deplacable qui montre le mode du dernier sort et la derniere raison de refus.")
	UI.OptToggle(g, "debug", "Debug (decisions dans le chat)", "Debug",
		"Ecrit dans le chat chaque decision (cible choisie, refus, erreurs). Sinon l'addon reste silencieux.")
	Wd.Fit(g)
	-- --- soins ---
	g = Wd.Group(st, "o_heal", "Soins")
	UI.OptToggle(g, "healPets", "Soigner : inclure les familiers", "Soigner : familiers",
		"Le mode Soigner considere aussi les familiers du groupe et du raid.")
	UI.OptToggle(g, "healRestore", "Soigner : revenir a ma cible apres", "Soigner : revenir a la cible d'avant",
		"Apres le sort de soin, reprend la cible que tu avais avant (par exemple le mob).")
	UI.OptSlider(g, "healMin", "Soigner sous (% PV)", 1, 100, 1, UI.FmtPct,
		"Mode Soigner : seuls les allies sous ce pourcentage de PV sont pris (100 = tout allie blesse).")
	Wd.Fit(g)
	-- --- apparence ---
	g = Wd.Group(st, "o_look", "Apparence")
	Wd.Put(g, Wd.Line(g.body, "label", "Couleur d'accent", 300), 14)
	UI.BuildSwatches(g)
	UI.scaleSld = Wd.Slider(g.body, 300, "Taille de la fenetre", 0.8, 1.3, 0.05, UI.ScaleGet, UI.ScaleSet, UI.FmtScale,
		"Taille de la fenetre", "Agrandit ou reduit tout le panneau (80 a 130 %). Appliquee quand tu relaches le curseur.", nil, true)
	Wd.Put(g, UI.scaleSld, 36)
	UI.alphaSld = Wd.Slider(g.body, 300, "Opacite du fond", 0.4, 1, 0.05, UI.AlphaGet, UI.AlphaSet, UI.FmtScale,
		"Opacite du fond", "Rend le fond du panneau plus ou moins transparent (le texte reste net).")
	Wd.Put(g, UI.alphaSld, 36)
	Wd.Put(g, Wd.Line(g.body, "label", "Langue de l'interface", 300), 14)
	local li = {
		{ "auto", "", "Langue de l'interface",
			"Auto suit la langue du client (frFR : francais, sinon anglais). Les noms de sorts viennent toujours du client." },
		{ "fr", "", "Langue de l'interface",
			"Auto suit la langue du client (frFR : francais, sinon anglais). Les noms de sorts viennent toujours du client." },
		{ "en", "", "Langue de l'interface",
			"Auto suit la langue du client (frFR : francais, sinon anglais). Les noms de sorts viennent toujours du client." },
	}
	UI.langSeg = Wd.Seg(g.body, 300, 24, 3, li, UI.LangSegClick, UI.LangSegGet)
	UI.langSeg.cells[1].fs:SetText("Auto")
	UI.langSeg.cells[2].fs:SetText("Francais")
	UI.langSeg.cells[3].fs:SetText("English")
	Wd.Put(g, UI.langSeg, 24)
	Wd.Fit(g)
end

function UI.MarksEnter(txt)
	local words, n = FAT.SplitArgs(txt)
	local m = FAT.ParseMarks(words, n)
	if m[1] then
		FAT.S.marks = m
	end
	FAT.UIRefresh()
end

function UI.AssistEnter(txt)
	FAT.S.assist = FAT.Trim(txt)
	FAT.UIRefresh()
end

function UI.BuildOptionsRight(page)
	local st = Wd.Stack(page, 312, 0, 300)
	tinsert(UI.stacks, st)
	-- --- ciblage ---
	local g = Wd.Group(st, "o_target", "Ciblage")
	UI.OptToggle(g, "pull", "Pull : autoriser un mob hors combat", "Autoriser le pull",
		"Hors combat, permet de prendre un mob au repos. Desactive (conseille) : l'addon ne cible jamais un mob au hasard hors combat.")
	UI.OptSlider(g, "scan", "Candidats examines", 1, 16, 1, UI.FmtNum,
		"Combien d'ennemis au maximum sont parcourus (du plus proche au plus loin) pour trouver une cible valide.")
	UI.OptSlider(g, "minInterval", "Intervalle Plus proche (s)", 0.05, 5, 0.05, UI.FmtSec,
		"Mode Plus proche : pas plus d'un changement de cible par intervalle.")
	UI.OptSlider(g, "retargetGap", "Intervalle re-ciblage (s)", 0.1, 10, 0.1, UI.FmtSec,
		"Re-ciblage automatique : au plus un changement par intervalle.")
	UI.fbGlobalText = Wd.Line(g.body, "label", "", 300)
	Wd.Put(g, UI.fbGlobalText, 14)
	local fbi = {}
	local i = 1
	while FAT.FALLBACKS[i] do
		local m = FAT.FALLBACKS[i]
		tinsert(fbi, { m, UI.SHORT[m] or FAT.FR.MODE_LABEL[m], "Mode de repli par defaut",
			"Utilise quand Assister / Prioritaire / Plus faible / Lanceur ne trouvent rien (chaque sort peut avoir le sien).", FAT.FR.MODE_LABEL[m] })
		i = i + 1
	end
	UI.fbGlobal = Wd.Seg(g.body, 300, 24, 6, fbi, UI.FbGlobalClick, UI.FbGlobalGet, true)
	Wd.Put(g, UI.fbGlobal, 24)
	Wd.Fit(g)
	-- --- assister et marqueurs ---
	g = Wd.Group(st, "o_assist", "Assister et marqueurs")
	Wd.Put(g, Wd.Line(g.body, "label", "Assister : joueur a suivre (vide = chef/assistants)", 300), 14)
	UI.assistBox = Wd.Input(g.body, 300, 24, 30, UI.AssistEnter, "Joueur a assister",
		"Nom du joueur dont tu prends la cible en mode Assister (ex. ton tank). Vide : chef de groupe, puis assistants du raid. Entree pour valider.")
	Wd.Put(g, UI.assistBox, 24)
	Wd.Put(g, Wd.Line(g.body, "label", "Ordre des marqueurs (mode Prioritaire)", 300), 14)
	UI.marksBox = Wd.Input(g.body, 300, 24, 80, UI.MarksEnter, "Ordre des marqueurs",
		"Du plus prioritaire au moins prioritaire : crane croix carre lune triangle losange cercle etoile (ou 8 7 6 5 4 3 2 1). Entree pour valider.")
	Wd.Put(g, UI.marksBox, 24)
	UI.marksText = Wd.Text(g.body, "small", "", 300, 26)
	Wd.Put(g, UI.marksText, 26)
	Wd.Put(g, Wd.Text(g.body, "help", "Raccourcis clavier : Echap > Raccourcis > Fredo AutoTarget\n(cible suivante / precedente filtree, joueur ennemi, plus bas PV,\nassister, marque, lanceur, allie blesse, vider la cible).", 300, 62), 62)
	Wd.Fit(g)
end

function UI.BuildOptions(page)
	UI.BuildOptionsLeft(page)
	UI.BuildOptionsRight(page)
end

function UI.RefreshOptions()
	UI.fbGlobalText:SetText(Tr("Repli par defaut : %s", FAT.MODE_LABEL[FAT.S.fallback] or tostring(FAT.S.fallback)))
	UI.assistBox:SetText(FAT.S.assist or "")
	local names = {}
	local k = 1
	while FAT.S.marks[k] do
		tinsert(names, FAT.MARK_NAME[FAT.S.marks[k]] or "?")
		k = k + 1
	end
	UI.marksBox:SetText("")
	UI.marksText:SetText(table.concat(names, " > "))
	k = 1
	while UI.swatches[k] do
		UI.swatches[k].on = (UI.swatches[k].akey == Wd.accKey) or nil
		UI.PaintSwatch(UI.swatches[k])
		k = k + 1
	end
end

-- ========= Onglet Profils =========
function UI.ProfSave()
	local ok, m = FAT.ProfileSave(UI.profBox:GetText())
	FAT.p(ok and Tr("Profil sauvegarde : %s", m) or m)
	FAT.UIRefresh()
end

function UI.ProfLoad()
	local ok, m = FAT.ProfileLoad(UI.profBox:GetText())
	FAT.p(ok and Tr("Profil charge : %s", m) or m)
	UI.sel = nil
	FAT.UIRefresh()
end

function UI.ProfDel()
	local ok, m = FAT.ProfileDelete(UI.profBox:GetText())
	FAT.p(ok and Tr("Profil supprime : %s", m) or m)
	FAT.UIRefresh()
end

function UI.ProfBind()
	local ok, m = FAT.ProfileBind(UI.profBox:GetText())
	FAT.p(ok and Tr("Profil lie a la specialisation %s", m) or m)
	FAT.UIRefresh()
end

function UI.ProfUnbind()
	local ok, m = FAT.ProfileUnbind()
	FAT.p(ok and Tr("Liaison retiree pour %s", m) or Tr("Aucune liaison pour cette specialisation."))
	FAT.UIRefresh()
end

function UI.ProfRowClick(b)
	if b.pname then
		UI.profBox:SetText(b.pname)
	end
end

function UI.ExportClick()
	FAT.ShowExport(FAT.Export())
end

function UI.ImportClick()
	local ok, m = FAT.Import(UI.exportBox:GetText())
	FAT.p(m)
	UI.sel = nil
	FAT.UIRefresh()
end

function UI.ResetClick()
	FAT.Slash("reset confirm")
	UI.sel = nil
end

function UI.BuildProfiles(page)
	Wd.At(Wd.Text(page, "help", "Profils : une liste de sorts + les filtres, a changer en un clic (par specialisation, par situation...).", 612, 30), page, 0, 0)
	UI.profBox = Wd.At(Wd.Input(page, 236, 28, 24, function() FAT.UIRefresh() end,
		"Nom du profil", "Ecris un nom (lettres, chiffres, espace, - et _) ou clique un profil dans la liste."), page, 0, 36)
	Wd.At(Wd.Button(page, 84, 28, "Sauver", UI.ProfSave, "accent", "Sauvegarder le profil",
		"Enregistre ta liste de sorts et tes filtres sous ce nom (remplace le profil du meme nom)."), page, 240, 36)
	Wd.At(Wd.Button(page, 84, 28, "Charger", UI.ProfLoad, "normal", "Charger le profil",
		"Remplace ta liste et tes filtres par ceux du profil. Tes touches ne changent pas."), page, 328, 36)
	Wd.At(Wd.Button(page, 84, 28, "Suppr", UI.ProfDel, "danger", "Supprimer le profil",
		"Efface le profil sauvegarde (ta liste actuelle ne change pas)."), page, 416, 36)
	Wd.At(Wd.Button(page, 144, 24, "Lier a ma spe", UI.ProfBind, "normal", "Lier a la specialisation",
		"Ce profil se charge tout seul quand ta specialisation (branche de talents principale) est celle d'aujourd'hui."), page, 0, 72)
	Wd.At(Wd.Button(page, 96, 24, "Delier", UI.ProfUnbind, "normal", "Delier la specialisation",
		"Retire la liaison profil <-> specialisation actuelle."), page, 148, 72)
	UI.specText = Wd.Text(page, "help", "", 352, 16)
	UI.specText:SetPoint("TOPLEFT", page, "TOPLEFT", 256, -76)
	UI.profRows = {}
	local i = 1
	while i <= 8 do
		local b = Wd.Button(page, 360, 28, "", UI.ProfRowClick, "normal", "Profil",
			"Clique pour mettre son nom dans la case, puis Charger / Supprimer / Lier.")
		Wd.At(b, page, 0, 108 + ((i - 1) * 32))
		b.fs:SetJustifyH("LEFT")
		b.fs:SetWidth(344)
		b.fs:ClearAllPoints()
		b.fs:SetPoint("LEFT", b, "LEFT", 12, 0)
		UI.profRows[i] = b
		i = i + 1
	end
	Wd.At(Wd.Line(page, "label", "Export / import : une chaine courte a copier-coller (Ctrl+A, Ctrl+C / Ctrl+V).", 612), page, 0, 376)
	UI.exportBox = Wd.At(Wd.Input(page, 404, 28, 12000, function(txt) end,
		"Chaine d'export / import",
		"Exporter : remplit cette case avec ta configuration (copie-la). Importer : colle ici une chaine FAT2;... puis clique Importer (remplace ta liste)."), page, 0, 394)
	Wd.At(Wd.Button(page, 100, 28, "Exporter", UI.ExportClick, "normal", "Exporter",
		"Ecrit ta liste de sorts et tes filtres dans la case, a copier pour un ami ou une sauvegarde."), page, 408, 394)
	Wd.At(Wd.Button(page, 100, 28, "Importer", UI.ImportClick, "normal", "Importer",
		"Remplace ta liste et tes filtres par la chaine collee. Controle d'integrite inclus."), page, 512, 394)
	Wd.At(Wd.Button(page, 200, 28, "Tout remettre a zero", UI.ResetClick, "danger", "Reinitialiser",
		"Efface la liste et les reglages (les profils sauvegardes sont conserves)."), page, 0, 440)
end

function FAT.ShowExport(s)
	if UI.exportBox then
		UI.exportBox:SetText(s)
		UI.exportBox:HighlightText()
		UI.exportBox:SetFocus()
		UI.ShowTab(4)
		if FAT.optionsFrame and not FAT.optionsFrame:IsShown() then
			FAT.optionsFrame:Show()
		end
	end
end

function UI.RefreshProfiles()
	local names = FAT.ProfileNames()
	local binds = {}
	local k, v
	for k, v in pairs(FAT.DB.specBind) do
		binds[v] = (binds[v] and (binds[v] .. ",") or "") .. k
	end
	local i = 1
	while i <= 8 do
		local b = UI.profRows[i]
		local nm = names[i]
		if nm then
			b.pname = nm
			b.on = (FAT.DB.activeProfile == nm) or nil
			b:SetText(nm .. (FAT.DB.activeProfile == nm and (Wd.AccHex() .. Tr("  (actif)") .. "|r") or "")
				.. (binds[nm] and (Wd.Hex(C.muted) .. "  [" .. binds[nm] .. "]|r") or ""))
			b.paint(b)
			b:Show()
		else
			b.pname = nil
			b.on = nil
			b:Hide()
		end
		i = i + 1
	end
	local spec = FAT.SpecName()
	UI.specText:SetText(Tr("Specialisation detectee : %s", tostring(spec or Tr("inconnue"))) .. (spec and FAT.DB.specBind[spec] and Tr(" -> profil %s", FAT.DB.specBind[spec]) or ""))
end

-- ========= Onglet Aide =========
function UI.HelpTestClick()
	local f = SlashCmdList["FREDOAUTOTARGET"]
	if f then
		f("test")
	end
end

function UI.BuildHelp(page)
	Wd.At(Wd.Line(page, "head", "Les modes de ciblage", 372), page, 0, 0)
	UI.helpRows = {}
	local i = 1
	while FAT.MODES[i] do
		local m = FAT.MODES[i]
		local y = 28 + ((i - 1) * 44)
		local ic = page:CreateTexture(nil, "ARTWORK")
		ic:SetTexture(UI.MODE_ICON[m])
		ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		ic:SetWidth(24)
		ic:SetHeight(24)
		ic:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(y + 4))
		local nm = Wd.At(Wd.Line(page, "body", FAT.FR.MODE_LABEL[m], 330), page, 34, y)
		local mc = UI.MODE_COL[m]
		nm:SetTextColor(mc[1], mc[2], mc[3])
		Wd.At(Wd.Text(page, "help", FAT.FR.MODE_HELP[m], 336, 28), page, 34, y + 16)
		UI.helpRows[i] = { ic, nm }
		i = i + 1
	end
	Wd.At(Wd.Line(page, "head", "Commandes /fat (ou /fredo) :", 216), page, 396, 0)
	UI.helpCmds = Wd.Text(page, "help", "", 216, 380)
	UI.helpCmds:SetPoint("TOPLEFT", page, "TOPLEFT", 396, -28)
	UI.helpTest = Wd.At(Wd.Button(page, 216, 28, "Tester le choix de cible (/fat test)", UI.HelpTestClick, "accent",
		"Lien vers /fat test", "Affiche dans le chat l'explication du choix de cible pour le sort selectionne (ou le dernier sort lance), sans le lancer."), page, 396, 440)
end

function UI.RefreshHelp()
	local lines = FAT.HELP_LINES
	local out = {}
	local i = 2
	while lines and lines[i] do
		tinsert(out, Tr(lines[i]))
		i = i + 1
	end
	-- les listes "a|b|c" n'ont pas d'espace : on en ajoute pour que la ligne puisse passer a la ligne
	local txt = table.concat(out, "\n")
	txt = string.gsub(txt, "(%S)|(%S)", "%1| %2")
	txt = string.gsub(txt, "(%S)|(%S)", "%1| %2")
	UI.helpCmds:SetText(txt)
end

-- ========= Test, apercu =========
-- resultat du test : la zone est de hauteur fixe. On garde le titre, la cible actuelle et le resultat, puis
-- autant de lignes de candidats que la hauteur reelle (mesuree avec le retour a la ligne) en permet.
function UI.TestText(disp, take, dn)
	local out = {}
	local k = 1
	while k <= 2 and k < dn do
		tinsert(out, disp[k])
		k = k + 1
	end
	local j = 0
	while j < take do
		tinsert(out, disp[2 + 1 + j])
		j = j + 1
	end
	if take < (dn - 3) then
		tinsert(out, Tr("  ... (/fat test pour tout voir)"))
	end
	tinsert(out, disp[dn])
	return table.concat(out, "\n")
end

function UI.RefreshTest()
	local lines = FAT.testLines
	if lines then
		-- on saute la description (deja dans l'apercu)
		local disp = {}
		local li = 1
		while lines[li] do
			if li ~= 2 then tinsert(disp, lines[li]) end
			li = li + 1
		end
		local dn = 0
		while disp[dn + 1] do dn = dn + 1 end
		local take = math.max(0, dn - 3)
		local txt = table.concat(disp, "\n")
		if dn > 3 then
			txt = UI.TestText(disp, take, dn)
			while take > 0 do
				local h = Wd.BlockH(UI.testOut, txt)
				if (not h) or h <= UI.testOut:GetHeight() + 0.5 then
					break
				end
				take = take - 1
				txt = UI.TestText(disp, take, dn)
			end
		end
		Wd.SetFit(UI.testOut, txt)
	else
		UI.testOut:SetText(Wd.Hex(C.muted) .. Tr("Clique Tester pour voir pourquoi une cible est prise ou refusee.") .. "|r")
	end
end

function UI.RefreshDetail()
	local e = UI.Cur()
	if not e then
		UI.dName:SetText(Wd.Hex(C.muted) .. Tr("(aucun sort)") .. "|r")
		UI.preview:SetText(Tr("Ajoute ou choisis un sort pour voir ce qui se passera."))
		UI.fbText:SetText("")
		UI.dVia:SetText("")
		UI.dKey:SetText("")
		UI.detail:Hide()
		UI.noSel:Show()
		return
	end
	UI.detail:Show()
	UI.noSel:Hide()
	UI.dName:SetText(e.name)
	UI.dIcon:SetTexture(FAT.SpellIcon(e.name) or UI.UNKNOWN_ICON)
	local fbm = e.fb or FAT.S.fallback
	UI.fbText:SetText(Tr("Si rien : %s", FAT.MODE_LABEL[fbm] or tostring(fbm)) .. (e.fb and "" or Tr(" (def.)")))
	Wd.SegDisable(UI.fbSeg, not UI.UsesFallback(e.mode))
	UI.dVia:SetText(e.via == "click" and Tr("Clic seul") or (e.via == "key" and Tr("Touche seule") or Tr("Clic + Touche")))
	if UI.keyCapture.slot == UI.sel then
		UI.dKey:SetText(Tr("Touche..."))
		UI.dKey.on = true
	else
		local k1 = GetBindingKey("FREDOAUTOTARGET_SLOT" .. e.key)
		local _, gc = FAT.GroupEntries(e.key)
		UI.dKey:SetText((k1 and UI.ShortKey(k1) or Tr("Definir touche")) .. (gc > 1 and (" x" .. gc) or ""))
		UI.dKey.on = nil
	end
	UI.dKey.paint(UI.dKey)
	Wd.SetFit(UI.preview, FAT.Describe(e))
end

-- ========= Panneau : coquille, onglets, pied de page =========
function UI.TabClick(b)
	UI.ShowTab(b.n)
end

function UI.PaintTab(b)
	local A = Wd.acc
	local bg, bga, tc = C.panel, 0, C.muted
	if b.on then
		bg, bga, tc = Wd.Mix(C.panel, A, 0.16), 1, C.text
	elseif b.dn then
		bg, bga = C.press, 1
	elseif b.hv then
		bg, bga, tc = C.hover, 0.7, C.text
	end
	b:SetBackdropColor(bg[1], bg[2], bg[3], bga)
	b:SetBackdropBorderColor(bg[1], bg[2], bg[3], 0)
	b.fs:SetTextColor(tc[1], tc[2], tc[3])
	b.icon:SetAlpha(b.on and 1 or 0.65)
	if b.on then
		b.bar:Show()
	else
		b.bar:Hide()
	end
end

function UI.ShowTab(n)
	Wd.DropTip()
	local i = 1
	while UI.pages[i] do
		if i == n then
			UI.pages[i]:Show()
		else
			UI.pages[i]:Hide()
		end
		UI.tabs[i].on = (i == n) or nil
		UI.tabs[i].paint(UI.tabs[i])
		i = i + 1
	end
	UI.tab = n
	FAT.UIRefresh()
end

function UI.RefreshChrome()
	local S = FAT.S
	local cls = FAT.PlayerClass()
	local ci = UI.CLASS_ICON[cls or ""]
	if ci then
		UI.classIcon:SetTexture(UI.CLASS_TEX)
		UI.classIcon:SetTexCoord(ci[1], ci[2], ci[3], ci[4])
	else
		UI.classIcon:SetTexture(UI.UNKNOWN_ICON)
		UI.classIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end
	UI.hdrToggle.lab:SetText(S.enabled and Tr("Actif") or Tr("Inactif"))
	UI.langBtn:SetText(FAT.LangLabel())
	-- pied de page : etat, derniere raison, nombre de sorts, langue
	local on = S.enabled
	local col = on and C.good or C.bad
	UI.footDot:SetVertexColor(col[1], col[2], col[3], 1)
	UI.footState:SetText(on and Tr("Actif") or Tr("Inactif"))
	UI.footState:SetTextColor(col[1], col[2], col[3])
	local L = FAT.ST.last
	if not L then
		UI.footWhy:SetText(Tr("En attente d'un sort"))
		UI.footWhy:SetTextColor(C.faint[1], C.faint[2], C.faint[3])
	elseif L.ok then
		UI.footWhy:SetText(Tr("Dernier sort : %s", tostring(L.spell)))
		UI.footWhy:SetTextColor(C.good[1], C.good[2], C.good[3])
	else
		UI.footWhy:SetText(Tr("Dernier refus : %s", tostring(FAT.REASON[L.why] or L.why)))
		UI.footWhy:SetTextColor(C.warn[1], C.warn[2], C.warn[3])
	end
	UI.footCount:SetText(Tr("Sorts : %d/%d", FAT.CountEntries(), FAT.MAX_SLOTS))
	UI.footLang:SetText(Tr("Langue : %s", FAT.LangLabel()))
end

function FAT.RefreshPanel()
	if not FAT.optionsFrame or not FAT.DB then
		return
	end
	local order = UI.Order()
	if UI.sel and (not FAT.DB.spells[UI.sel]) then
		UI.sel = nil
	end
	if (not UI.sel) and order[1] then
		UI.sel = order[1]
	end
	UI.RefreshList(order)
	UI.RefreshDetail()
	UI.RefreshTest()
	Wd.SyncAll()
	UI.RefreshFilters()
	UI.RefreshOptions()
	UI.RefreshProfiles()
	UI.RefreshHelp()
	local i = 1
	while UI.stacks[i] do
		Wd.StackLayout(UI.stacks[i])
		i = i + 1
	end
	UI.RefreshChrome()
end

-- changement de langue : reposer tous les textes memorises puis rafraichir les textes dynamiques
function FAT.UIRelocalize()
	local i = 1
	while UI.loc[i] do
		local r = UI.loc[i]
		r[1]:SetText(Tr(r[2]))
		i = i + 1
	end
	if UI.langSeg then
		UI.langSeg.cells[1].fs:SetText("Auto")
		UI.langSeg.cells[2].fs:SetText("Francais")
		UI.langSeg.cells[3].fs:SetText("English")
	end
	if FAT.optionsFrame and FAT.DB and FAT.RefreshPanel then
		FAT.RefreshPanel()
	end
	if FAT.indicator and FAT.RefreshIndicator then
		FAT.RefreshIndicator()
	end
end

function UI.OnDragStop()
	this:StopMovingOrSizing()
	if FAT.DB then
		FAT.DB.ui = FAT.DB.ui or {}
		FAT.DB.ui.pos = { this:GetLeft(), this:GetTop() }
	end
end

function UI.OnDragStart()
	this:StartMoving()
end

-- Piege des niveaux (client 1.12) : un enfant garde le niveau qu'avait son parent a sa creation. Si le niveau
-- du panneau a change depuis (autre addon, Raise()), des controles passent sous le cadre qui capte la souris.
-- A chaque ouverture, on recale tout l'arbre : niveau enfant = niveau parent + 1 (+ decalage UI.lvl voulu).
function UI.FixLevels(fr)
	local kids = { fr:GetChildren() }
	local base = fr:GetFrameLevel()
	local i = 1
	while kids[i] do
		local k = kids[i]
		k:SetFrameLevel(base + (k.lvl or 1))
		UI.FixLevels(k)
		i = i + 1
	end
end

function UI.OnShowPanel()
	UI.FixLevels(this)
	UI.LoadAppearance()
	FAT.UIRefresh()
end

function UI.OnHidePanel()
	Wd.DropTip()
	-- reglage differe en attente (glissement interrompu par la fermeture) : on l'applique
	if UI.scaleSld then
		Wd.SliderFlush(UI.scaleSld)
	end
	if UI.keyCapture.slot then
		UI.StopCapture()
	end
end

function UI.CloseClick()
	FAT.optionsFrame:Hide()
end

function UI.HdrToggleGet()
	return FAT.S.enabled
end

function UI.HdrToggleSet(v)
	FAT.S.enabled = v
end

function UI.BuildHeader(f)
	local hd = CreateFrame("Frame", nil, f)
	hd:SetWidth(UI.W - 2)
	hd:SetHeight(49)
	hd:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -3)
	Wd.BgBox(hd, C.panel, 0.97, C.panel)
	local rule = Wd.Tex(hd, "OVERLAY", C.line, 1, UI.W - 2, 1)
	rule:SetPoint("BOTTOMLEFT", hd, "BOTTOMLEFT", 0, 0)
	UI.classIcon = hd:CreateTexture(nil, "ARTWORK")
	UI.classIcon:SetWidth(28)
	UI.classIcon:SetHeight(28)
	UI.classIcon:SetPoint("TOPLEFT", hd, "TOPLEFT", 16, -10)
	local title = Wd.Text(hd, "title", "Fredo AutoTarget", 200, 18)
	title:SetPoint("TOPLEFT", hd, "TOPLEFT", 54, -9)
	local ver = Wd.Text(hd, "small", "", 200, 12)
	ver:SetText("v" .. FAT.VERSION)
	ver:SetPoint("TOPLEFT", hd, "TOPLEFT", 54, -28)
	UI.closeBtn = Wd.Button(hd, 28, 28, "", UI.CloseClick, "ghost", "Fermer", "Ferme le panneau (la touche Echap le ferme aussi).")
	UI.closeBtn:SetText("x")
	UI.closeBtn:SetPoint("TOPRIGHT", hd, "TOPRIGHT", -10, -10)
	UI.langBtn = Wd.Button(hd, 116, 24, "", UI.LangClick, "normal", "Langue de l'interface",
		"Auto suit la langue du client (frFR : francais, sinon anglais). Clic : suivant, clic droit : precedent. Les noms de sorts viennent toujours du client.")
	UI.langBtn:SetPoint("TOPRIGHT", hd, "TOPRIGHT", -46, -12)
	UI.hdrToggle = Wd.Toggle(hd, 92, "", UI.HdrToggleGet, UI.HdrToggleSet, "Auto-cible activee",
		"Interrupteur general. Desactive : les sorts partent sans aucun changement de cible. Raccourci : /fat toggle.")
	UI.hdrToggle:SetPoint("TOPRIGHT", hd, "TOPRIGHT", -172, -13)
end

function UI.BuildSidebar(f)
	local sb = CreateFrame("Frame", nil, f)
	sb:SetWidth(131)
	sb:SetHeight(UI.H - 3 - 49 - 28)
	sb:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -52)
	Wd.BgBox(sb, C.panel, 0.97, C.panel)
	local rule = Wd.Tex(sb, "OVERLAY", C.line, 1, 1, UI.H - 3 - 49 - 28)
	rule:SetPoint("TOPRIGHT", sb, "TOPRIGHT", 0, 0)
	local names = { "Sorts", "Filtres", "Options", "Profils", "Aide" }
	local tipsT = {
		"Ta liste de sorts : ajout, mode de cible, repli, auto-attaque, touche, apercu et test.",
		"Filtres de ciblage : combat, distance, familiers, controle, tapes, ligne de vue, joueurs, pull.",
		"Options generales : re-ciblage, indicateur, debug, soins, assistance, marqueurs, apparence.",
		"Profils par specialisation, export et import d'une chaine copiable.",
		"Guide des modes de ciblage et liste des commandes /fat.",
	}
	local i = 1
	while names[i] do
		local tb = Wd.Button(sb, 123, 36, names[i], UI.TabClick, "ghost", names[i], tipsT[i])
		tb:SetPoint("TOPLEFT", sb, "TOPLEFT", 4, -(8 + ((i - 1) * 40)))
		tb.n = i
		tb.fs:ClearAllPoints()
		tb.fs:SetPoint("LEFT", tb, "LEFT", 42, 0)
		tb.fs:SetWidth(76)
		tb.fs:SetJustifyH("LEFT")
		tb.icon = tb:CreateTexture(nil, "ARTWORK")
		tb.icon:SetTexture(UI.TAB_ICON[i])
		tb.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		tb.icon:SetWidth(20)
		tb.icon:SetHeight(20)
		tb.icon:SetPoint("LEFT", tb, "LEFT", 14, 0)
		tb.bar = Wd.AccTexture(tb, "OVERLAY", 1, 3, 36)
		tb.bar:SetPoint("LEFT", tb, "LEFT", 0, 0)
		tb.paint = UI.PaintTab
		UI.PaintTab(tb)
		UI.tabs[i] = tb
		i = i + 1
	end
end

function UI.BuildFooter(f)
	local ft = CreateFrame("Frame", nil, f)
	ft:SetWidth(UI.W - 2)
	ft:SetHeight(27)
	ft:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
	Wd.BgBox(ft, C.panel, 0.97, C.panel)
	local rule = Wd.Tex(ft, "OVERLAY", C.line, 1, UI.W - 2, 1)
	rule:SetPoint("TOPLEFT", ft, "TOPLEFT", 0, 0)
	UI.footDot = Wd.Tex(ft, "ARTWORK", C.good, 1, 8, 8)
	UI.footDot:SetPoint("LEFT", ft, "LEFT", 16, 0)
	UI.footState = Wd.Line(ft, "body", "", 70)
	UI.footState:SetPoint("LEFT", ft, "LEFT", 30, 0)
	UI.footWhy = Wd.Line(ft, "small", "", 330)
	UI.footWhy:SetPoint("LEFT", ft, "LEFT", 104, 0)
	UI.footCount = Wd.Line(ft, "small", "", 100)
	UI.footCount:SetPoint("RIGHT", ft, "RIGHT", -190, 0)
	UI.footCount:SetJustifyH("RIGHT")
	UI.footLang = Wd.Line(ft, "small", "", 170)
	UI.footLang:SetPoint("RIGHT", ft, "RIGHT", -16, 0)
	UI.footLang:SetJustifyH("RIGHT")
end

function FAT.CreateOptionsPanel()
	if FAT.optionsFrame then
		return
	end
	local f = CreateFrame("Frame", "FredoAutoTargetOptionsFrame", UIParent)
	f:SetWidth(UI.W)
	f:SetHeight(UI.H)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	f:SetFrameStrata("DIALOG")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", UI.OnDragStart)
	f:SetScript("OnDragStop", UI.OnDragStop)
	Wd.BgBox(f, C.bg, 0.97, C.line)
	f:Hide()
	tinsert(UISpecialFrames, "FredoAutoTargetOptionsFrame") -- Echap ferme le panneau
	FAT.optionsFrame = f
	UI.frame = f

	local top = Wd.AccTexture(f, "OVERLAY", 1, UI.W - 2, 2)
	top:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)

	-- capture de touche
	local cap = CreateFrame("Frame", "FredoATKeyCapture", f)
	cap:EnableKeyboard(false)
	cap:Hide()
	cap.slot = nil
	cap:SetScript("OnKeyDown", UI.OnCaptureKey)
	UI.keyCapture = cap

	UI.BuildHeader(f)
	UI.BuildSidebar(f)
	local builders = { UI.BuildSorts, UI.BuildFilters, UI.BuildOptions, UI.BuildProfiles, UI.BuildHelp }
	local i = 1
	while builders[i] do
		local pg = CreateFrame("Frame", nil, f)
		pg:SetWidth(612)
		pg:SetHeight(488)
		pg:SetPoint("TOPLEFT", f, "TOPLEFT", 144, -60)
		pg:Hide()
		UI.pages[i] = pg
		builders[i](pg)
		i = i + 1
	end
	UI.BuildFooter(f)

	f:SetScript("OnShow", UI.OnShowPanel)
	f:SetScript("OnHide", UI.OnHidePanel)
	UI.LoadAppearance()
	UI.ShowTab(1)
end

FredoAutoTarget_CreateOptionsPanel = FAT.CreateOptionsPanel

function FredoAutoTarget_ToggleOptions()
	if not FAT.optionsFrame then
		FAT.p(Tr("Le panneau n'a pas pu etre cree (voir l'erreur au chargement, ou /reload). Les commandes /fat restent utilisables."))
		return
	end
	if FAT.optionsFrame:IsShown() then
		FAT.optionsFrame:Hide()
	else
		FAT.optionsFrame:Show()
	end
end

-- ========= Indicateur discret (meme style que le panneau) =========
function FAT.EnsureIndicator()
	if FAT.indicator then
		return FAT.indicator
	end
	local f = CreateFrame("Frame", "FredoATIndicator", UIParent)
	f:SetWidth(224)
	f:SetHeight(24)
	f:SetFrameStrata("MEDIUM")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetClampedToScreen(true)
	f:SetScript("OnDragStart", UI.OnDragStart)
	f:SetScript("OnDragStop", function()
		this:StopMovingOrSizing()
		if FAT.DB then
			FAT.DB.ui = FAT.DB.ui or {}
			FAT.DB.ui.ind = { this:GetLeft(), this:GetBottom() }
		end
	end)
	Wd.Box(f, C.bg, C.line, 0.9, 1)
	f.strip = Wd.AccTexture(f, "OVERLAY", 1, 3, 22)
	f.strip:SetPoint("LEFT", f, "LEFT", 1, 0)
	f.text = Wd.Line(f, "body", "", 208)
	f.text:SetPoint("LEFT", f, "LEFT", 10, 0)
	UI.Tip(f, "Fredo AutoTarget", "Mode du dernier sort et derniere raison de refus. Glisse pour deplacer. Desactive-le dans le panneau (Options).")
	local pos = FAT.DB and FAT.DB.ui and FAT.DB.ui.ind
	if pos and pos[1] and pos[2] then
		f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", pos[1], pos[2])
	else
		f:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
	end
	f:Hide()
	FAT.indicator = f
	return f
end

function FAT.RefreshIndicator()
	local S = FAT.S
	-- le pied de page du panneau (dernier sort / refus) suit tant qu'il est ouvert
	if FAT.optionsFrame and UI.footWhy and FAT.optionsFrame:IsShown() and FAT.DB then
		UI.RefreshChrome()
	end
	if not S.indicator then
		if FAT.indicator then
			FAT.indicator:Hide()
		end
		return
	end
	local f = FAT.EnsureIndicator()
	local L = FAT.ST.last
	local txt
	if not S.enabled then
		txt = Wd.Hex(C.warn) .. "OFF|r Fredo AutoTarget"
	elseif not L then
		txt = Wd.AccHex() .. "FAT|r " .. Tr("pret")
	else
		local label = FAT.MODE_LABEL[L.mode] or tostring(L.mode)
		if L.ok then
			txt = Wd.Hex(C.good) .. label .. "|r " .. tostring(L.spell)
		else
			txt = Wd.Hex(C.bad) .. label .. "|r " .. tostring(FAT.REASON[L.why] or L.why)
		end
	end
	f.text:SetText(txt)
	f:Show()
end
