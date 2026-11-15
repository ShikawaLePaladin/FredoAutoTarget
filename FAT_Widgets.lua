---------------------------------------------------------------
-- FAT_Widgets.lua - style (palette, accent, polices) et widgets
-- reutilisables du panneau : bouton, interrupteur, segmente,
-- curseur, saisie, section repliable. Textures integrees du client
-- uniquement (WHITE8X8). Aucun OnUpdate. Lua 5.0 / source ASCII.
-- Les widgets gardent leur etat dans des champs (f.hv, f.on...) :
-- pas de fermeture dans les boucles, chaque fonction reste petite.
---------------------------------------------------------------

local FAT = FredoAutoTarget
local Tr = FAT.Tr

FAT.UI = FAT.UI or { sel = nil, refresh = {}, tabs = {}, pages = {}, rows = {}, scope = "global", loc = {} }
local UI = FAT.UI

FAT.Wd = FAT.Wd or {}
local Wd = FAT.Wd

-- ========= Palette (aplats sombres, un seul accent) =========
Wd.TEX = "Interface\\Buttons\\WHITE8X8"
Wd.F1 = "Fonts\\FRIZQT__.TTF"
Wd.F2 = "Fonts\\ARIALN.TTF"

Wd.C = {
	bg = { 0.051, 0.055, 0.071 },
	panel = { 0.078, 0.082, 0.106 },
	card = { 0.106, 0.114, 0.145 },
	hover = { 0.155, 0.165, 0.205 },
	press = { 0.070, 0.075, 0.095 },
	line = { 0.190, 0.200, 0.250 },
	text = { 0.93, 0.94, 0.96 },
	muted = { 0.62, 0.65, 0.72 },
	faint = { 0.40, 0.43, 0.50 },
	good = { 0.35, 0.86, 0.52 },
	bad = { 0.95, 0.40, 0.40 },
	warn = { 0.98, 0.72, 0.30 },
	off = { 0.26, 0.28, 0.34 },
	dark = { 0.04, 0.045, 0.06 },
	white = { 1, 1, 1 },
	tipT = { 1, 1, 1 },          -- infobulle : titre
	tipB = { 1, 0.82, 0 },       -- infobulle : texte (or du jeu)
	tipX = { 0.70, 0.70, 0.70 }, -- infobulle : complement
}
local C = Wd.C

-- couleur de la puce de chaque mode (semantique, independante de l'accent)
Wd.MODE = {
	keep = { 0.62, 0.70, 0.82 },
	range = { 0.40, 0.70, 1.00 },
	nearest = { 0.62, 0.88, 0.38 },
	assist = { 0.35, 0.85, 0.85 },
	mark = { 1.00, 0.62, 0.25 },
	weak = { 0.95, 0.42, 0.48 },
	caster = { 0.78, 0.56, 1.00 },
	heal = { 0.30, 0.90, 0.62 },
	none = { 0.58, 0.58, 0.64 },
}

-- filet 1 px fabrique avec un fond et une bordure pleins (texture integree)
Wd.BD = {
	bgFile = Wd.TEX,
	edgeFile = Wd.TEX,
	tile = false,
	tileSize = 0,
	edgeSize = 1,
	insets = { left = 1, right = 1, top = 1, bottom = 1 },
}

-- accents au choix ; "class" = couleur de classe du joueur
Wd.ACCENTS = {
	blue = { 0.30, 0.62, 1.00 },
	green = { 0.30, 0.85, 0.52 },
	orange = { 1.00, 0.62, 0.22 },
	purple = { 0.67, 0.47, 1.00 },
	pink = { 0.97, 0.50, 0.76 },
}
Wd.ACC_LIST = { "class", "blue", "green", "orange", "purple", "pink" }
Wd.acc = { Wd.ACCENTS.blue[1], Wd.ACCENTS.blue[2], Wd.ACCENTS.blue[3] }
Wd.accKey = "class"
Wd.alpha = 1

Wd.all = {}      -- widgets qui ont une fonction de peinture (f.paint)
Wd.syncs = {}    -- widgets relus depuis les reglages a chaque rafraichissement
Wd.accTx = {}    -- textes colores par l'accent
Wd.accTex = {}   -- { texture, alpha } teintees par l'accent
Wd.bgs = {}      -- cadres dont le fond suit le reglage d'opacite

-- ========= Couleurs =========
function Wd.Mix(a, b, t)
	return { a[1] + ((b[1] - a[1]) * t), a[2] + ((b[2] - a[2]) * t), a[3] + ((b[3] - a[3]) * t) }
end

function Wd.Hex(c)
	return string.format("|cff%02x%02x%02x", math.floor((c[1] * 255) + 0.5), math.floor((c[2] * 255) + 0.5), math.floor((c[3] * 255) + 0.5))
end

-- texte lisible sur un aplat d'accent (sombre sur accent clair, blanc sinon)
function Wd.AccHex()
	return Wd.Hex(Wd.acc)
end

function Wd.OnAcc()
	local a = Wd.acc
	if ((a[1] * 0.299) + (a[2] * 0.587) + (a[3] * 0.114)) > 0.55 then
		return C.dark
	end
	return C.white
end

function Wd.AccentRGB(key)
	local a = Wd.ACCENTS[key or ""]
	if a then
		return a[1], a[2], a[3]
	end
	local cls = FAT.PlayerClass and FAT.PlayerClass()
	local col = cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
	if col then
		return col.r, col.g, col.b
	end
	return Wd.ACCENTS.blue[1], Wd.ACCENTS.blue[2], Wd.ACCENTS.blue[3]
end

-- ========= Textes, textures =========
Wd.KINDS = {
	title = { Wd.F1, 14, "text" },
	head = { Wd.F1, 11, "text" },
	body = { Wd.F1, 11, "text" },
	small = { Wd.F1, 10, "muted" },
	label = { Wd.F1, 10, "muted" },
	help = { Wd.F2, 12, "muted" },
	dense = { Wd.F2, 12, "text" },
	acc = { Wd.F1, 11, "acc" },
}

function Wd.SetColor(fs, key)
	local c = C[key]
	if c then
		fs:SetTextColor(c[1], c[2], c[3])
	end
end

-- pose le texte traduit et le memorise (texte FR d'origine) pour le changement de langue
function Wd.Reg(obj, src)
	obj:SetText(Tr(src))
	if src ~= "" then
		tinsert(UI.loc, { obj, src })
	end
end
UI.Reg = Wd.Reg

-- ========= Mesure et coupe des textes d'une ligne =========
-- Un FontString de largeur fixe passe a la ligne puis cache le surplus : un nom de sort trop long
-- perdrait ses derniers mots. Les textes d'une ligne (Wd.Line) sont donc mesures sur un FontString
-- sans largeur (cree une seule fois au chargement) et coupes avec ".." s'ils depassent.
Wd.meas = nil
function Wd.MakeMeasure()
	local fr = CreateFrame("Frame", nil, UIParent)
	fr:SetWidth(1)
	fr:SetHeight(1)
	fr:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -600, 600)
	fr:SetAlpha(0)
	Wd.meas = fr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	Wd.meas:SetPoint("TOPLEFT", fr, "TOPLEFT", 0, 0)
	-- second FontString, a largeur fixe : donne la hauteur reelle d'un bloc de plusieurs lignes
	Wd.meas2 = fr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	Wd.meas2:SetPoint("TOPLEFT", fr, "TOPLEFT", 0, 0)
end

-- hauteur reelle (retour a la ligne compris) de text dans la zone de fs ; nil si la mesure n'est pas fiable
function Wd.BlockH(fs, text)
	local m = Wd.meas2
	if not m then
		return nil
	end
	m:SetFont(fs.fnt, fs.size)
	m:SetWidth(fs:GetWidth())
	m:SetText(text)
	local h = m:GetStringHeight()
	if h and h > 0 then
		return h
	end
	return nil
end

-- pose text dans fs (zone de hauteur fixe) ; si le bloc deborde, retire des mots a la fin puis ajoute ".."
function Wd.SetFit(fs, text)
	local maxH = fs:GetHeight()
	local h = Wd.BlockH(fs, text)
	if (not h) or h <= maxH + 0.5 then
		fs:SetText(text)
		return
	end
	local plain = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
	plain = string.gsub(plain, "|r", "")
	local n = string.len(plain)
	local guard = 0
	while n > 4 and guard < 400 do
		guard = guard + 1
		n = n - 4
		local cand = Wd.Utf8Cut(plain, n) .. ".."
		local hc = Wd.BlockH(fs, cand)
		if (not hc) or hc <= maxH + 0.5 then
			fs:SetText(cand)
			return
		end
	end
	fs:SetText(text)
end

function Wd.Measure(fs, text)
	local m = Wd.meas
	if not m then
		return nil
	end
	m:SetFont(fs.fnt, fs.size)
	m:SetText(text)
	return m:GetStringWidth()
end

-- coupe sur une frontiere de caractere UTF-8 : garde au plus n octets
function Wd.Utf8Cut(s, n)
	if n >= string.len(s) then
		return s
	end
	local b = string.byte(s, n + 1)
	while n > 0 and b and b >= 128 and b < 192 do
		n = n - 1
		b = string.byte(s, n + 1)
	end
	return string.sub(s, 1, n)
end

function Wd.ClipText(fs, text)
	local w = fs:GetWidth()
	if (not fs.clip) or (not w) or w < 8 or text == "" then
		return text
	end
	local m = Wd.Measure(fs, text)
	if (not m) or m <= w then
		return text
	end
	-- les codes couleur sont retires (la coupe ne doit pas tomber au milieu)
	local plain = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
	plain = string.gsub(plain, "|r", "")
	local n = string.len(plain)
	while n > 1 do
		n = n - 1
		local cand = Wd.Utf8Cut(plain, n) .. ".."
		local mc = Wd.Measure(fs, cand)
		if (not mc) or mc <= w then
			return cand
		end
	end
	return string.sub(plain, 1, 1)
end

function Wd.LineSet(fs, t)
	fs.setRaw(fs, Wd.ClipText(fs, t))
end

-- texte multi-ligne (largeur w), a coller en haut
function Wd.Text(parent, kind, text, w, h)
	local d = Wd.KINDS[kind] or Wd.KINDS.body
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fs:SetFont(d[1], d[2])
	if d[3] == "acc" then
		fs:SetTextColor(Wd.acc[1], Wd.acc[2], Wd.acc[3])
		tinsert(Wd.accTx, fs)
	else
		Wd.SetColor(fs, d[3])
	end
	fs.size = d[2]
	fs.fnt = d[1]
	fs:SetJustifyH("LEFT")
	fs:SetJustifyV("TOP")
	if w then
		fs:SetWidth(w)
	end
	if h then
		fs:SetHeight(h)
	end
	Wd.Reg(fs, text or "")
	return fs
end

-- texte d'une seule ligne (coupe au lieu de passer a la ligne)
function Wd.Line(parent, kind, text, w)
	local d = Wd.KINDS[kind] or Wd.KINDS.body
	local fs = Wd.Text(parent, kind, nil, w, d[2] + 3)
	fs:SetJustifyV("MIDDLE")
	fs.clip = true
	fs.setRaw = fs.SetText
	fs.SetText = Wd.LineSet
	Wd.Reg(fs, text or "")
	return fs
end

function Wd.Tex(parent, layer, c, a, w, h)
	local t = parent:CreateTexture(nil, layer or "ARTWORK")
	t:SetTexture(Wd.TEX)
	if c then
		t:SetVertexColor(c[1], c[2], c[3], a or 1)
	end
	if w then
		t:SetWidth(w)
	end
	if h then
		t:SetHeight(h)
	end
	return t
end

-- texture teintee par l'accent (suit le choix de couleur a chaud)
function Wd.AccTexture(parent, layer, a, w, h)
	local t = Wd.Tex(parent, layer, Wd.acc, a, w, h)
	tinsert(Wd.accTex, { t, a or 1 })
	return t
end

function Wd.At(f, parent, x, y)
	f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
	return f
end

-- fond plein + filet 1 px
function Wd.Box(f, bg, bd, bga, bda)
	f:SetBackdrop(Wd.BD)
	f:SetBackdropColor(bg[1], bg[2], bg[3], bga or 1)
	f:SetBackdropBorderColor(bd[1], bd[2], bd[3], bda or 1)
end

-- idem, mais le fond suit le reglage d'opacite de la fenetre
function Wd.BgBox(f, bg, a, bd)
	f.wbg = bg
	f.wba = a
	Wd.Box(f, bg, bd, a * Wd.alpha, 1)
	tinsert(Wd.bgs, f)
end

function Wd.ApplyBg()
	local i = 1
	while Wd.bgs[i] do
		local f = Wd.bgs[i]
		f:SetBackdropColor(f.wbg[1], f.wbg[2], f.wbg[3], f.wba * Wd.alpha)
		i = i + 1
	end
end

-- recolore tout ce qui depend de l'accent puis repeint les widgets
function Wd.Repaint()
	local a = Wd.acc
	local i = 1
	while Wd.accTx[i] do
		Wd.accTx[i]:SetTextColor(a[1], a[2], a[3])
		i = i + 1
	end
	i = 1
	while Wd.accTex[i] do
		local r = Wd.accTex[i]
		r[1]:SetVertexColor(a[1], a[2], a[3], r[2])
		i = i + 1
	end
	i = 1
	while Wd.all[i] do
		local w = Wd.all[i]
		w.paint(w)
		i = i + 1
	end
end

function Wd.SetAccent(key)
	local ok = false
	local i = 1
	while Wd.ACC_LIST[i] do
		if Wd.ACC_LIST[i] == key then
			ok = true
		end
		i = i + 1
	end
	if not ok then
		key = "class"
	end
	local r, g, b = Wd.AccentRGB(key)
	Wd.accKey = key
	Wd.acc = { r, g, b }
	Wd.Repaint()
end

function Wd.SyncAll()
	local i = 1
	while Wd.syncs[i] do
		local w = Wd.syncs[i]
		w.sync(w)
		i = i + 1
	end
end

-- ========= Infobulles et etats (survol / pression / desactive) =========
function Wd.Tip(f, title, text, extra)
	f.tipTitle = title
	f.tipText = text
	f.tipExtra = extra
end

function Wd.ShowTip()
	if not this.tipTitle then
		return
	end
	Wd.tipOwner = this
	GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
	GameTooltip:SetText(Tr(this.tipTitle), C.tipT[1], C.tipT[2], C.tipT[3])
	if this.tipText then
		GameTooltip:AddLine(Tr(this.tipText), C.tipB[1], C.tipB[2], C.tipB[3], 1)
	end
	if this.tipExtra then
		GameTooltip:AddLine(Tr(this.tipExtra), C.tipX[1], C.tipX[2], C.tipX[3], 1)
	end
	GameTooltip:Show()
end

function Wd.HideTip()
	Wd.tipOwner = nil
	GameTooltip:Hide()
end

-- un cadre masque pendant son survol ne recoit pas OnLeave : on retire l'infobulle qu'il avait ouverte
function Wd.DropTip()
	local o = Wd.tipOwner
	if o and GameTooltip:IsOwned(o) then
		GameTooltip:Hide()
	end
	Wd.tipOwner = nil
end

-- cadre simple avec infobulle (indicateur...)
function UI.Tip(f, title, text, extra)
	Wd.Tip(f, title, text, extra)
	f:SetScript("OnEnter", Wd.ShowTip)
	f:SetScript("OnLeave", Wd.HideTip)
end

function Wd.OnEnter()
	this.hv = true
	this.paint(this)
	Wd.ShowTip()
end

function Wd.OnLeave()
	this.hv = nil
	if not (this.c and this.dn and Wd.MouseDown()) then
		this.dn = nil
	end
	this.paint(this)
	GameTooltip:Hide()
end

function Wd.OnDown()
	this.dn = true
	this.paint(this)
end

function Wd.OnUp()
	this.dn = nil
	this.paint(this)
	if this.c and this.c.pend ~= nil then
		Wd.SliderFlush(this.c)
	end
end

function Wd.OnHideW()
	this.hv = nil
	this.dn = nil
	if Wd.tipOwner == this then
		Wd.DropTip()
	end
	if this.c and this.c.pend ~= nil then
		Wd.SliderFlush(this.c)
	end
end

function Wd.OnClick()
	local b = this
	if b.disabled then
		return
	end
	if b.act then
		b.act(b, arg1)
	end
end

-- branche les etats d'un widget : paint(f) est rappelee a chaque changement
function Wd.Hook(f, paint)
	f.paint = paint
	f:SetScript("OnEnter", Wd.OnEnter)
	f:SetScript("OnLeave", Wd.OnLeave)
	f:SetScript("OnMouseDown", Wd.OnDown)
	f:SetScript("OnMouseUp", Wd.OnUp)
	f:SetScript("OnHide", Wd.OnHideW)
	tinsert(Wd.all, f)
	paint(f)
end

function Wd.SetDisabled(f, v)
	f.disabled = v and true or nil
	if f.paint then
		f.paint(f)
	end
end

-- ========= Bouton =========
-- styles : normal, accent (mis en avant), ghost (sans fond), danger, seg (cellule de controle segmente)
function Wd.PaintButton(b)
	local A = Wd.acc
	local st = b.style
	local bg, bga, bd, bda, tc = C.card, 1, C.line, 1, C.text
	if st == "ghost" then
		bga = 0
		bda = 0
		tc = C.muted
	elseif st == "seg" then
		tc = C.muted
	end
	if b.disabled then
		bg, bd, tc = C.panel, C.line, C.faint
		if st ~= "ghost" then
			bga = 1
			bda = 0.6
		end
	elseif st == "accent" then
		bg, bd, tc = A, A, Wd.OnAcc()
		bga = 1
		bda = 1
		if b.dn then
			bg = Wd.Mix(A, C.dark, 0.35)
		elseif b.hv then
			bg = Wd.Mix(A, C.white, 0.2)
		end
	elseif b.on then
		bg, bd, tc = Wd.Mix(C.card, A, 0.30), A, C.text
		bga = 1
		bda = 1
		if b.hv then
			bg = Wd.Mix(C.card, A, 0.42)
		end
	elseif b.dn then
		bg, bd, bga, bda = C.press, Wd.Mix(C.line, A, 0.8), 1, 1
	elseif b.hv then
		bg, bd, tc = C.hover, Wd.Mix(C.line, A, 0.6), C.text
		bga = 1
		bda = 1
		if st == "danger" then
			bg, bd, tc = Wd.Mix(C.card, C.bad, 0.25), C.bad, C.bad
		end
	elseif b.dim then
		bd, tc, bda = Wd.Mix(C.line, A, 0.8), C.text, 1
	end
	b:SetBackdropColor(bg[1], bg[2], bg[3], bga)
	b:SetBackdropBorderColor(bd[1], bd[2], bd[3], bda)
	b.fs:SetTextColor(tc[1], tc[2], tc[3])
end

function Wd.BSet(b, t)
	b.fs:SetText(t)
end

function Wd.BGet(b)
	return b.fs:GetText()
end

-- act(b, bouton_souris) ; text = texte FR (vide : pose plus tard par le rafraichissement)
function Wd.Button(parent, w, h, text, act, style, title, tip, extra, kind)
	local b = CreateFrame("Button", nil, parent)
	b:SetWidth(w)
	b:SetHeight(h)
	b.style = style or "normal"
	b.act = act
	b.SetText = Wd.BSet
	b.GetText = Wd.BGet
	Wd.Box(b, C.card, C.line)
	b.fs = Wd.Line(b, kind or "body", text or "", w - (kind and 4 or 6))
	b.fs:SetPoint("CENTER", b, "CENTER", 0, 0)
	b.fs:SetJustifyH("CENTER")
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:SetScript("OnClick", Wd.OnClick)
	if title then
		Wd.Tip(b, title, tip, extra)
	end
	Wd.Hook(b, Wd.PaintButton)
	return b
end

-- ========= Interrupteur (toggle) =========
-- getFn(t) lit la valeur, setFn(bool, t) l'ecrit ; hasSub : seconde ligne (t.sub)
function Wd.PaintToggle(t)
	local A = Wd.acc
	local tr = C.off
	if t.on then
		tr = A
	end
	if t.disabled then
		tr = Wd.Mix(tr, C.bg, 0.55)
	elseif t.hv then
		tr = Wd.Mix(tr, C.white, 0.14)
	end
	t.track:SetVertexColor(tr[1], tr[2], tr[3], 1)
	t.knob:ClearAllPoints()
	local k = C.muted
	if t.on then
		t.knob:SetPoint("RIGHT", t.track, "RIGHT", -2, 0)
		k = C.white
	else
		t.knob:SetPoint("LEFT", t.track, "LEFT", 2, 0)
	end
	t.knob:SetVertexColor(k[1], k[2], k[3], t.disabled and 0.5 or 1)
	local tc = t.disabled and C.faint or C.text
	t.lab:SetTextColor(tc[1], tc[2], tc[3])
end

function Wd.SyncToggle(t)
	t.on = (t.getFn(t) and true) or false
	Wd.PaintToggle(t)
end

function Wd.ToggleClick(t)
	if t.setFn then
		t.setFn(not (t.getFn(t) and true or false), t)
	end
	FAT.UIRefresh()
end

function Wd.Toggle(parent, w, label, getFn, setFn, title, tip, extra, hasSub)
	local t = CreateFrame("Button", nil, parent)
	t:SetWidth(w)
	t:SetHeight(hasSub and 32 or 24)
	t.getFn = getFn
	t.setFn = setFn
	t.act = Wd.ToggleClick
	t.track = Wd.Tex(t, "ARTWORK", C.off, 1, 28, 14)
	t.track:SetPoint("TOPLEFT", t, "TOPLEFT", 0, hasSub and -2 or -5)
	t.knob = Wd.Tex(t, "OVERLAY", C.white, 1, 10, 10)
	t.lab = Wd.Line(t, "body", label, w - 34)
	t.lab:SetPoint("TOPLEFT", t, "TOPLEFT", 34, hasSub and -1 or -5)
	if hasSub then
		t.sub = Wd.Line(t, "small", "", w - 34)
		t.sub:SetPoint("TOPLEFT", t, "TOPLEFT", 34, -17)
	end
	t:RegisterForClicks("LeftButtonUp")
	t:SetScript("OnClick", Wd.OnClick)
	Wd.Tip(t, title or label, tip, extra)
	t.sync = Wd.SyncToggle
	tinsert(Wd.syncs, t)
	Wd.Hook(t, Wd.PaintToggle)
	return t
end

-- ========= Curseur (barre de remplissage a l'accent + valeur affichee) =========
function Wd.PaintSlider(s)
	local th = s:GetThumbTexture()
	local c = s.c
	local col = C.text
	if s.hv or s.dn then
		col = Wd.acc
	end
	th:SetVertexColor(col[1], col[2], col[3], 1)
	local lc = c.disabled and C.faint or C.muted
	c.lab:SetTextColor(lc[1], lc[2], lc[3])
end

function Wd.SliderUpdate(c, shown)
	local v = shown
	if v == nil then
		v = c.getFn(c)
	end
	if v == nil then
		v = c.lo
	end
	local frac = (v - c.lo) / (c.hi - c.lo)
	if frac < 0 then
		frac = 0
	elseif frac > 1 then
		frac = 1
	end
	if frac <= 0 then
		c.fill:Hide()
	else
		c.fill:Show()
		c.fill:SetWidth(math.max(1, math.floor(c.w * frac)))
	end
	c.val:SetText(c.fmt(v))
end

function Wd.SyncSlider(c)
	if c.pend ~= nil then
		return
	end
	local v = c.getFn(c)
	if v ~= nil then
		c.sld.busy = true
		c.sld:SetValue(v)
		c.sld.busy = nil
	end
	Wd.SliderUpdate(c)
end

function Wd.SliderChanged()
	local s = this
	if s.busy then
		return
	end
	local c = s.c
	local v = math.floor((s:GetValue() * 100) + 0.5) / 100
	if v < c.lo then
		v = c.lo
	elseif v > c.hi then
		v = c.hi
	end
	-- reglage "differe" (taille de la fenetre) : la valeur s'affiche pendant le glissement mais ne
	-- s'applique qu'au relachement (redimensionner la fenetre sous le curseur ferait osciller le curseur)
	if c.defer and s.dn and Wd.MouseDown() then
		c.pend = v
		Wd.SliderUpdate(c, v)
		return
	end
	c.pend = nil
	c.setFn(v, c)
	Wd.SliderUpdate(c)
end

function Wd.MouseDown()
	local f = FAT.Api("IsMouseButtonDown")
	if not f then
		return true
	end
	return f("LeftButton") and true or false
end

-- applique la valeur en attente (relachement, sortie du curseur, fermeture)
function Wd.SliderFlush(c)
	local v = c.pend
	if v ~= nil then
		c.pend = nil
		c.setFn(v, c)
		Wd.SliderUpdate(c)
	end
end

function Wd.Slider(parent, w, label, lo, hi, step, getFn, setFn, fmt, title, tip, extra, defer)
	local c = CreateFrame("Frame", nil, parent)
	c.defer = defer
	c:SetWidth(w)
	c:SetHeight(36)
	c.w = w
	c.lo = lo
	c.hi = hi
	c.getFn = getFn
	c.setFn = setFn
	c.fmt = fmt
	c.lab = Wd.Line(c, "label", label, w - 96)
	c.lab:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
	c.val = Wd.Line(c, "body", "", 92)
	c.val:SetPoint("TOPRIGHT", c, "TOPRIGHT", 0, 0)
	c.val:SetJustifyH("RIGHT")
	c.track = Wd.Tex(c, "BACKGROUND", C.line, 1, w, 4)
	c.track:SetPoint("TOPLEFT", c, "TOPLEFT", 0, -24)
	c.fill = Wd.AccTexture(c, "ARTWORK", 1, 1, 4)
	c.fill:SetPoint("TOPLEFT", c, "TOPLEFT", 0, -24)
	local s = CreateFrame("Slider", nil, c)
	s:SetWidth(w)
	s:SetHeight(16)
	s:SetPoint("TOPLEFT", c, "TOPLEFT", 0, -18)
	s:SetOrientation("HORIZONTAL")
	s:SetMinMaxValues(lo, hi)
	s:SetValueStep(step)
	s:SetThumbTexture(Wd.TEX)
	local th = s:GetThumbTexture()
	th:SetWidth(8)
	th:SetHeight(14)
	s:EnableMouse(true)
	s.c = c
	c.sld = s
	s:SetScript("OnValueChanged", Wd.SliderChanged)
	Wd.Tip(s, title or label, tip, extra)
	c.sync = Wd.SyncSlider
	tinsert(Wd.syncs, c)
	Wd.Hook(s, Wd.PaintSlider)
	return c
end

-- ========= Controle segmente =========
-- items : { { cle, libelle FR, titre, texte, extra }, ... } ; act(cle, bouton, seg) ; getFn(seg) -> cle [, cle par defaut]
function Wd.SegClick(c, btn)
	local s = c.seg
	if s.act then
		s.act(c.key, btn, s)
	end
end

function Wd.SegSelect(s, key, dimKey)
	local base = s:GetFrameLevel()
	local i = 1
	while s.cells[i] do
		local c = s.cells[i]
		c.on = (c.key == key) or nil
		c.dim = ((dimKey ~= nil) and (c.key == dimKey) and (not c.on)) or nil
		c:SetFrameLevel(base + (c.on and 3 or (c.dim and 2 or 1)))
		c.paint(c)
		i = i + 1
	end
end

function Wd.SyncSeg(s)
	local k, d
	if s.getFn then
		k, d = s.getFn(s)
	end
	Wd.SegSelect(s, k, d)
end

function Wd.SegDisable(s, v)
	local i = 1
	while s.cells[i] do
		Wd.SetDisabled(s.cells[i], v)
		i = i + 1
	end
end

function Wd.Seg(parent, w, rowH, cols, items, act, getFn, small)
	local s = CreateFrame("Frame", nil, parent)
	local n = 0
	while items[n + 1] do
		n = n + 1
	end
	local rows = math.floor((n + cols - 1) / cols)
	s:SetWidth(w)
	s:SetHeight((rows * (rowH - 1)) + 1)
	s.act = act
	s.getFn = getFn
	s.cells = {}
	local cw = math.floor((w + (cols - 1)) / cols)
	local i = 1
	while i <= n do
		local it = items[i]
		local col = math.mod(i - 1, cols)
		local row = math.floor((i - 1) / cols)
		local x = col * (cw - 1)
		local width = cw
		if col == (cols - 1) then
			width = w - x
		end
		local b = Wd.Button(s, width, rowH, it[2] or "", Wd.SegClick, "seg", it[3] or it[2], it[4], it[5], small and "small" or nil)
		b:SetPoint("TOPLEFT", s, "TOPLEFT", x, -(row * (rowH - 1)))
		b.seg = s
		b.key = it[1]
		s.cells[i] = b
		i = i + 1
	end
	s.sync = Wd.SyncSeg
	tinsert(Wd.syncs, s)
	return s
end

-- ========= Zone de saisie =========
function Wd.PaintInput(e)
	local bd = C.line
	if e.focused then
		bd = Wd.acc
	elseif e.hv then
		bd = Wd.Mix(C.line, Wd.acc, 0.55)
	end
	e:SetBackdropBorderColor(bd[1], bd[2], bd[3], 1)
end

function Wd.InputEnter()
	local e = this
	if e.onEnter then
		e.onEnter(e:GetText(), e)
	end
	e:ClearFocus()
end

function Wd.InputEsc()
	this:ClearFocus()
end

function Wd.InputFocus()
	this.focused = true
	Wd.PaintInput(this)
end

function Wd.InputBlur()
	this.focused = nil
	Wd.PaintInput(this)
end

function Wd.InputEnterHover()
	this.hv = true
	Wd.PaintInput(this)
	Wd.ShowTip()
end

function Wd.InputLeaveHover()
	this.hv = nil
	Wd.PaintInput(this)
	GameTooltip:Hide()
end

function Wd.Input(parent, w, h, maxLetters, onEnter, title, tip, extra)
	local e = CreateFrame("EditBox", nil, parent)
	e:SetWidth(w)
	e:SetHeight(h)
	e:SetFont(Wd.F1, 11)
	e:SetTextColor(C.text[1], C.text[2], C.text[3])
	e:SetTextInsets(8, 8, 0, 0)
	e:SetAutoFocus(false)
	e:SetMaxLetters(maxLetters or 60)
	Wd.Box(e, C.bg, C.line)
	e.onEnter = onEnter
	e:SetScript("OnEnterPressed", Wd.InputEnter)
	e:SetScript("OnEscapePressed", Wd.InputEsc)
	e:SetScript("OnEditFocusGained", Wd.InputFocus)
	e:SetScript("OnEditFocusLost", Wd.InputBlur)
	if title then
		Wd.Tip(e, title, tip, extra)
	end
	e:SetScript("OnEnter", Wd.InputEnterHover)
	e:SetScript("OnLeave", Wd.InputLeaveHover)
	e.paint = Wd.PaintInput
	tinsert(Wd.all, e)
	Wd.PaintInput(e)
	return e
end

-- ========= Section repliable =========
function Wd.PaintGroup(h)
	local tc = h.hv and C.white or C.text
	h.fs:SetTextColor(tc[1], tc[2], tc[3])
end

function Wd.GroupOpen(g)
	local u = FAT.DB and FAT.DB.ui
	if u and u.collapsed and u.collapsed[g.key] then
		return false
	end
	return true
end

function Wd.StackLayout(st)
	local y = st.y
	local i = 1
	while st.groups[i] do
		local g = st.groups[i]
		local open = Wd.GroupOpen(g)
		g.open = open
		g.head:ClearAllPoints()
		g.head:SetPoint("TOPLEFT", st.parent, "TOPLEFT", st.x, -y)
		g.head.chev:SetText(open and "v" or ">")
		y = y + 24
		if open then
			g.body:ClearAllPoints()
			g.body:SetPoint("TOPLEFT", st.parent, "TOPLEFT", st.x, -(y + 4))
			g.body:SetHeight(g.h)
			g.body:Show()
			y = y + 4 + g.h
		else
			g.body:Hide()
		end
		y = y + 12
		i = i + 1
	end
	st.height = y - st.y
end

function Wd.GroupClick(h)
	local g = h.g
	FAT.DB.ui = FAT.DB.ui or {}
	FAT.DB.ui.collapsed = FAT.DB.ui.collapsed or {}
	if Wd.GroupOpen(g) then
		FAT.DB.ui.collapsed[g.key] = true
	else
		FAT.DB.ui.collapsed[g.key] = nil
	end
	Wd.StackLayout(g.st)
end

function Wd.Stack(parent, x, y, w)
	return { parent = parent, x = x, y = y, w = w, groups = {}, height = 0 }
end

function Wd.Group(st, key, title)
	local g = { key = key, st = st, y = 0, h = 0 }
	local hd = CreateFrame("Button", nil, st.parent)
	hd:SetWidth(st.w)
	hd:SetHeight(24)
	hd.g = g
	hd.act = Wd.GroupClick
	hd.fs = Wd.Line(hd, "head", title, st.w - 28)
	hd.fs:SetPoint("LEFT", hd, "LEFT", 20, 0)
	hd.chev = Wd.Line(hd, "acc", "", 16)
	hd.chev:SetPoint("LEFT", hd, "LEFT", 4, 0)
	hd.rule = Wd.Tex(hd, "ARTWORK", C.line, 1, st.w, 1)
	hd.rule:SetPoint("BOTTOMLEFT", hd, "BOTTOMLEFT", 0, 0)
	hd:RegisterForClicks("LeftButtonUp")
	hd:SetScript("OnClick", Wd.OnClick)
	Wd.Tip(hd, title, "Clic : replier ou deplier cette section.")
	Wd.Hook(hd, Wd.PaintGroup)
	g.head = hd
	g.body = CreateFrame("Frame", nil, st.parent)
	g.body:SetWidth(st.w)
	g.body:SetHeight(1)
	tinsert(st.groups, g)
	return g
end

-- place un widget dans le corps de la section (curseur vertical g.y)
function Wd.Put(g, f, h, x, w)
	f:SetPoint("TOPLEFT", g.body, "TOPLEFT", x or 0, -g.y)
	if w then
		f:SetWidth(w)
	end
	g.y = g.y + h + 4
	return f
end

function Wd.Fit(g)
	g.h = math.max(1, g.y - 4)
	g.body:SetHeight(g.h)
	Wd.StackLayout(g.st)
end

Wd.MakeMeasure()
