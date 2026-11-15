---------------------------------------------------------------
-- FredoAutoTarget.lua - coeur de FredoAutoTarget 2.0 (WoW 1.12 / Lua 5.0)
--
-- Pour chaque sort de ta liste : l'addon choisit la cible AVANT le
-- sort (garder / a portee / plus proche / assister / prioritaire /
-- plus faible / lanceur / soigner / pas de changement), lance le sort
-- puis demarre l'auto-attaque. Declencheurs : touche de l'addon, barre
-- d'action, macro (/cast), livre de sorts.
--
-- Ciblage a FILTRES : jusqu'a 8 candidats sont parcourus dans l'ordre
-- de proximite (ClearTarget puis TargetNearestEnemy) ; le premier
-- valide est garde (modes a score : le meilleur). Un mob hors combat,
-- trop loin, mort, controle, tape par un autre, familier/totem... est
-- refuse. Aucun candidat valide : on revient a la cible d'avant.
--
-- Lua 5.0 : 32 upvalues max par fonction -> tout est range dans des
-- tables (FAT = FredoAutoTarget). Aucun OnUpdate permanent : seulement
-- des evenements et un minuteur d'un coup qui s'eteint tout seul.
---------------------------------------------------------------

FredoAutoTarget = FredoAutoTarget or {}
local FAT = FredoAutoTarget

-- ========= Etat =========
FAT.ST = {
	busy = false,        -- vrai pendant qu'on traite un sort (anti-recursion)
	lastAcquire = 0,     -- derniere acquisition "plus proche" (GetTime)
	attacking = false,   -- auto-attaque en cours (PLAYER_ENTER/LEAVE_COMBAT)
	castEnd = 0,         -- fin presumee de l'incantation en cours
	keyDown = false,     -- appel venant d'une touche de barre d'action
	lastEntry = nil,     -- dernier sort traite (pour le re-ciblage)
	lastEntryAt = 0,
	retargetAt = 0,
	casters = {},        -- nom de mob (normalise) -> heure du dernier "commence a lancer"
	last = nil,          -- {spell, mode, ok, why, name} pour l'indicateur et /fat status
	lastCast = nil,      -- dernier sort lance (pour "ajouter le dernier sort")
	delay = nil,         -- cadre du minuteur d'un coup
	delayItems = {},
}
FAT.orig = {}            -- fonctions d'origine (CastSpellByName, CastSpell, UseAction...)
FAT.DB = nil

local function CopyTable(t)
	if type(t) ~= "table" then
		return t
	end
	local c = {}
	local k, v
	for k, v in pairs(t) do
		c[k] = CopyTable(v)
	end
	return c
end
FAT.CopyTable = CopyTable

-- reglages vivants (copie des defauts tant que la base n'est pas chargee)
FAT.S = CopyTable(FAT.DEFAULTS)

-- ========= Messages =========
function FAT.d(msg)
	if FAT.S.debug and DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage("|cff88ccff[FredoAT]|r " .. tostring(msg))
	end
end

function FAT.p(msg)
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00[FredoAT]|r " .. tostring(msg))
	end
end

-- ========= Utilitaires =========
-- Lettres accentuees UTF-8 (2 octets, premier = 195) -> ASCII, pour
-- comparer "Frappe h\195\169ro\195\175que" et "frappe heroique".
local FOLD = {
	[128] = "A", [129] = "A", [130] = "A", [131] = "A", [132] = "A", [133] = "A", [134] = "AE", [135] = "C",
	[136] = "E", [137] = "E", [138] = "E", [139] = "E", [140] = "I", [141] = "I", [142] = "I", [143] = "I",
	[145] = "N", [146] = "O", [147] = "O", [148] = "O", [149] = "O", [150] = "O", [153] = "U", [154] = "U",
	[155] = "U", [156] = "U",
	[160] = "a", [161] = "a", [162] = "a", [163] = "a", [164] = "a", [165] = "a", [166] = "ae", [167] = "c",
	[168] = "e", [169] = "e", [170] = "e", [171] = "e", [172] = "i", [173] = "i", [174] = "i", [175] = "i",
	[177] = "n", [178] = "o", [179] = "o", [180] = "o", [181] = "o", [182] = "o", [185] = "u", [186] = "u",
	[187] = "u", [188] = "u", [189] = "y", [191] = "y",
}

function FAT.Fold(s)
	s = tostring(s or "")
	s = string.gsub(s, "\195([\128-\191])", function(c) return FOLD[string.byte(c)] or "" end)
	s = string.gsub(s, "\197\147", "oe")
	s = string.gsub(s, "\197\146", "OE")
	s = string.gsub(s, "\226\128[\152\153]", "'")   -- apostrophe typographique -> '
	s = string.gsub(s, "\194\160", " ")             -- espace insecable -> espace
	return s
end

function FAT.Trim(s)
	s = tostring(s or "")
	s = string.gsub(s, "^%s+", "")
	s = string.gsub(s, "%s+$", "")
	return s
end

-- Le rang est une parenthese finale qui contient un chiffre : "(Rank 2)", "(Rang 3)", "(Niveau 4)".
-- Une parenthese sans chiffre fait partie du nom : "Faerie Fire (Feral)" / "Lucioles (farouche)".
local RANK_PAT = "%s*%([^%)%d]*%d[^%)]*%)%s*$"

-- "Charge(Rank 2)" / "Charge (Rang 2)" / " Frappe h\195\169ro\195\175que " -> "charge" / "frappe heroique"
function FAT.Norm(name)
	if not name then
		return ""
	end
	local n = string.lower(FAT.Fold(name))
	n = string.gsub(n, RANK_PAT, "")
	n = string.gsub(n, "^%s+", "")
	n = string.gsub(n, "%s+$", "")
	n = string.gsub(n, "%s%s+", " ")
	return n
end

-- nom de sort sans le rang, casse conservee
function FAT.BaseName(name)
	local n = FAT.Trim(name)
	n = string.gsub(n, RANK_PAT, "")
	return n
end

-- ========= Noms de sorts : un meme sort peut s'appeler "Heroic Strike" (EN) ou "Frappe heroique" (FR) =========
-- Table : nom normalise (EN, FR ou autre nom FR connu des presets) -> nom EN normalise du preset.
-- Un sort hors presets n'a que son propre nom normalise.
function FAT.BuildCanon()
	local map = {}
	local clash = {}
	local cls, list
	for cls, list in pairs(FAT.PRESETS) do
		local i = 1
		while list[i] do
			local it = list[i]
			local en = FAT.Norm(it[1])
			local names = { en, FAT.Norm(it[2]) }
			local a = 1
			while it[5] and it[5][a] do
				tinsert(names, FAT.Norm(it[5][a]))
				a = a + 1
			end
			local j = 1
			while names[j] do
				local nm = names[j]
				if map[nm] and map[nm] ~= en then
					clash[nm] = true
				else
					map[nm] = en
				end
				j = j + 1
			end
			i = i + 1
		end
	end
	FAT.canonMap = map
	FAT.canonClash = clash
	return map
end

-- identifiant d'un nom de sort, identique pour ses noms EN et FR
function FAT.Canon(name)
	local n = FAT.Norm(name)
	if n == "" then
		return n
	end
	local map = FAT.canonMap or FAT.BuildCanon()
	return map[n] or n
end

-- nom du sort tel que le CLIENT le donne (livre de sorts), ou le nom demande si le sort n'y est pas
function FAT.ClientName(name)
	local c = FAT.Canon(name)
	if c == "" then
		return name
	end
	local i = 1
	while true do
		local sn = GetSpellName(i, "spell")
		if not sn then
			break
		end
		if FAT.Canon(sn) == c then
			return FAT.BaseName(sn)
		end
		i = i + 1
	end
	return name
end

-- ========= Types de creature =========
-- "Non-combat Pet" / "Mort-vivant" -> "non combat pet" / "mort vivant"
function FAT.TypeKey(ct)
	local k = string.lower(FAT.Fold(ct))
	k = string.gsub(k, "[%-_]", " ")
	k = string.gsub(k, "%s%s+", " ")
	return FAT.Trim(k)
end

-- raison de refus d'un type de creature ("critter", "pet") ou nil (type normal ou inconnu)
function FAT.CreatureKind(ct)
	if type(ct) ~= "string" or ct == "" then
		return nil
	end
	return FAT.IGNORED_TYPES[FAT.TypeKey(ct)]
end

-- fonction globale facultative (ou nil)
local function Api(name)
	local f = getglobal(name)
	if type(f) == "function" then
		return f
	end
	return nil
end
FAT.Api = Api

-- appel protege d'une API a 1 ou 2 arguments ; nil en cas d'erreur / d'absence
local function Call1(name, a)
	local f = Api(name)
	if f then
		local ok, r = pcall(f, a)
		if ok then
			return r
		end
	end
	return nil
end
local function Call2(name, a, b)
	local f = Api(name)
	if f then
		local ok, r = pcall(f, a, b)
		if ok then
			return r
		end
	end
	return nil
end
FAT.Call1 = Call1
FAT.Call2 = Call2

function FAT.Round(x)
	return math.floor(x + 0.5)
end

-- ========= Minuteur d'un coup (pas d'OnUpdate permanent) =========
function FAT.DelayTick()
	local ST = FAT.ST
	local now = GetTime()
	local keep = {}
	local due = {}
	local i = 1
	while ST.delayItems[i] do
		local it = ST.delayItems[i]
		if it.at <= now then
			tinsert(due, it)
		else
			tinsert(keep, it)
		end
		i = i + 1
	end
	ST.delayItems = keep
	if not keep[1] and ST.delay then
		ST.delay:SetScript("OnUpdate", nil)
		ST.delay:Hide()
	end
	i = 1
	while due[i] do
		local ok, err = pcall(due[i].fn)
		if not ok then
			FAT.d(FAT.Tr("erreur minuteur : %s", tostring(err)))
		end
		i = i + 1
	end
end

function FAT.Delay(sec, fn)
	local ST = FAT.ST
	if not ST.delay then
		ST.delay = CreateFrame("Frame", "FredoATDelayFrame")
		ST.delay:Hide()
	end
	tinsert(ST.delayItems, { at = GetTime() + sec, fn = fn })
	ST.delay:SetScript("OnUpdate", FAT.DelayTick)
	ST.delay:Show()
end

-- ========= Entrees (liste de sorts) =========
-- retourne (entree, index) ou nil
function FAT.FindEntry(name)
	local DB = FAT.DB
	if not DB or not name then
		return nil
	end
	local n = FAT.Canon(name)
	if n == "" then
		return nil
	end
	local i = 1
	while i <= FAT.MAX_SLOTS do
		local e = DB.spells[i]
		if e and e.name and FAT.Canon(e.name) == n then
			return e, i
		end
		i = i + 1
	end
	return nil
end

function FAT.ValidMode(m)
	local i = 1
	while FAT.MODES[i] do
		if FAT.MODES[i] == m then
			return true
		end
		i = i + 1
	end
	return false
end

function FAT.ValidFallback(m)
	local i = 1
	while FAT.FALLBACKS[i] do
		if FAT.FALLBACKS[i] == m then
			return true
		end
		i = i + 1
	end
	return false
end

-- nombre d'entrees dans la liste
function FAT.CountEntries()
	local n = 0
	local i = 1
	while FAT.DB and i <= FAT.MAX_SLOTS do
		if FAT.DB.spells[i] then
			n = n + 1
		end
		i = i + 1
	end
	return n
end

-- ========= Unites : tests de base =========
function FAT.IsDead(unit)
	if not UnitExists(unit) then
		return false
	end
	if UnitIsDeadOrGhost(unit) then
		return true
	end
	local mx = UnitHealthMax(unit)
	if mx and mx > 0 and UnitHealth(unit) <= 0 then
		return true
	end
	return false
end

-- ennemi attaquable et vivant
function FAT.IsHostileUnit(unit)
	return UnitExists(unit) and UnitCanAttack("player", unit) and (not UnitIsFriend("player", unit))
		and (not FAT.IsDead(unit)) and true or false
end

function FAT.IsHostile()
	return FAT.IsHostileUnit("target")
end

-- identifiant stable : guid (SuperWoW) sinon nom + niveau
function FAT.TargetKey()
	if not UnitExists("target") then
		return nil
	end
	local _, guid = UnitExists("target")
	if guid then
		return guid
	end
	return tostring(UnitName("target")) .. ":" .. tostring(UnitLevel("target"))
end

-- signature plus fine (avec les PV) pour detecter qu'un cycle boucle
function FAT.TargetSig()
	if not UnitExists("target") then
		return nil
	end
	local _, guid = UnitExists("target")
	if guid then
		return guid
	end
	return tostring(UnitName("target")) .. ":" .. tostring(UnitLevel("target")) .. ":" .. tostring(UnitHealth("target"))
end

-- l'unite "unit" est-elle la cible de moi / mon familier / mon groupe ? (= cette cible menace le groupe)
function FAT.Threatens(unit)
	local t = unit .. "target"
	if not UnitExists(t) then
		return false
	end
	if UnitIsUnit(t, "player") then
		return true
	end
	if UnitExists("pet") and UnitIsUnit(t, "pet") then
		return true
	end
	if Call1("UnitPlayerOrPetInParty", t) then
		return true
	end
	local nr = Call1("GetNumRaidMembers", nil)
	if nr and nr > 0 and Call1("UnitPlayerOrPetInRaid", t) then
		return true
	end
	return false
end

-- ========= UnitXP / portee =========
-- UnitXP_SP3 est-il vraiment present ? (certains clients ont une UnitXP "experience" qui renvoie 0 pour tout)
function FAT.XPOK()
	local f = Api("UnitXP")
	if not f then
		return false
	end
	local ok, r = pcall(f, "version", "coffTimeDateStamp")
	if ok and type(r) == "number" and r > 0 then
		return true
	end
	return false
end

-- distance en metres via UnitXP ou nil
function FAT.XPDist(unit)
	if not FAT.XPOK() then
		return nil
	end
	local ok, r = pcall(getglobal("UnitXP"), "distanceBetween", "player", unit)
	if ok and type(r) == "number" then
		return r
	end
	return nil
end

-- 1 = a portee, 0 = hors portee, nil = indeterminable (IsSpellInRange vient de Nampower)
function FAT.SpellRange(spell, unit)
	if (not spell) or spell == "" then
		return nil
	end
	local f = Api("IsSpellInRange")
	if not f or (not UnitExists(unit)) then
		return nil
	end
	local ok, r = pcall(f, spell, unit)
	if not ok then
		return nil
	end
	if r == 1 or r == true then
		return 1
	elseif r == 0 or r == false then
		return 0
	end
	return nil
end

-- true / false, ou nil si CheckInteractDistance est absent ou plante
function FAT.Interact(unit, idx)
	local f = Api("CheckInteractDistance")
	if not f then
		return nil
	end
	local ok, r = pcall(f, unit, idx)
	if not ok then
		return nil
	end
	return r and true or false
end

-- le mob est-il dans la distance voulue ? d = metres (0 = portee du sort)
function FAT.InReach(unit, spell, d)
	d = tonumber(d) or 0
	local x = FAT.XPDist(unit)
	local sr = FAT.SpellRange(spell, unit)
	if x then
		if d > 0 then
			return x <= d
		end
		if sr ~= nil then
			return sr == 1
		end
		return x <= 28
	end
	-- sans UnitXP
	if d <= 0 then
		if sr ~= nil then
			return sr == 1
		end
		local r = FAT.Interact(unit, 4)
		return r ~= false -- indeterminable : on laisse passer
	end
	if d > 28 and sr == 1 then
		return true
	end
	local idx = 4
	if d <= 10 then
		idx = 3
	elseif d <= 11.5 then
		idx = 2
	end
	local r = FAT.Interact(unit, idx)
	if r == nil then
		return true
	end
	return r
end

-- ligne de vue : false si UnitXP dit "pas en vue"
function FAT.InSight(unit)
	if not FAT.XPOK() then
		return true
	end
	local ok, r = pcall(getglobal("UnitXP"), "inSight", "player", unit)
	if not ok then
		return true
	end
	if r == false or r == 0 then
		return false
	end
	return true
end

-- ========= Controle (poly, sap, gel, piege...) =========
FAT.ccCache = {}

function FAT.DebuffName(unit, i)
	if not FAT.scanTip then
		FAT.scanTip = CreateFrame("GameTooltip", "FredoATScanTip", nil, "GameTooltipTemplate")
	end
	local tip = FAT.scanTip
	tip:SetOwner(WorldFrame, "ANCHOR_NONE")
	tip:ClearLines()
	tip:SetUnitDebuff(unit, i)
	local fs = getglobal("FredoATScanTipTextLeft1")
	local t = fs and fs:GetText()
	tip:Hide()
	return t
end

local function Contains(list, s)
	local i = 1
	while list[i] do
		if string.find(s, list[i], 1, true) then
			return true
		end
		i = i + 1
	end
	return false
end

function FAT.TexIsCC(tex, unit, i)
	local low = string.lower(tostring(tex))
	local c = FAT.ccCache[low]
	if c ~= nil then
		return c
	end
	local res = Contains(FAT.CC_TEXTURES, low)
	if not res then
		local ok, nm = pcall(FAT.DebuffName, unit, i)
		if ok and nm then
			local f = string.lower(FAT.Fold(nm))
			-- noms courts ("sap", "peur") : mot entier ; les autres : sous-chaine
			res = (FAT.CCNameMatch(f))
		end
	end
	FAT.ccCache[low] = res and true or false
	return res and true or false
end

function FAT.CCNameMatch(f)
	local i = 1
	while FAT.CC_NAMES[i] do
		local n = FAT.CC_NAMES[i]
		if string.len(n) <= 4 then
			if f == n or string.find(f, "^" .. n .. "[^%a]") or string.find(f, "[^%a]" .. n .. "$") or string.find(f, "[^%a]" .. n .. "[^%a]") then
				return true
			end
		elseif string.find(f, n, 1, true) then
			return true
		end
		i = i + 1
	end
	return false
end

function FAT.IsControlled(unit)
	local f = Api("UnitDebuff")
	if not f then
		return false
	end
	local i = 1
	while i <= 16 do
		local ok, tex = pcall(f, unit, i)
		if (not ok) or (not tex) then
			break
		end
		if FAT.TexIsCC(tex, unit, i) then
			return true
		end
		i = i + 1
	end
	return false
end

-- ========= Filtres =========
-- filtres effectifs d'une entree : valeur du sort sinon valeur globale
function FAT.Filters(e)
	local S = FAT.S
	local F = {}
	local ef = e and e.f
	local i = 1
	while FAT.FILTER_KEYS[i] do
		local k = FAT.FILTER_KEYS[i]
		local v = ef and ef[k]
		if v == nil then
			v = S[k]
		end
		F[k] = v
		i = i + 1
	end
	F.pvp = (e and e.pvp) and true or false
	F.inCombat = UnitAffectingCombat("player") and true or false
	-- hors combat on ne cherche pas un mob au hasard, sauf option pull (et joueurs ennemis = choix volontaire)
	F.needCombat = (F.combat and (not F.pvp) and (not (F.pull and (not F.inCombat)))) and true or false
	return F
end

-- Un candidat est-il valide ? retourne ok, raison
-- ctx.skipCombat : ne pas exiger le combat (cible d'un tank)
function FAT.Eval(unit, F, spell, ctx)
	if not UnitExists(unit) then
		return false, "none"
	end
	if FAT.IsDead(unit) then
		return false, "dead"
	end
	if (not UnitCanAttack("player", unit)) or UnitIsFriend("player", unit) then
		return false, "friend"
	end
	local isPlayer = UnitIsPlayer(unit) and true or false
	if F.pvp and (not isPlayer) then
		return false, "notplayer"
	end
	if F.pets and (not isPlayer) then
		local kind = FAT.CreatureKind(Call1("UnitCreatureType", unit))
		if kind then
			return false, kind
		end
		if Call1("UnitIsCivilian", unit) then
			return false, "civil"
		end
		if Call1("UnitPlayerControlled", unit) then
			return false, "pet"
		end
	end
	if isPlayer and F.pvpsafe and (not F.pvp) and (not Call1("UnitIsPVP", "player")) then
		return false, "pvp"
	end
	if F.cc and FAT.IsControlled(unit) then
		return false, "cc"
	end
	local skipCombat = ctx and ctx.skipCombat
	if F.tapped and (not isPlayer) and (not skipCombat) then
		if Call1("UnitIsTapped", unit) and (not Call1("UnitIsTappedByPlayer", unit)) and (not FAT.Threatens(unit)) then
			return false, "tapped"
		end
	end
	if F.needCombat and (not skipCombat) then
		if (not UnitAffectingCombat(unit)) and (not FAT.Threatens(unit)) then
			return false, "combat"
		end
	end
	if not FAT.InReach(unit, spell, F.dist) then
		return false, "far"
	end
	-- mode "a portee" : la cible doit etre a portee DU SORT (pas seulement dans la distance maximale reglee,
	-- sinon un sort de melee choisit un mob a 30 m). Si la portee du sort est inconnue, on garde la distance.
	if F.mode == "range" and FAT.SpellRange(spell, unit) == 0 then
		return false, "far"
	end
	if F.los and (not FAT.InSight(unit)) then
		return false, "los"
	end
	return true, "ok"
end

-- ========= Marqueurs / lanceurs / score =========
-- rang du marqueur dans l'ordre configure (1 = prioritaire) ou nil
function FAT.MarkRank(unit)
	local m = Call1("GetRaidTargetIndex", unit)
	if not m then
		return nil
	end
	local order = FAT.S.marks
	local i = 1
	while order[i] do
		if order[i] == m then
			return i
		end
		i = i + 1
	end
	return nil
end

function FAT.IsCaster(unit)
	local nm = UnitName(unit)
	if nm then
		local t = FAT.ST.casters[FAT.Norm(nm)]
		if t and (GetTime() - t) < 3.5 then
			return true
		end
	end
	return false
end

function FAT.HealthPct(unit)
	local mx = UnitHealthMax(unit)
	if not mx or mx <= 0 then
		return 100
	end
	return (UnitHealth(unit) * 100) / mx
end

-- plus grand = meilleur ; a egalite le plus proche (premier) gagne
function FAT.Score(kind, unit)
	if kind == "mark" then
		local r = FAT.MarkRank(unit)
		if r then
			return 1000 - (r * 10)
		end
		return 0
	elseif kind == "weak" then
		return 100 - FAT.HealthPct(unit)
	elseif kind == "caster" then
		if FAT.IsCaster(unit) then
			return 100
		end
		local mx = UnitManaMax(unit)
		if mx and mx > 0 and UnitPowerType(unit) == 0 then
			return 10
		end
		return 0
	end
	return 0
end

-- ========= Sauvegarde / restauration de la cible =========
function FAT.Snapshot()
	if not UnitExists("target") then
		return nil
	end
	local _, guid = UnitExists("target")
	return { guid = guid, name = UnitName("target"), level = UnitLevel("target") }
end

function FAT.SameTarget(s)
	if not s then
		return not UnitExists("target")
	end
	if not UnitExists("target") then
		return false
	end
	local _, guid = UnitExists("target")
	if s.guid and guid then
		return s.guid == guid
	end
	return UnitName("target") == s.name and UnitLevel("target") == s.level
end

-- remet la cible d'avant (sans cible -> ClearTarget). Verifie chaque essai.
function FAT.Restore(s)
	if FAT.SameTarget(s) then
		return true
	end
	if not s then
		pcall(ClearTarget)
		return true
	end
	if s.guid then
		pcall(TargetUnit, s.guid)
		if FAT.SameTarget(s) then
			return true
		end
	end
	local tl = Api("TargetLastTarget")
	if tl then
		pcall(tl)
		if FAT.SameTarget(s) then
			return true
		end
	end
	local tb = Api("TargetByName")
	if tb and s.name then
		pcall(tb, s.name, true)
		if FAT.SameTarget(s) then
			return true
		end
	end
	return false
end

-- ========= Acquisition =========
-- Parcourt jusqu'a S.scan candidats dans l'ordre de proximite. kind :
-- "nearest" (premier valide) ou "mark" / "weak" / "caster" (meilleur score).
-- Retourne true si la cible actuelle est un candidat valide ; sinon la cible d'avant est restauree.
function FAT.Acquire(kind, F, spell, ctx)
	local S = FAT.S
	local max = tonumber(S.scan) or 8
	if F.pvp and max < 16 then
		max = 16 -- les joueurs sont souvent au milieu des PNJ
	end
	if max < 1 then max = 1 end
	if max > 16 then max = 16 end
	local prev = FAT.Snapshot()
	local okClear, errClear = pcall(ClearTarget) -- sans ca l'API continue apres la cible actuelle au lieu de repartir du plus proche
	if not okClear then
		FAT.d(FAT.Tr("erreur ClearTarget : %s", tostring(errClear)))
	end
	local sigs = {}
	local seen = {}
	local reasons = {}
	local scanned = 0
	local found = false
	local best, bestScore, bestKey, bestGuid = nil, nil, nil, nil
	local atIdx = nil -- rang du candidat actuellement cible (nil = inconnu)
	local i = 1
	local tne = Api("TargetNearestEnemy")
	local tnp = F.pvp and Api("TargetNearestEnemyPlayer") or nil
	while i <= max and tne do
		atIdx = nil
		local okc, errc
		if tnp then
			okc, errc = pcall(tnp)
		else
			okc, errc = pcall(tne)
		end
		if not okc then
			FAT.d(FAT.Tr("erreur TargetNearestEnemy : %s", tostring(errc)))
			break
		end
		if not UnitExists("target") then
			break
		end
		local _, guid = UnitExists("target")
		local sig = FAT.TargetSig()
		if guid and seen[guid] then
			break -- le cycle a boucle
		end
		if guid then
			seen[guid] = true
		end
		sigs[i] = sig
		if (not guid) and FAT.PeriodRepeats(sigs, i) then
			break
		end
		scanned = i
		atIdx = i
		local ok, why = FAT.Eval("target", F, spell, ctx)
		if ctx and ctx.trace then
			tinsert(ctx.trace, { idx = i, name = UnitName("target"), ok = ok, why = why, dist = FAT.XPDist("target") })
		end
		if ok then
			if kind == "nearest" then
				found = true
				break
			end
			local sc = FAT.Score(kind, "target")
			if (best == nil) or sc > bestScore then
				best, bestScore, bestKey, bestGuid = i, sc, FAT.TargetKey(), guid
			end
		else
			reasons[why] = (reasons[why] or 0) + 1
		end
		i = i + 1
	end
	if (not found) and best then
		-- recible le meilleur : meme guid, sinon on rejoue le cycle jusqu'a son rang.
		-- On compare le RANG, pas le nom : sans guid, trois loups identiques ont la meme cle
		-- et on resterait sur le dernier examine (peut-etre loin / hors combat).
		if atIdx == best then
			found = UnitExists("target") and true or false
		else
			if bestGuid then
				pcall(TargetUnit, bestGuid)
			end
			local again = (bestGuid ~= nil) and (FAT.TargetKey() == bestKey)
			if not again then
				pcall(ClearTarget)
				local k = 1
				while k <= best and tne do
					if tnp then pcall(tnp) else pcall(tne) end
					k = k + 1
				end
			end
			if UnitExists("target") and FAT.TargetKey() == bestKey and FAT.Eval("target", F, spell, nil) then
				found = true
			end
		end
	end
	if found then
		return true, "ok", scanned
	end
	if not FAT.Restore(prev) then
		-- impossible de retrouver la cible d'avant : ne pas laisser un candidat REFUSE (loin, hors combat...) cible
		pcall(ClearTarget)
	end
	-- raison principale : la plus frequente
	local topWhy, topN = "none", 0
	local k, v
	for k, v in pairs(reasons) do
		if v > topN then
			topWhy, topN = k, v
		end
	end
	return false, topWhy, scanned
end

-- le motif des signatures se repete-t-il (cycle sans guid) ? periode >= 2 seulement :
-- trois loups identiques a la suite ne sont pas un cycle.
function FAT.PeriodRepeats(sigs, n)
	local p = 2
	while p * 2 <= n do
		local same = true
		local varied = false
		local j = 0
		while j < p do
			if sigs[n - j] ~= sigs[n - p - j] then
				same = false
				break
			end
			if sigs[n - j] ~= sigs[n] then
				varied = true
			end
			j = j + 1
		end
		if same and varied then
			return true
		end
		p = p + 1
	end
	return false
end

-- ========= Modes =========
-- cible actuelle utilisable (ennemie, vivante, joueur si "joueurs seulement")
function FAT.CurrentOK(F)
	if not FAT.IsHostile() then
		return false
	end
	if F.pvp and (not UnitIsPlayer("target")) then
		return false
	end
	return true
end

-- sources d'assistance : joueur nomme, chef de groupe/raid, assistants
function FAT.AssistSources()
	local list = {}
	local n = 0
	local function add(u)
		if u and UnitExists(u) and (not UnitIsUnit(u, "player")) then
			local i = 1
			while i <= n do
				if UnitIsUnit(list[i], u) then
					return
				end
				i = i + 1
			end
			n = n + 1
			list[n] = u
		end
	end
	local want = FAT.Trim(FAT.S.assist)
	local nr = Call1("GetNumRaidMembers", nil) or 0
	local np = Call1("GetNumPartyMembers", nil) or 0
	if want ~= "" then
		if string.find(want, "^party%d$") or string.find(want, "^raid%d+$") then
			add(want)
		else
			local lw = string.lower(want)
			local i = 1
			while i <= nr do
				local u = "raid" .. i
				if UnitName(u) and string.lower(UnitName(u)) == lw then add(u) end
				i = i + 1
			end
			i = 1
			while i <= np do
				local u = "party" .. i
				if UnitName(u) and string.lower(UnitName(u)) == lw then add(u) end
				i = i + 1
			end
		end
	end
	if nr > 0 then
		local rr = Api("GetRaidRosterInfo")
		if rr then
			local rank2, rank1 = {}, {}
			local i = 1
			while i <= nr do
				local ok, nm, rank = pcall(rr, i)
				if ok and nm then
					if rank == 2 then tinsert(rank2, "raid" .. i) elseif rank == 1 then tinsert(rank1, "raid" .. i) end
				end
				i = i + 1
			end
			i = 1
			while rank2[i] do add(rank2[i]); i = i + 1 end
			i = 1
			while rank1[i] do add(rank1[i]); i = i + 1 end
		end
	elseif np > 0 then
		local li = Call1("GetPartyLeaderIndex", nil)
		if li and li > 0 then
			add("party" .. li)
		end
	end
	return list, n
end

function FAT.ModeAssist(e, spell, F, ctx)
	local list, n = FAT.AssistSources()
	if n == 0 then
		return false, "none"
	end
	local ctx2 = { skipCombat = true, trace = ctx and ctx.trace }
	local au = Api("AssistUnit")
	if not au then
		return false, "none"
	end
	local lastWhy = "none"
	local prev = FAT.Snapshot()
	local i = 1
	while i <= n do
		local u = list[i]
		local t = u .. "target"
		if UnitExists(t) and FAT.IsHostileUnit(t) then
			pcall(au, u)
			local ok, why = FAT.Eval("target", F, spell, ctx2)
			if ctx and ctx.trace then
				tinsert(ctx.trace, { idx = i, name = UnitName("target"), ok = ok, why = why, src = UnitName(u) })
			end
			if ok then
				return true, "ok"
			end
			lastWhy = why
			FAT.Restore(prev)
		end
		i = i + 1
	end
	return false, lastWhy
end

-- allies a soigner
function FAT.HealUnits()
	local list = {}
	local n = 0
	local S = FAT.S
	local function add(u)
		if UnitExists(u) then
			n = n + 1
			list[n] = u
		end
	end
	add("player")
	local nr = Call1("GetNumRaidMembers", nil) or 0
	if nr > 0 then
		local i = 1
		while i <= nr do
			local u = "raid" .. i
			if UnitExists(u) and (not UnitIsUnit(u, "player")) then add(u) end
			if S.healPets then
				local pu = "raidpet" .. i
				if UnitExists(pu) and (not UnitIsUnit(pu, "pet")) then add(pu) end
			end
			i = i + 1
		end
	else
		local np = Call1("GetNumPartyMembers", nil) or 0
		local i = 1
		while i <= np do
			add("party" .. i)
			if S.healPets then add("partypet" .. i) end
			i = i + 1
		end
	end
	if S.healPets then add("pet") end
	return list, n
end

function FAT.ModeHeal(e, spell, F, ctx)
	local S = FAT.S
	local list, n = FAT.HealUnits()
	local best, bestKey = nil, nil
	local i = 1
	while i <= n do
		local u = list[i]
		local ok = true
		local why = nil
		if FAT.IsDead(u) or (not UnitIsFriend("player", u)) or UnitCanAttack("player", u) then
			ok = false; why = "dead"
		elseif UnitIsConnected and (not UnitIsConnected(u)) then
			ok = false; why = "dead"
		end
		local pct = 100
		local key = 0
		if ok then
			pct = FAT.HealthPct(u)
			if pct >= (tonumber(S.healMin) or 100) then
				ok = false; why = "nochange"
			end
		end
		if ok then
			local x = FAT.XPDist(u)
			local sr = FAT.SpellRange(spell, u)
			local known = true
			if sr ~= nil then
				if sr ~= 1 then ok = false; why = "far" end
			elseif x then
				if x > 40 then ok = false; why = "far" end
			else
				local r = FAT.Interact(u, 4)
				if r == nil then
					known = false
				elseif r == false then
					known = false
					if Call1("UnitIsVisible", u) == nil and Api("UnitIsVisible") then ok = false; why = "far" end
				end
			end
			if ok then
				key = pct + (known and 0 or 150)
			end
		end
		if ctx and ctx.trace then
			tinsert(ctx.trace, { idx = i, name = UnitName(u), ok = ok, why = why or "ok", unit = u })
		end
		if ok and ((best == nil) or key < bestKey) then
			best, bestKey = u, key
		end
		i = i + 1
	end
	if not best then
		return false, "nochange"
	end
	if UnitExists("target") and UnitIsUnit("target", best) then
		return true, "ok"
	end
	pcall(TargetUnit, best)
	if UnitExists("target") and UnitIsUnit("target", best) then
		return true, "ok"
	end
	return false, "none"
end

-- un mode (sans repli). Retourne ok, raison
function FAT.RunMode(mode, e, spell, F, ctx)
	local S = FAT.S
	local ST = FAT.ST
	F.mode = mode -- le mode reellement execute (le repli "plus proche" ne doit pas exiger la portee du sort)
	if mode == "none" then
		return true, "nochange"
	elseif mode == "heal" then
		return FAT.ModeHeal(e, spell, F, ctx)
	elseif mode == "assist" then
		return FAT.ModeAssist(e, spell, F, ctx)
	end
	local cur = FAT.CurrentOK(F)
	local now = GetTime()
	if mode == "keep" then
		if cur then
			return true, "ok"
		end
	elseif mode == "range" then
		if cur and FAT.SpellRange(spell, "target") ~= 0 then
			return true, "ok"
		end
	elseif mode == "nearest" or mode == "mark" or mode == "weak" or mode == "caster" then
-- une rotation qui rappelle le sort a chaque image ne doit pas relancer un balayage complet a chaque fois
if cur and (not e.force) and (now - ST.lastAcquire) < (tonumber(S.minInterval) or 0.25) then
return true, "ok"
end
end
local kind = "nearest"
	if mode == "mark" or mode == "weak" or mode == "caster" then
		kind = mode
	end
	ST.lastAcquire = now
	local ok, why = FAT.Acquire(kind, F, spell, ctx)
	return ok, why
end

-- Prepare la cible pour une entree. Retourne ok, raison, mode utilise.
function FAT.Prepare(e, spell, trace)
	local S = FAT.S
	local F = FAT.Filters(e)
	local ctx = { trace = trace }
	local mode = e.mode
	local ok, why = FAT.RunMode(mode, e, spell, F, ctx)
	local used = mode
	if (not ok) and (mode == "assist" or mode == "mark" or mode == "weak" or mode == "caster") then
		local fb = e.fb or S.fallback
		if fb and fb ~= "" and fb ~= mode and FAT.ValidFallback(fb) then
			local ok2, why2 = FAT.RunMode(fb, e, spell, F, ctx)
			if ok2 then
				ok, why, used = true, "ok", fb
			end
		end
	end
	return ok, why, used
end

-- ========= Incantation / auto-attaque =========
function FAT.IsCasting()
	return GetTime() < (FAT.ST.castEnd or 0)
end

-- changed = la cible a change pendant Prepare : l'auto-attaque en cours
-- vise l'ancienne cible et LEAVE_COMBAT n'est pas encore arrive, donc
-- on relance l'attaque sur la nouvelle.
function FAT.StartAttack(e, changed)
	if e.attack and e.mode ~= "heal" and FAT.IsHostile() and (changed or (not FAT.ST.attacking)) then
		FAT.d(FAT.Tr("auto-attaque"))
		if Api("AttackTarget") then
			AttackTarget()
		end
	end
end

function FAT.SetLast(spell, mode, ok, why)
	local ST = FAT.ST
	ST.last = { spell = spell, mode = mode, ok = ok, why = why, name = UnitExists("target") and UnitName("target") or nil }
	if FAT.RefreshIndicator then
		FAT.RefreshIndicator()
	end
end

-- Sequence complete : cible -> sort -> auto-attaque. castFn lance le
-- vrai sort (fonction d'origine, jamais nos hooks). ST.busy reste
-- vrai pendant tout ce temps : un macro ou une barre qui rappelle un
-- sort de la liste pendant ce delai passe tel quel, sans boucle.
function FAT.Engage(e, spell, castFn)
	local ST = FAT.ST
	local S = FAT.S
	if ST.busy or (not S.enabled) then
		castFn()
		return
	end
	ST.busy = true
	local before = FAT.TargetKey()
	local snap = FAT.Snapshot()
	local ok, why, used = true, "ok", e.mode
	if FAT.IsCasting() then
		-- changer de cible pendant une incantation risque de la casser
		why = "incant"
		FAT.d(FAT.Tr("incantation en cours : cible inchangee"))
	else
		local okp, a, b, c = pcall(FAT.Prepare, e, spell)
		if okp then
			ok, why, used = a, b, c
		else
			FAT.d(FAT.Tr("erreur ciblage : %s", tostring(a)))
			ok, why = false, "erreur"
		end
	end
	ST.lastEntry = e
	ST.lastEntryAt = GetTime()
	local changed = (FAT.TargetKey() ~= before)
	FAT.SetLast(spell, used or e.mode, ok, why)
	if not ok then
		FAT.d(FAT.Tr("pas de cible pour %s : %s", tostring(spell), tostring(FAT.REASON[why] or why)))
	end
	if e.pvp and (not (FAT.IsHostile() and UnitIsPlayer("target"))) then
		FAT.d(FAT.Tr("joueurs seulement : aucun joueur ennemi, sort non lance"))
		FAT.SetLast(spell, used or e.mode, false, "pvponly")
		ST.busy = false
		return
	end
	local ok2, err2 = pcall(castFn)
	if not ok2 then
		ST.busy = false
		error(err2, 0)
	end
	local ok3, err3 = pcall(FAT.StartAttack, e, changed)
	if not ok3 then
		FAT.d(FAT.Tr("erreur auto-attaque : %s", tostring(err3)))
	end
	if used == "heal" and S.healRestore and snap and changed then
		ST.restoreSnap = snap
		ST.restoreAt = GetTime()
		FAT.Delay(0.5, FAT.DoRestoreHeal)
	end
	ST.busy = false
end

-- Soigner : retour a la cible d'avant une fois le sort fini
function FAT.DoRestoreHeal()
	local ST = FAT.ST
	local s = ST.restoreSnap
	if not s then
		return
	end
	if (GetTime() - (ST.restoreAt or 0)) > 8 then
		ST.restoreSnap = nil
		ST.restorePending = false
		return
	end
	if FAT.IsCasting() then
		ST.restorePending = true
		return
	end
	ST.restorePending = false
	ST.restoreSnap = nil
	FAT.Restore(s)
end

-- ========= Nom du sort d'une case de barre d'action =========
function FAT.ActionSpellName(slot)
	if not FAT.scanTip then
		FAT.scanTip = CreateFrame("GameTooltip", "FredoATScanTip", nil, "GameTooltipTemplate")
	end
	local tip = FAT.scanTip
	tip:SetOwner(WorldFrame, "ANCHOR_NONE")
	tip:ClearLines()
	tip:SetAction(slot)
	local fs = getglobal("FredoATScanTipTextLeft1")
	local t = fs and fs:GetText()
	tip:Hide()
	return t
end

-- ========= Hooks : barre d'action, macros, livre de sorts =========
-- e.via : "both" (clic + touche), "click" (clic seulement), "key" (touche seulement)
function FAT.ViaOK(e, isKey)
	local v = e.via
	if v == "click" then
		return not isKey
	elseif v == "key" then
		return isKey and true or false
	end
	return true
end

-- Cherche l'entree d'un appel intercepte. Retourne entree, nom ou nil. Ne leve jamais d'erreur.
function FAT.Lookup(name)
	local ok, e = pcall(FAT.FindEntry, name)
	if ok then
		return e
	end
	return nil
end

function FAT.NoteCast(name)
	if name and name ~= "" then
		FAT.ST.lastCast = FAT.BaseName(name)
	end
end

function FAT.InstallHooks()
	local orig = FAT.orig
	orig.CastSpellByName = CastSpellByName
	orig.CastSpell = CastSpell
	orig.UseAction = UseAction

	-- macros (/cast), CastSpellByName direct, autres addons
	CastSpellByName = function(name, onSelf)
		if FAT.S.enabled and (not FAT.ST.busy) and name and (not onSelf) then
			FAT.NoteCast(name)
			local e = FAT.Lookup(name)
			if e then
				FAT.Engage(e, name, function() orig.CastSpellByName(name, onSelf) end)
				return
			end
		end
		return orig.CastSpellByName(name, onSelf)
	end

	-- clic dans le livre de sorts
	CastSpell = function(index, book)
		if FAT.S.enabled and (not FAT.ST.busy) and index and book ~= "pet" then
			local okn, n = pcall(GetSpellName, index, book)
			if okn and n then
				FAT.NoteCast(n)
				local e = FAT.Lookup(n)
				if e and FAT.ViaOK(e, false) then
					FAT.Engage(e, n, function() orig.CastSpell(index, book) end)
					return
				end
			end
		end
		return orig.CastSpell(index, book)
	end

	-- barres d'action (touches ou clics). Les macros (GetActionText) et
	-- les objets passent tels quels : un /cast de macro repasse par
	-- CastSpellByName ci-dessus.
	UseAction = function(slot, checkCursor, onSelf)
		if FAT.S.enabled and (not FAT.ST.busy) and slot and (not onSelf) then
			local okh, handled = pcall(FAT.UseActionIntercept, slot, checkCursor, onSelf)
			if okh and handled then
				return
			end
		end
		return orig.UseAction(slot, checkCursor, onSelf)
	end

	-- Touches des barres d'action par defaut : ActionButtonDown appelle
	-- UseAction ; on marque l'appel "touche" pour le distinguer du clic
	-- (les barres d'autres addons qui n'utilisent pas ActionButtonDown
	-- comptent comme "clic").
	if Api("ActionButtonDown") then
		orig.ActionButtonDown = ActionButtonDown
		ActionButtonDown = function(id)
			FAT.ST.keyDown = true
			local ok, err = pcall(orig.ActionButtonDown, id)
			FAT.ST.keyDown = false
			if not ok then
				error(err, 0)
			end
		end
	end
	-- selon les versions du client, c est ActionButtonUp qui appelle UseAction : meme marquage
	if Api("ActionButtonUp") then
		orig.ActionButtonUp = ActionButtonUp
		ActionButtonUp = function(id, onSelf)
			FAT.ST.keyDown = true
			local ok, err = pcall(orig.ActionButtonUp, id, onSelf)
			FAT.ST.keyDown = false
			if not ok then
				error(err, 0)
			end
		end
	end
end

-- vrai si l'appel a ete pris en charge (sort lance par nous)
function FAT.UseActionIntercept(slot, checkCursor, onSelf)
	if (not HasAction(slot)) or GetActionText(slot) then
		return false
	end
	if (CursorHasSpell and CursorHasSpell()) or (CursorHasItem and CursorHasItem()) then
		return false
	end
	local n = FAT.ActionSpellName(slot)
	if not n then
		return false
	end
	FAT.NoteCast(n)
	local e = FAT.Lookup(n)
	if e and FAT.ViaOK(e, FAT.ST.keyDown) then
		FAT.Engage(e, n, function() FAT.orig.UseAction(slot, checkCursor, onSelf) end)
		return true
	end
	return false
end

-- ========= API publique (touches, macros) =========
-- Sort pret : hors recharge (le GCD de 1.5 s compte comme pret) et a portee.
function FAT.SpellReady(name, mode)
	name = FAT.ClientName(name)
	local n = FAT.Canon(name)
	local found = nil
	local i = 1
	while true do
		local sn = GetSpellName(i, "spell")
		if not sn then
			break
		end
		if FAT.Canon(sn) == n then
			found = i -- on garde le dernier = rang le plus eleve
		end
		i = i + 1
	end
	if not found then
		return false
	end
	local start, dur = GetSpellCooldown(found, "spell")
	if start and start > 0 and dur and dur > 1.5 then
		return false
	end
	if mode ~= "heal" and FAT.SpellRange(name, "target") == 0 then
		return false
	end
	return true
end

-- Sorts (entrees) rattaches a la touche n, dans l'ordre de la liste.
function FAT.GroupEntries(n)
	local list = {}
	local c = 0
	local i = 1
	while i <= FAT.MAX_SLOTS do
		local e = FAT.DB and FAT.DB.spells[i]
		if e and e.key == n then
			c = c + 1
			list[c] = e
		end
		i = i + 1
	end
	return list, c
end

-- Touche liee a l'emplacement n (Raccourcis > FREDOAUTOTARGET)
function FredoAutoTarget_UseSlot(n)
	if not FAT.DB then
		return
	end
	local list, c = FAT.GroupEntries(n)
	if c == 0 then
		FAT.p(FAT.Tr("Touche %s : aucun sort rattache. Ajoute un sort dans le panneau (/fat).", tostring(n)))
		return
	end
	local e = list[1]
	if c > 1 then
		-- priorite : le premier sort de la liste qui est pret
		local k = 1
		while k <= c do
			if FAT.SpellReady(list[k].name, list[k].mode) then
				e = list[k]
				break
			end
			k = k + 1
		end
	end
	local name = FAT.ClientName(e.name)
	FAT.NoteCast(name)
	FAT.Engage(e, name, function() FAT.orig.CastSpellByName(name) end)
end

-- Macro : /script FredoAutoTarget_Cast("Charge")  (ou  /fat cast Charge)
-- Si le sort est dans la liste, ses reglages sont utilises ; sinon
-- reglages par defaut (A portee + auto-attaque).
function FredoAutoTarget_Cast(spellName)
	spellName = FAT.Trim(spellName)
	if spellName == "" then
		return
	end
	FAT.NoteCast(spellName)
	local e = FAT.FindEntry(spellName)
	if not e then
		e = { name = spellName, mode = "range", attack = true, pvp = false }
	end
	spellName = FAT.ClientName(spellName)
	FAT.Engage(e, spellName, function() FAT.orig.CastSpellByName(spellName) end)
end

function FredoAutoTarget_Toggle()
	FAT.S.enabled = not FAT.S.enabled
	FAT.p(FAT.S.enabled and FAT.Tr("Auto-cible ACTIVEE") or FAT.Tr("Auto-cible DESACTIVEE"))
	if FAT.RefreshPanel then
		FAT.RefreshPanel()
	end
	if FAT.RefreshIndicator then
		FAT.RefreshIndicator()
	end
end

-- ========= Selections directes (raccourcis) =========
-- Choisit une cible avec les filtres globaux, sans lancer de sort.
-- mode : "nearest" "mark" "weak" "caster" "assist" "heal" "player"
function FredoAutoTarget_Select(mode, trace)
	if not FAT.DB then
		return false
	end
	local e = { name = "", mode = mode, attack = false, pvp = false, force = true } -- force : choix explicite, jamais limite par l'intervalle
	if mode == "player" then
		e.mode = "nearest"
		e.pvp = true
	end
	local ST = FAT.ST
	if ST.busy then
		return false
	end
	if FAT.IsCasting() then
		FAT.d(FAT.Tr("incantation en cours : selection ignoree"))
		return false
	end
	ST.busy = true
	local ok, a, b, c = pcall(FAT.Prepare, e, nil, trace)
	ST.busy = false
	if not ok then
		FAT.d(FAT.Tr("erreur selection : %s", tostring(a)))
		return false
	end
	FAT.SetLast("(" .. (FAT.MODE_LABEL[mode] or tostring(mode)) .. ")", c or mode, a, b)
	return a
end

-- Cible suivante / precedente PARMI les ennemis valides (filtres globaux)
function FredoAutoTarget_Cycle(reverse)
	if not FAT.DB or FAT.ST.busy or FAT.IsCasting() then
		return false
	end
	local ST = FAT.ST
	ST.busy = true
	local ok, res = pcall(FAT.CycleNext, reverse)
	ST.busy = false
	if not ok then
		FAT.d(FAT.Tr("erreur cycle : %s", tostring(res)))
		return false
	end
	return res
end

function FAT.CycleNext(reverse)
	local tne = Api("TargetNearestEnemy")
	if not tne then
		return false
	end
	local F = FAT.Filters(nil)
	local prev = FAT.Snapshot()
	local startKey = FAT.TargetKey()
	local max = tonumber(FAT.S.scan) or 8
	local sigs = {}
	local seen = {}
	local i = 1
	while i <= max do
		if reverse then
			pcall(tne, true)
		else
			pcall(tne)
		end
		if not UnitExists("target") then
			break
		end
		local _, guid = UnitExists("target")
		if guid and seen[guid] then
			break
		end
		if guid then seen[guid] = true end
		sigs[i] = FAT.TargetSig()
		if (not guid) and FAT.PeriodRepeats(sigs, i) then
			break
		end
		local key = FAT.TargetKey()
		if key ~= startKey then
			local ok = FAT.Eval("target", F, nil, nil)
			if ok then
				FAT.SetLast(FAT.Tr("(cible suivante)"), "nearest", true, "ok")
				return true
			end
		end
		i = i + 1
	end
	FAT.Restore(prev)
	FAT.SetLast(FAT.Tr("(cible suivante)"), "nearest", false, "none")
	return false
end

function FredoAutoTarget_ClearTarget()
	pcall(ClearTarget)
end

-- ========= Re-ciblage quand la cible meurt =========
function FAT.OnDeath(msg)
	local S = FAT.S
	local ST = FAT.ST
	if (not S.retarget) or (not S.enabled) or (not ST.lastEntry) then
		return
	end
	if (GetTime() - (ST.lastEntryAt or 0)) > 10 then
		return
	end
	if not UnitExists("target") then
		return
	end
	local nm = UnitName("target")
	if (not nm) or (not msg) or (not string.find(msg, nm, 1, true)) then
		return
	end
	FAT.Delay(0.2, FAT.DoRetarget)
end

function FAT.DoRetarget()
	local S = FAT.S
	local ST = FAT.ST
	if (not S.retarget) or (not S.enabled) or ST.busy then
		return
	end
	if not UnitAffectingCombat("player") then
		return
	end
	if FAT.IsCasting() then
		ST.retargetPending = true
		return
	end
	ST.retargetPending = false
	local now = GetTime()
	if (now - ST.retargetAt) < (tonumber(S.retargetGap) or 0.5) then
		return
	end
	if not (UnitExists("target") and FAT.IsDead("target")) then
		return -- tu as deja une autre cible, ou plus de cible
	end
	local e0 = ST.lastEntry
	if not e0 then
		return
	end
	local mode = e0.mode
	if mode == "heal" or mode == "none" or mode == "keep" or mode == "range" then
		mode = "nearest"
	end
	local e = { name = e0.name, mode = mode, fb = e0.fb, attack = e0.attack, pvp = e0.pvp, f = e0.f, via = e0.via }
	ST.retargetAt = now
	ST.busy = true
	local before = FAT.TargetKey()
	local ok, a, b, c = pcall(FAT.Prepare, e, FAT.ClientName(e0.name))
	ST.busy = false
	if not ok then
		FAT.d(FAT.Tr("erreur re-ciblage : %s", tostring(a)))
		return
	end
	FAT.SetLast(tostring(e0.name), c or mode, a, b)
	if a then
		FAT.d(FAT.Tr("re-ciblage automatique"))
		pcall(FAT.StartAttack, e, FAT.TargetKey() ~= before)
	end
end

-- ========= Evenements =========
-- motif "X commence a lancer Y" a partir des chaines globales du client
function FAT.CastPatterns()
	if FAT.castPats then
		return FAT.castPats
	end
	local pats = {}
	local g = getglobal("SPELLCASTOTHERSTART")
	if type(g) == "string" then
		local p = string.gsub(g, "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
		p = string.gsub(p, "%%%%s", "(.+)")
		p = string.gsub(p, "%%%%%d%%%$s", "(.+)")
		tinsert(pats, "^" .. p)
	end
	tinsert(pats, "^(.+) begins to cast ")
	tinsert(pats, "^(.+) commence .+ lancer ")
	FAT.castPats = pats
	return pats
end

function FAT.OnCreatureCast(msg)
	if not msg then
		return
	end
	local pats = FAT.CastPatterns()
	local i = 1
	while pats[i] do
		local _, _, who = string.find(msg, pats[i])
		if who then
			FAT.ST.casters[FAT.Norm(who)] = GetTime()
			return
		end
		i = i + 1
	end
end

FAT.CASTER_EVENTS = {
	"CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE", "CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE",
	"CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE", "CHAT_MSG_SPELL_CREATURE_VS_SELF_BUFF",
	"CHAT_MSG_SPELL_CREATURE_VS_PARTY_BUFF",
}

-- n'ecoute le journal de combat que si un sort utilise le mode "Lanceur"
function FAT.SyncEvents()
	local f = FAT.frame
	if not f then
		return
	end
	local need = false
	local S = FAT.S
	if S.fallback == "caster" then
		need = true
	end
	local i = 1
	while FAT.DB and i <= FAT.MAX_SLOTS do
		local e = FAT.DB.spells[i]
		if e and (e.mode == "caster" or e.fb == "caster") then
			need = true
		end
		i = i + 1
	end
	i = 1
	while FAT.CASTER_EVENTS[i] do
		if need then
			f:RegisterEvent(FAT.CASTER_EVENTS[i])
		else
			f:UnregisterEvent(FAT.CASTER_EVENTS[i])
		end
		i = i + 1
	end
	FAT.castWatch = need
end

FAT.frame = CreateFrame("Frame", "FredoAutoTargetFrame")
FAT.frame:RegisterEvent("VARIABLES_LOADED")
FAT.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
FAT.frame:RegisterEvent("PLAYER_ENTER_COMBAT")
FAT.frame:RegisterEvent("PLAYER_LEAVE_COMBAT")
FAT.frame:RegisterEvent("SPELLCAST_START")
FAT.frame:RegisterEvent("SPELLCAST_STOP")
FAT.frame:RegisterEvent("SPELLCAST_FAILED")
FAT.frame:RegisterEvent("SPELLCAST_INTERRUPTED")
FAT.frame:RegisterEvent("SPELLCAST_DELAYED")
FAT.frame:RegisterEvent("SPELLCAST_CHANNEL_START")
FAT.frame:RegisterEvent("SPELLCAST_CHANNEL_STOP")
FAT.frame:RegisterEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH")
FAT.frame:RegisterEvent("CHARACTER_POINTS_CHANGED")

function FAT.OnEvent(ev, a1, a2)
	local ST = FAT.ST
	if ev == "PLAYER_ENTER_COMBAT" then
		ST.attacking = true
	elseif ev == "PLAYER_LEAVE_COMBAT" then
		ST.attacking = false
	elseif ev == "SPELLCAST_START" then
		ST.castEnd = GetTime() + ((tonumber(a2) or 0) / 1000) + 0.3
	elseif ev == "SPELLCAST_CHANNEL_START" then
		ST.castEnd = GetTime() + ((tonumber(a1) or 0) / 1000) + 0.3
	elseif ev == "SPELLCAST_DELAYED" then
		ST.castEnd = (ST.castEnd or 0) + ((tonumber(a1) or 0) / 1000)
	elseif ev == "SPELLCAST_STOP" or ev == "SPELLCAST_FAILED" or ev == "SPELLCAST_INTERRUPTED" or ev == "SPELLCAST_CHANNEL_STOP" then
		ST.castEnd = 0
		if ST.restorePending then
			FAT.Delay(0.1, FAT.DoRestoreHeal)
		end
		if ST.retargetPending then
			FAT.Delay(0.1, FAT.DoRetarget)
		end
	elseif ev == "CHAT_MSG_COMBAT_HOSTILE_DEATH" then
		FAT.OnDeath(a1)
	elseif string.find(ev, "^CHAT_MSG_SPELL_CREATURE") then
		FAT.OnCreatureCast(a1)
	elseif ev == "VARIABLES_LOADED" then
		FAT.OnLoaded()
	elseif ev == "PLAYER_ENTERING_WORLD" or ev == "CHARACTER_POINTS_CHANGED" then
		if FAT.OnWorld then
			FAT.OnWorld(ev)
		end
	end
end

FAT.frame:SetScript("OnEvent", function()
	local ok, err = pcall(FAT.OnEvent, event, arg1, arg2)
	if not ok then
		FAT.d(FAT.Tr("erreur evenement %s : %s", tostring(event), tostring(err)))
	end
end)

-- ========= Base de donnees : creation et migration douce =========
function FAT.FixEntry(e)
	if type(e) ~= "table" or type(e.name) ~= "string" or e.name == "" then
		return false
	end
	if not FAT.ValidMode(e.mode) then e.mode = "range" end
	e.attack = e.attack and true or false
	e.pvp = e.pvp and true or false
	if e.via ~= "key" and e.via ~= "click" then e.via = "both" end
	if type(e.key) ~= "number" or e.key < 1 or e.key > FAT.MAX_SLOTS then e.key = nil end
	if e.fb ~= nil and (not FAT.ValidFallback(e.fb)) then e.fb = nil end
	if type(e.f) ~= "table" then
		e.f = nil
	else
		local k
		for k, _ in pairs(e.f) do
			local valid = false
			local i = 1
			while FAT.FILTER_KEYS[i] do
				if FAT.FILTER_KEYS[i] == k then valid = true end
				i = i + 1
			end
			if (not valid) or (k == "dist" and type(e.f[k]) ~= "number") or (k ~= "dist" and type(e.f[k]) ~= "boolean") then
				e.f[k] = nil
			end
		end
		if next(e.f) == nil then e.f = nil end
	end
	return true
end

function FAT.FixSettings(S)
	local D = FAT.DEFAULTS
	local k, v
	for k, v in pairs(D) do
		if S[k] == nil or type(S[k]) ~= type(v) then
			S[k] = CopyTable(v)
		end
	end
	local function clamp(key, lo, hi)
		if S[key] < lo then S[key] = lo elseif S[key] > hi then S[key] = hi end
	end
	clamp("dist", 0, 100)
	clamp("scan", 1, 16)
	clamp("retargetGap", 0.1, 10)
	clamp("minInterval", 0.05, 5)
	clamp("healMin", 1, 100)
	if S.lang ~= "fr" and S.lang ~= "en" then S.lang = "auto" end
	if not FAT.ValidFallback(S.fallback) then S.fallback = "nearest" end
	-- marqueurs : 1 a 8, sans doublon
	local clean, seen, i = {}, {}, 1
	while type(S.marks) == "table" and S.marks[i] do
		local m = tonumber(S.marks[i])
		if m and m >= 1 and m <= 8 and (not seen[m]) then
			tinsert(clean, math.floor(m))
			seen[m] = true
		end
		i = i + 1
	end
	if clean[1] == nil then clean = CopyTable(D.marks) end
	S.marks = clean
end

function FAT.InitDB()
	FredoAutoTargetDB = FredoAutoTargetDB or {}
	local DB = FredoAutoTargetDB
	local hadData = (DB.version == nil) and (type(DB.spells) == "table") and (next(DB.spells) ~= nil)
	local oldVersion = DB.version
	if type(DB.spells) ~= "table" then DB.spells = {} end
	if type(DB.settings) ~= "table" then DB.settings = {} end
	if type(DB.profiles) ~= "table" then DB.profiles = {} end
	if type(DB.specBind) ~= "table" then DB.specBind = {} end
	FAT.FixSettings(DB.settings)
	local i = 1
	while i <= FAT.MAX_SLOTS do
		local e = DB.spells[i]
		if e then
			if not FAT.FixEntry(e) then
				DB.spells[i] = nil
			elseif not e.key then
				e.key = i -- ancienne version : une touche par sort
			end
		end
		i = i + 1
	end
	-- les cles au dela des emplacements sont ignorees (ne supprime rien)
	DB.version = FAT.DB_VERSION
	if hadData and oldVersion == nil then
		DB.migrated = true
	end
	FAT.DB = DB
	FAT.S = DB.settings
	return DB
end

function FAT.OnLoaded()
	local ok, err = pcall(FAT.InitDB)
	if not ok then
		FAT.p("|cffff5555" .. FAT.Tr("ERREUR") .. "|r " .. FAT.Tr("base de donnees : %s", tostring(err)))
		FredoAutoTargetDB = { spells = {}, settings = CopyTable(FAT.DEFAULTS), profiles = {}, specBind = {}, version = FAT.DB_VERSION }
		FAT.DB = FredoAutoTargetDB
		FAT.S = FAT.DB.settings
	end
	FAT.ApplyLang() -- langue choisie (reglage lang) : libelles, noms de raccourcis, panneau
	FAT.SyncEvents()
	if FAT.CreateOptionsPanel then
		local ok2, err2 = pcall(FAT.CreateOptionsPanel)
		if not ok2 then
			FAT.p("|cffff5555" .. FAT.Tr("ERREUR") .. "|r " .. FAT.Tr("panneau d'options : %s", tostring(err2)))
		end
	end
	if FAT.S.indicator and FAT.RefreshIndicator then
		pcall(FAT.RefreshIndicator)
	end
	FAT.frame:UnregisterEvent("VARIABLES_LOADED")
end

FAT.InstallHooks()
