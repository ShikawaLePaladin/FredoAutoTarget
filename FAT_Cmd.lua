---------------------------------------------------------------
-- FAT_Cmd.lua - liste de sorts, presets, profils, export/import,
-- commandes /fat (et /fredo), explications (test), raccourcis.
-- Lua 5.0 : pas de '#', pas de '...', pas de string.match.
---------------------------------------------------------------

local FAT = FredoAutoTarget
local Tr = FAT.Tr

-- ========= Raccourcis des touches de groupe =========
function FAT.UpdateBindingName(i)
	local text = Tr("Touche %d (vide - ajoute un sort avec /fat)", i)
	if FAT.DB then
		local list, c = FAT.GroupEntries(i)
		if c > 0 then
			text = Tr("Touche %d :", i)
			local k = 1
			while k <= c do
				text = text .. (k > 1 and " > " or " ") .. list[k].name
				k = k + 1
			end
		end
	end
	setglobal("BINDING_NAME_FREDOAUTOTARGET_SLOT" .. i, text)
end

function FAT.UpdateBindingNames()
	local i = 1
	while i <= FAT.MAX_SLOTS do
		FAT.UpdateBindingName(i)
		i = i + 1
	end
end

-- premiere touche (groupe) sans aucun sort
function FAT.FreeGroup()
	local g = 1
	while g <= FAT.MAX_SLOTS do
		local _, c = FAT.GroupEntries(g)
		if c == 0 then
			return g
		end
		g = g + 1
	end
	return 1
end

function FAT.ClearSlotBinding(i)
	local cmd = "FREDOAUTOTARGET_SLOT" .. i
	local k1, k2 = GetBindingKey(cmd)
	if k1 then SetBinding(k1) end
	if k2 then SetBinding(k2) end
	SaveBindings(GetCurrentBindingSet())
end

-- ========= Gestion de la liste =========
-- mode et auto-attaque conseilles par le preset de ta classe pour ce sort (ou nil)
function FAT.PresetFor(name)
	local cls = FAT.PlayerClass()
	local list = FAT.PRESETS[cls or ""]
	local n = FAT.Canon(name)
	local i = 1
	while list and list[i] do
		local it = list[i]
		if FAT.Canon(it[1]) == n then
			return it[3], it[4]
		end
		i = i + 1
	end
	return nil
end

-- Ajoute (ou met a jour) un sort. Retourne l'index ou nil.
function FAT.AddEntry(name, mode, attack, pvp, keepExisting)
	name = FAT.BaseName(name)
	if name == "" or (not FAT.DB) then
		return nil
	end
	-- le sort est dans mon livre de sorts (sous son nom EN, FR, sans accent...) : on garde le nom du client
	local known = FAT.SpellKnown(name)
	if known then
		name = known
	end
	if mode == nil then
		local pm, pa = FAT.PresetFor(name)
		mode = pm or "range"
		if attack == nil then attack = pa end
	end
	if not FAT.ValidMode(mode) then
		mode = "range"
	end
	if attack == nil then
		attack = (mode ~= "heal" and mode ~= "none")
	end
	local ex, idx = FAT.FindEntry(name)
	if ex and keepExisting then
		return idx
	end
	if ex then
		ex.mode = mode
		ex.attack = attack and true or false
		ex.pvp = pvp and true or false
		return idx
	end
	local i = 1
	while i <= FAT.MAX_SLOTS do
		if not FAT.DB.spells[i] then
			FAT.DB.spells[i] = { name = name, mode = mode, attack = attack and true or false, pvp = pvp and true or false, key = FAT.FreeGroup(), via = "both" }
			FAT.UpdateBindingNames()
			FAT.SyncEvents()
			return i
		end
		i = i + 1
	end
	FAT.p(Tr("Liste pleine (%d sorts maximum). Supprime-en un d'abord.", FAT.MAX_SLOTS))
	return nil
end

function FAT.RemoveEntry(i)
	local e = FAT.DB.spells[i]
	if e then
		local g = e.key
		FAT.DB.spells[i] = nil
		local _, c = FAT.GroupEntries(g)
		if c == 0 then
			FAT.ClearSlotBinding(g) -- la touche ne doit pas rester liee a un groupe vide
		end
		FAT.UpdateBindingNames()
		FAT.SyncEvents()
	end
end

function FAT.CycleIn(list, cur, back)
	local n = 0
	while list[n + 1] do
		n = n + 1
	end
	local i = 1
	while i <= n do
		if list[i] == cur then
			if back then
				return list[(i == 1) and n or (i - 1)]
			end
			return list[(i == n) and 1 or (i + 1)]
		end
		i = i + 1
	end
	return list[1]
end

function FAT.NextMode(m, back)
	return FAT.CycleIn(FAT.MODES, m, back)
end

-- Le sort est-il dans mon livre de sorts ? retourne le nom (sans rang) ou nil
function FAT.SpellKnown(name)
	local n = FAT.Canon(name)
	if n == "" then
		return nil
	end
	local i = 1
	while true do
		local sn = GetSpellName(i, "spell")
		if not sn then
			break
		end
		if FAT.Canon(sn) == n then
			return FAT.BaseName(sn)
		end
		i = i + 1
	end
	return nil
end

-- icone d'un sort (par nom) ou nil
function FAT.SpellIcon(name)
	local n = FAT.Canon(name)
	local found = nil
	local i = 1
	while true do
		local sn = GetSpellName(i, "spell")
		if not sn then
			break
		end
		if FAT.Canon(sn) == n then
			found = i
		end
		i = i + 1
	end
	if found then
		return GetSpellTexture(found, "spell")
	end
	return nil
end

function FAT.PlayerClass()
	local _, token = UnitClass("player")
	return token
end

-- sorts du preset connus de ce personnage : liste de { nom, mode, attaque }
function FAT.PresetKnown(class)
	local out = {}
	local list = FAT.PRESETS[class or FAT.PlayerClass() or ""]
	local i = 1
	while list and list[i] do
		local it = list[i]
		local nm = FAT.SpellKnown(it[1]) or FAT.SpellKnown(it[2])
		if nm then
			tinsert(out, { nm, it[3], it[4] })
		end
		i = i + 1
	end
	return out
end

-- ajoute les sorts connus du preset. Retourne le nombre d'ajouts.
function FAT.AddPreset(class)
	local known = FAT.PresetKnown(class)
	local added = 0
	local i = 1
	while known[i] do
		local it = known[i]
		if not FAT.FindEntry(it[1]) then
			if FAT.AddEntry(it[1], it[2], it[3], false, true) then
				added = added + 1
			end
		end
		i = i + 1
	end
	return added
end

-- ajoute le dernier sort lance (barre d'action, macro ou livre de sorts)
function FAT.AddLast()
	local n = FAT.ST.lastCast
	if not n then
		return nil
	end
	local idx = FAT.AddEntry(n, "range", true, false, true)
	return idx, n
end

-- ========= Apercu textuel =========
function FAT.Describe(e)
	if not e then
		return ""
	end
	local mode = e.mode
	local F = FAT.Filters(e)
	local t = (FAT.MODE_LABEL[mode] or tostring(mode)) .. " : " .. (FAT.MODE_DESC[mode] or "") .. "."
	if mode == "assist" or mode == "mark" or mode == "weak" or mode == "caster" then
		local fb = e.fb or FAT.S.fallback
		t = t .. Tr(" Sinon : %s.", FAT.MODE_DESC[fb] or fb)
	end
	if mode ~= "heal" and mode ~= "none" then
		local parts = {}
		if F.pvp then
			tinsert(parts, Tr("joueurs ennemis seulement"))
		elseif F.combat then
			tinsert(parts, F.pull and Tr("en combat (pull permis hors combat)") or Tr("en combat"))
		end
		if (tonumber(F.dist) or 0) > 0 then
			tinsert(parts, Tr("a moins de %s m", tostring(F.dist)))
		else
			tinsert(parts, Tr("a portee du sort"))
		end
		if F.pets then tinsert(parts, Tr("sans familiers/totems")) end
		if F.cc then tinsert(parts, Tr("sans mobs controles")) end
		if F.tapped then tinsert(parts, Tr("sans mobs tapes")) end
		if F.los then tinsert(parts, Tr("ligne de vue")) end
		if F.pvpsafe and (not F.pvp) then tinsert(parts, Tr("sans joueurs hors PvP")) end
		t = t .. Tr(" Nouvelle cible : %s.", table.concat(parts, ", "))
	end
	if mode == "heal" then
		t = t .. Tr(" Allies sous %s%% de PV, a portee.", tostring(FAT.S.healMin))
	end
	if e.attack and mode ~= "heal" then
		t = t .. Tr(" Puis lance le sort et l'auto-attaque.")
	else
		t = t .. Tr(" Puis lance le sort.")
	end
	return t
end

-- ========= Explications (test) =========
-- Simule le choix de cible pour une entree SANS lancer le sort.
-- Retourne une liste de lignes de texte.
function FAT.Explain(e)
	local lines = {}
	local function add(s) tinsert(lines, s) end
	local label = FAT.MODE_LABEL[e.mode] or tostring(e.mode)
	add(Tr("Test de %s (mode %s)", tostring(e.name), label))
	add(FAT.Describe(e))
	if FAT.ST.busy then
		add(Tr("Un autre traitement est en cours."))
		return lines
	end
	if FAT.IsCasting() then
		add(Tr("Incantation en cours : l'addon ne changerait PAS la cible."))
		return lines
	end
	local F = FAT.Filters(e)
	local spell = FAT.ClientName(e.name)
	if UnitExists("target") then
		local ok, why = FAT.Eval("target", F, spell, nil)
		add(Tr("Cible actuelle : %s -> %s", tostring(UnitName("target")),
			ok and Tr("valide") or Tr("refusee (%s)", tostring(FAT.REASON[why] or why))))
	else
		add(Tr("Cible actuelle : aucune"))
	end
	if not F.inCombat and F.needCombat then
		add(Tr("Tu es hors combat : seuls les mobs deja en combat sont pris (/fat set pull on pour pouvoir pull)."))
	end
	local trace = {}
	FAT.ST.busy = true
	-- copie "force" : le test balaie toujours les candidats (pas d'intervalle mini)
	local e2 = FAT.CopyTable(e)
	e2.force = true
	local okp, ok, why, used = pcall(FAT.Prepare, e2, spell, trace)
	FAT.ST.busy = false
	if not okp then
		add(Tr("Erreur : %s", tostring(ok)))
		return lines
	end
	local i = 1
	while trace[i] do
		local r = trace[i]
		local s = "  " .. (r.idx or i) .. ". " .. tostring(r.name) .. " : " .. (r.ok and "OK" or Tr("refuse (%s)", tostring(FAT.REASON[r.why] or r.why)))
		if r.dist then s = s .. " [" .. FAT.Round(r.dist) .. " m]" end
		if r.src then s = s .. " " .. Tr("[cible de %s]", tostring(r.src)) end
		add(s)
		i = i + 1
	end
	if ok then
		add(Tr("Resultat : cible = %s (%s)", tostring(UnitName("target")), FAT.MODE_LABEL[used] or tostring(used)))
	else
		add(Tr("Resultat : aucune cible valide -> %s. Ta cible d'avant est conservee.", tostring(FAT.REASON[why] or why)))
	end
	return lines
end

-- ========= Profils / export =========
function FAT.MakeProfile()
	local p = { spells = {}, settings = {} }
	local i = 1
	while i <= FAT.MAX_SLOTS do
		if FAT.DB.spells[i] then
			p.spells[i] = FAT.CopyTable(FAT.DB.spells[i])
		end
		i = i + 1
	end
	i = 1
	while FAT.PROFILE_KEYS[i] do
		local k = FAT.PROFILE_KEYS[i]
		p.settings[k] = FAT.CopyTable(FAT.S[k])
		i = i + 1
	end
	return p
end

-- applique un profil (liste + reglages de profil). Ne touche pas enabled/debug/indicator.
function FAT.ApplyProfile(p)
	if type(p) ~= "table" or type(p.spells) ~= "table" then
		return false
	end
	local DB = FAT.DB
	local newSpells = {}
	local i = 1
	while i <= FAT.MAX_SLOTS do
		local e = p.spells[i]
		if e then
			local c = FAT.CopyTable(e)
			if FAT.FixEntry(c) then
				if not c.key then c.key = i end
				newSpells[i] = c
			end
		end
		i = i + 1
	end
	local S = DB.settings
	if type(p.settings) == "table" then
		i = 1
		while FAT.PROFILE_KEYS[i] do
			local k = FAT.PROFILE_KEYS[i]
			if p.settings[k] ~= nil and type(p.settings[k]) == type(FAT.DEFAULTS[k]) then
				S[k] = FAT.CopyTable(p.settings[k])
			end
			i = i + 1
		end
	end
	DB.spells = newSpells
	FAT.FixSettings(S)
	FAT.S = S
	FAT.UpdateBindingNames()
	FAT.SyncEvents()
	if FAT.RefreshPanel then FAT.RefreshPanel() end
	return true
end

function FAT.ProfileName(n)
	n = FAT.Trim(n)
	n = string.gsub(n, "[^%w _%-]", "")
	if string.len(n) > 24 then
		n = string.sub(n, 1, 24)
	end
	return n
end

function FAT.ProfileSave(name)
	name = FAT.ProfileName(name)
	if name == "" then
		return false, Tr("Nom de profil vide.")
	end
	FAT.DB.profiles[name] = FAT.MakeProfile()
	FAT.DB.activeProfile = name
	return true, name
end

function FAT.ProfileLoad(name)
	name = FAT.ProfileName(name)
	local p = FAT.DB.profiles[name]
	if not p then
		return false, Tr("Profil introuvable : %s", name)
	end
	FAT.ApplyProfile(p)
	FAT.DB.activeProfile = name
	return true, name
end

function FAT.ProfileDelete(name)
	name = FAT.ProfileName(name)
	if not FAT.DB.profiles[name] then
		return false, Tr("Profil introuvable : %s", name)
	end
	FAT.DB.profiles[name] = nil
	if FAT.DB.activeProfile == name then FAT.DB.activeProfile = nil end
	local k, v
	for k, v in pairs(FAT.DB.specBind) do
		if v == name then FAT.DB.specBind[k] = nil end
	end
	return true, name
end

-- liste triee des noms de profils
function FAT.ProfileNames()
	local out = {}
	local k
	for k, _ in pairs(FAT.DB.profiles) do
		tinsert(out, k)
	end
	table.sort(out)
	return out
end

-- specialisation = branche de talents la plus remplie
function FAT.SpecName()
	local f = FAT.Api("GetNumTalentTabs")
	local g = FAT.Api("GetTalentTabInfo")
	if not f or not g then
		return nil
	end
	local ok, num = pcall(f)
	if not ok or not num then
		return nil
	end
	local best, bestPts = nil, 0
	local i = 1
	while i <= num do
		local ok2, nm, _, pts = pcall(g, i)
		if ok2 and nm and (tonumber(pts) or 0) > bestPts then
			best, bestPts = nm, tonumber(pts)
		end
		i = i + 1
	end
	return best
end

function FAT.ProfileBind(name)
	local spec = FAT.SpecName()
	if not spec then
		return false, Tr("Specialisation inconnue (aucun talent distribue ?).")
	end
	name = FAT.ProfileName(name)
	if not FAT.DB.profiles[name] then
		return false, Tr("Profil introuvable : %s", name)
	end
	FAT.DB.specBind[spec] = name
	return true, spec
end

function FAT.ProfileUnbind()
	local spec = FAT.SpecName()
	if spec and FAT.DB.specBind[spec] then
		FAT.DB.specBind[spec] = nil
		return true, spec
	end
	return false, spec
end

-- charge automatiquement le profil lie a la specialisation actuelle
function FAT.AutoProfile()
	if not FAT.DB then return end
	local spec = FAT.SpecName()
	local name = spec and FAT.DB.specBind[spec]
	if name and FAT.DB.profiles[name] and FAT.DB.activeProfile ~= name then
		FAT.ProfileLoad(name)
		FAT.d(Tr("profil %s charge (specialisation %s)", name, spec))
	end
end

-- ----- export / import (chaine courte copiable) -----
-- FAT2;S:cle=val,cle=val;E:nom~mode~repli~atk~pvp~via~touche~filtres;...;#somme
local function Clean(s)
	s = string.gsub(tostring(s), "[;~:,=#|]", " ")
	return FAT.Trim(s)
end

local function Bool01(b)
	return b and "1" or "0"
end

function FAT.Checksum(s)
	local sum = 0
	local i = 1
	local n = string.len(s)
	while i <= n do
		sum = math.mod((sum * 31) + string.byte(s, i), 65521)
		i = i + 1
	end
	return string.format("%x", sum)
end

local function EncodeSetting(k, v)
	if type(v) == "boolean" then
		return k .. "=" .. Bool01(v)
	elseif type(v) == "number" then
		return k .. "=" .. tostring(v)
	elseif type(v) == "table" then
		return k .. "=" .. table.concat(v, "/")
	end
	return k .. "=" .. Clean(v)
end

function FAT.Export()
	local p = FAT.MakeProfile()
	local parts = { "FAT2" }
	local st = {}
	local i = 1
	while FAT.PROFILE_KEYS[i] do
		local k = FAT.PROFILE_KEYS[i]
		tinsert(st, EncodeSetting(k, p.settings[k]))
		i = i + 1
	end
	tinsert(parts, "S:" .. table.concat(st, ","))
	i = 1
	while i <= FAT.MAX_SLOTS do
		local e = p.spells[i]
		if e then
			local f = {}
			if e.f then
				local j = 1
				while FAT.FILTER_KEYS[j] do
					local k = FAT.FILTER_KEYS[j]
					if e.f[k] ~= nil then
						tinsert(f, EncodeSetting(k, e.f[k]))
					end
					j = j + 1
				end
			end
			tinsert(parts, "E:" .. Clean(e.name) .. "~" .. e.mode .. "~" .. (e.fb or "") .. "~" .. Bool01(e.attack)
				.. "~" .. Bool01(e.pvp) .. "~" .. (e.via or "both") .. "~" .. tostring(e.key or i) .. "~" .. table.concat(f, ","))
		end
		i = i + 1
	end
	local body = table.concat(parts, ";")
	return body .. ";#" .. FAT.Checksum(body)
end

local function SplitOn(s, sep)
	local out = {}
	local n = 0
	local start = 1
	while true do
		local a, b = string.find(s, sep, start, true)
		if not a then
			n = n + 1
			out[n] = string.sub(s, start)
			break
		end
		n = n + 1
		out[n] = string.sub(s, start, a - 1)
		start = b + 1
	end
	return out, n
end

local function DecodeValue(key, raw)
	local def = FAT.DEFAULTS[key]
	if def == nil then
		return nil
	end
	if type(def) == "boolean" then
		if raw == "1" then return true elseif raw == "0" then return false end
		return nil
	elseif type(def) == "number" then
		return tonumber(raw)
	elseif type(def) == "table" then
		local out = {}
		local parts, n = SplitOn(raw, "/")
		local i = 1
		while i <= n do
			local m = tonumber(parts[i])
			if m then tinsert(out, m) end
			i = i + 1
		end
		return out
	end
	return raw
end

-- decode une chaine d'export en profil, ou nil, message
function FAT.ParseExport(str)
	str = FAT.Trim(str)
	local a, b, body, sum = string.find(str, "^(FAT2;.*);#(%x+)$")
	if not a then
		return nil, Tr("Chaine invalide (elle doit commencer par FAT2; et finir par ;#code).")
	end
	if FAT.Checksum(body) ~= sum then
		return nil, Tr("Chaine abimee ou incomplete (code de controle different).")
	end
	local p = { spells = {}, settings = {} }
	local items, n = SplitOn(body, ";")
	local idx = 0
	local i = 2
	while i <= n do
		local it = items[i]
		if string.sub(it, 1, 2) == "S:" then
			local kv, m = SplitOn(string.sub(it, 3), ",")
			local j = 1
			while j <= m do
				local _, _, k, v = string.find(kv[j], "^(%w+)=(.*)$")
				if k then
					local val = DecodeValue(k, v)
					if val ~= nil then p.settings[k] = val end
				end
				j = j + 1
			end
		elseif string.sub(it, 1, 2) == "E:" then
			local f, m = SplitOn(string.sub(it, 3), "~")
			if m >= 7 and f[1] ~= "" then
				idx = idx + 1
				if idx <= FAT.MAX_SLOTS then
					local e = { name = f[1], mode = f[2], attack = (f[4] == "1"), pvp = (f[5] == "1"), via = f[6], key = tonumber(f[7]) }
					if f[3] ~= "" then e.fb = f[3] end
					if m >= 8 and f[8] and f[8] ~= "" then
						e.f = {}
						local kv, c = SplitOn(f[8], ",")
						local j = 1
						while j <= c do
							local _, _, k, v = string.find(kv[j], "^(%w+)=(.*)$")
							if k then
								local val = DecodeValue(k, v)
								if val ~= nil then e.f[k] = val end
							end
							j = j + 1
						end
					end
					p.spells[idx] = e
				end
			end
		end
		i = i + 1
	end
	if idx == 0 then
		return nil, Tr("Aucun sort dans la chaine.")
	end
	return p
end

function FAT.Import(str)
	local p, msg = FAT.ParseExport(str)
	if not p then
		return false, msg
	end
	FAT.ApplyProfile(p)
	return true, Tr("%d sort(s) importe(s).", FAT.CountEntries())
end

-- ========= Reglages (/fat set) =========
FAT.SETTING_ALIAS = {
	distance = "dist", familiers = "pets", pets = "pets", controle = "cc", tapes = "tapped",
	vue = "los", joueurs = "pvpsafe", assister = "assist", marqueurs = "marks", repli = "fallback",
	soin = "healMin", indicateur = "indicator", retarget = "retarget", intervalle = "minInterval",
	candidats = "scan", scan = "scan", actif = "enabled", langue = "lang", language = "lang",
}

local function ParseBool(v)
	v = string.lower(FAT.Trim(v))
	if v == "on" or v == "1" or v == "oui" or v == "true" or v == "yes" or v == "y" or v == "o" then
		return true
	elseif v == "off" or v == "0" or v == "non" or v == "false" or v == "no" or v == "n" then
		return false
	end
	return nil
end
FAT.ParseBool = ParseBool

-- noms de modes acceptes en commande, dans TOUTES les langues : cle (keep, range...), libelle FR, libelle EN, alias
FAT.MODE_ALIAS = {
	portee = "range", proche = "nearest", garder = "keep", assister = "assist", prio = "mark",
	priorite = "mark", prioritaire = "mark", faible = "weak", lanceur = "caster", soigner = "heal", soin = "heal",
	rien = "none", aucun = "none", close = "nearest", closest = "nearest", marker = "mark", marked = "mark",
	priority = "mark", lowest = "weak", weakest = "weak", healer = "heal", inrange = "range", nochange = "none",
	unchanged = "none",
}

function FAT.ParseMode(w)
	w = string.lower(FAT.Fold(FAT.Trim(w)))
	local i = 1
	while FAT.MODES[i] do
		local m = FAT.MODES[i]
		local fr = (FAT.FR and FAT.FR.MODE_LABEL[m]) or FAT.MODE_LABEL[m]
		local en = FAT.EN[fr] or fr
		if w == m or w == string.lower(FAT.Fold(fr)) or w == string.lower(FAT.Fold(en)) or w == string.lower(FAT.Fold(FAT.MODE_LABEL[m])) then
			return m
		end
		i = i + 1
	end
	return FAT.MODE_ALIAS[w]
end

function FAT.ParseMarks(words, n)
	local out = {}
	local seen = {}
	local i = 1
	while i <= n do
		local w = string.lower(FAT.Fold(words[i]))
		local m = tonumber(w) or FAT.MARK_ALIAS[w]
		if m and m >= 1 and m <= 8 and (not seen[m]) then
			tinsert(out, math.floor(m))
			seen[m] = true
		end
		i = i + 1
	end
	return out
end

-- regle un reglage global. Retourne ok, message
function FAT.SetSetting(key, value, words, n)
	key = FAT.SETTING_ALIAS[string.lower(key)] or key
	local D = FAT.DEFAULTS[key]
	local S = FAT.S
	if D == nil then
		return false, Tr("Reglage inconnu : %s", tostring(key))
	end
	if key == "marks" then
		local m = FAT.ParseMarks(words, n)
		if m[1] == nil then
			return false, Tr("Marqueurs : crane croix carre lune triangle losange cercle etoile (dans l'ordre voulu).")
		end
		S.marks = m
		local names = {}
		local i = 1
		while m[i] do tinsert(names, FAT.MARK_NAME[m[i]]); i = i + 1 end
		return true, Tr("Ordre des marqueurs : %s", table.concat(names, " > "))
	elseif key == "lang" then
		if not FAT.SetLang(value) then
			return false, Tr("Utilisation : /fat lang auto|fr|en")
		end
		FAT.RefreshAll()
		return true, Tr("Langue : %s", FAT.LangLabel())
	elseif type(D) == "boolean" then
		local b = ParseBool(value)
		if b == nil then
			return false, Tr("%s : on ou off.", key)
		end
		S[key] = b
	elseif type(D) == "number" then
		local v = tonumber(value)
		if not v then
			return false, Tr("%s : un nombre est attendu.", key)
		end
		S[key] = v
	elseif key == "fallback" then
		local m = FAT.ParseMode(value)
		if not m or not FAT.ValidFallback(m) then
			return false, Tr("repli : nearest keep mark weak caster none.")
		end
		S[key] = m
	else
		S[key] = FAT.Trim(value)
	end
	FAT.FixSettings(S)
	FAT.SyncEvents()
	if key == "debug" or key == "enabled" or key == "indicator" then
		if FAT.RefreshIndicator then FAT.RefreshIndicator() end
	end
	if FAT.RefreshPanel then FAT.RefreshPanel() end
	return true, key .. " = " .. tostring(S[key])
end

-- filtre / champ d'un sort. Retourne ok, message
function FAT.SetSpellField(e, key, value)
	key = FAT.SETTING_ALIAS[string.lower(key)] or key
	local isFilter = false
	local i = 1
	while FAT.FILTER_KEYS[i] do
		if FAT.FILTER_KEYS[i] == key then isFilter = true end
		i = i + 1
	end
	local v = string.lower(FAT.Trim(value))
	if isFilter then
		if v == "auto" or v == "defaut" or v == "default" or v == "-" then
			if e.f then
				e.f[key] = nil
				if next(e.f) == nil then e.f = nil end
			end
			return true, Tr("%s : valeur globale", key)
		end
		local val
		if key == "dist" then
			val = tonumber(v)
			if not val or val < 0 or val > 100 then return false, Tr("dist : 0 a 100 (ou auto).") end
		else
			val = ParseBool(v)
			if val == nil then return false, Tr("%s : on, off ou auto.", key) end
		end
		e.f = e.f or {}
		e.f[key] = val
		return true, key .. " = " .. tostring(val)
	elseif key == "mode" then
		local m = FAT.ParseMode(v)
		if not m then return false, Tr("Mode inconnu : %s", v) end
		e.mode = m
		FAT.SyncEvents()
		return true, "mode = " .. FAT.MODE_LABEL[m]
	elseif key == "fb" or key == "fallback" then
		if v == "auto" or v == "defaut" then
			e.fb = nil
			return true, Tr("repli : global")
		end
		local m = FAT.ParseMode(v)
		if not m or not FAT.ValidFallback(m) then return false, Tr("repli : nearest keep mark weak caster none (ou auto).") end
		e.fb = m
		FAT.SyncEvents()
		return true, Tr("repli = %s", FAT.MODE_LABEL[m])
	elseif key == "attack" or key == "attaque" then
		local b = ParseBool(v)
		if b == nil then return false, Tr("attack : on ou off.") end
		e.attack = b
		return true, Tr("attaque = %s", tostring(b))
	elseif key == "pvp" then
		local b = ParseBool(v)
		if b == nil then return false, Tr("pvp : on ou off.") end
		e.pvp = b
		return true, Tr("joueurs seulement = %s", tostring(b))
	elseif key == "via" then
		if v == "both" or v == "click" or v == "key" then
			e.via = v
			return true, Tr("declencheur = %s", v)
		end
		return false, Tr("via : both, click ou key.")
	end
	return false, Tr("Champ inconnu : %s", key)
end

-- ========= Commandes =========
-- decoupe en mots ; les guillemets groupent ("Holy Strike")
function FAT.SplitArgs(s)
	local w = {}
	local n = 0
	s = tostring(s or "")
	local pos = 1
	local len = string.len(s)
	while pos <= len do
		local c = string.sub(s, pos, pos)
		if c == " " or c == "\t" then
			pos = pos + 1
		elseif c == "\"" then
			local e = string.find(s, "\"", pos + 1, true)
			if not e then e = len + 1 end
			n = n + 1
			w[n] = string.sub(s, pos + 1, e - 1)
			pos = e + 1
		else
			local e = string.find(s, "[ \t]", pos)
			if not e then e = len + 1 end
			n = n + 1
			w[n] = string.sub(s, pos, e - 1)
			pos = e
		end
	end
	return w, n
end

-- reference de sort : numero d'emplacement ou nom. Retourne entree, index.
function FAT.ResolveSpell(ref)
	local num = tonumber(ref)
	if num and FAT.DB.spells[num] then
		return FAT.DB.spells[num], num
	end
	return FAT.FindEntry(ref)
end

function FAT.ListEntries()
	local shown = 0
	local i = 1
	while i <= FAT.MAX_SLOTS do
		local e = FAT.DB.spells[i]
		if e then
			local k1 = GetBindingKey("FREDOAUTOTARGET_SLOT" .. e.key)
			FAT.p(i .. ". " .. e.name .. " | " .. (FAT.MODE_LABEL[e.mode] or e.mode)
				.. (e.fb and (" > " .. (FAT.MODE_LABEL[e.fb] or e.fb)) or "")
				.. (e.attack and Tr(" | attaque") or "")
				.. (e.pvp and Tr(" | joueurs") or "")
				.. (e.f and Tr(" | filtres perso") or "")
				.. (k1 and Tr(" | touche %s", k1) or ""))
			shown = shown + 1
		end
		i = i + 1
	end
	if shown == 0 then
		FAT.p(Tr("Liste vide. /fat preset (sorts de ta classe), /fat add <sort>, ou lance un sort puis /fat add."))
	end
end

function FAT.Status()
	local S = FAT.S
	local ST = FAT.ST
	FAT.p(Tr("FredoAutoTarget %s : %s | %s sort(s) | profil %s", FAT.VERSION, S.enabled and Tr("ACTIVE") or Tr("DESACTIVE"),
		tostring(FAT.CountEntries()), tostring(FAT.DB.activeProfile or "-")))
	FAT.p(Tr("Filtres : combat=%s dist=%s familiers=%s controle=%s", tostring(S.combat), tostring(S.dist), tostring(S.pets), tostring(S.cc))
		.. Tr(" tapes=%s vue=%s joueurs=%s pull=%s", tostring(S.tapped), tostring(S.los), tostring(S.pvpsafe), tostring(S.pull)))
	FAT.p("Extensions : UnitXP=" .. tostring(FAT.XPOK()) .. " IsSpellInRange=" .. tostring(FAT.Api("IsSpellInRange") ~= nil)
		.. " SuperWoW(GUID)=" .. tostring(FAT.GuidPresent()))
	if ST.last then
		FAT.p(Tr("Dernier : %s [%s] -> %s", tostring(ST.last.spell), FAT.MODE_LABEL[ST.last.mode] or tostring(ST.last.mode),
			ST.last.ok and "ok" or Tr("refuse : %s", tostring(FAT.REASON[ST.last.why] or ST.last.why)))
			.. (ST.last.name and (" (" .. ST.last.name .. ")") or ""))
	end
end

function FAT.GuidPresent()
	local _, guid = UnitExists("player")
	return guid ~= nil
end

local HELP = {
	"Commandes /fat (ou /fredo) :",
	"  /fat : panneau | status | list | on | off | debug | reset confirm",
	"  /fat add [sort] [mode] [pvp] [noattack] : ajoute (sans nom : le dernier sort lance)",
	"  /fat del <n|sort> | mode <n|sort> <mode> [repli] | key <n|sort> <touche 1-24>",
	"  /fat set <reglage> <valeur> : combat dist pets cc tapped los pvpsafe pull retarget scan fallback assist marks healMin indicator",
	"  /fat set <n|sort> <filtre|mode|fb|attack|pvp|via> <valeur|auto> : reglage d'un seul sort",
	"  /fat test [n|sort] : explique le choix de cible (sans lancer le sort)",
	"  /fat select next|prev|player|lowest|assist|mark|caster|heal|clear",
	"  /fat preset [classe] | profile save|load|del|list|bind|unbind <nom> | export | import <chaine>",
	"  Modes : keep range nearest assist mark weak caster heal none",
	"  /fat lang auto|fr|en : langue de l'interface (auto = celle du client)",
}

FAT.HELP_LINES = HELP

function FAT.Help()
	local i = 1
	while HELP[i] do
		FAT.p(Tr(HELP[i]))
		i = i + 1
	end
end

function FAT.RefreshAll()
	if FAT.RefreshPanel then FAT.RefreshPanel() end
	if FAT.RefreshIndicator then FAT.RefreshIndicator() end
end

function FAT.DoSelect(what)
	if what == "next" then
		return FredoAutoTarget_Cycle(false)
	elseif what == "prev" or what == "previous" then
		return FredoAutoTarget_Cycle(true)
	elseif what == "player" or what == "joueur" then
		return FredoAutoTarget_Select("player")
	elseif what == "lowest" or what == "weak" or what == "faible" then
		return FredoAutoTarget_Select("weak")
	elseif what == "assist" then
		return FredoAutoTarget_Select("assist")
	elseif what == "mark" or what == "marque" then
		return FredoAutoTarget_Select("mark")
	elseif what == "caster" or what == "lanceur" then
		return FredoAutoTarget_Select("caster")
	elseif what == "heal" or what == "soin" then
		return FredoAutoTarget_Select("heal")
	elseif what == "clear" then
		FredoAutoTarget_ClearTarget()
		return true
	end
	return nil
end

function FAT.Slash(msg)
	msg = FAT.Trim(msg)
	local _, _, cmd, rest = string.find(msg, "^(%S*)%s*(.*)$")
	cmd = string.lower(cmd or "")
	rest = FAT.Trim(rest)
	local p = FAT.p

	if not FAT.DB then
		p(Tr("Pas encore charge, reessaie dans un instant."))
		return
	end
	local S = FAT.S

	if cmd == "" or cmd == "config" or cmd == "options" or cmd == "ui" then
		FredoAutoTarget_ToggleOptions()
	elseif cmd == "help" or cmd == "aide" or cmd == "?" then
		FAT.Help()
	elseif cmd == "on" then
		S.enabled = true
		p(Tr("Auto-cible ACTIVEE"))
		FAT.RefreshAll()
	elseif cmd == "off" then
		S.enabled = false
		p(Tr("Auto-cible DESACTIVEE"))
		FAT.RefreshAll()
	elseif cmd == "toggle" then
		FredoAutoTarget_Toggle()
	elseif cmd == "debug" then
		local b = ParseBool(rest)
		if b == nil then b = not S.debug end
		S.debug = b
		p("debug " .. (S.debug and "ON" or "OFF"))
		FAT.RefreshAll()
	elseif cmd == "status" or cmd == "etat" then
		FAT.Status()
	elseif cmd == "list" or cmd == "liste" then
		FAT.ListEntries()
	elseif cmd == "add" or cmd == "ajouter" then
		-- /fat add Crusader Strike [mode] [pvp] [noattack]
		local words, n = FAT.SplitArgs(rest)
		local mode, attack, pvp = nil, nil, false
		local wholeKnown = FAT.SpellKnown(rest) ~= nil
		while n > 0 and not wholeKnown do
			local w = string.lower(words[n])
			local m = FAT.ParseMode(w)
			if m and n > 1 then
				mode = m
			elseif w == "pvp" then
				pvp = true
			elseif w == "nopvp" then
				pvp = false
			elseif w == "noattack" then
				attack = false
			elseif w == "attack" then
				attack = true
			else
				break
			end
			n = n - 1
		end
		local name = ""
		local i = 1
		while i <= n do
			name = name .. (i > 1 and " " or "") .. words[i]
			i = i + 1
		end
		if name == "" then
			local idx, ln = FAT.AddLast()
			if idx then
				p(Tr("Ajoute le dernier sort lance (emplacement %d) : %s", idx, ln))
			else
				p(Tr("Utilisation : /fat add <sort> [mode] [pvp] [noattack]  (ou lance un sort puis /fat add)"))
			end
		else
			local idx = FAT.AddEntry(name, mode, attack, pvp)
			if idx then
				local ne = FAT.DB.spells[idx]
				p(Tr("Ajoute (emplacement %d) : %s | %s", idx, ne.name, FAT.MODE_LABEL[ne.mode] or ne.mode))
			end
		end
		FAT.RefreshAll()
	elseif cmd == "del" or cmd == "remove" or cmd == "suppr" then
		local e, idx = FAT.ResolveSpell(rest)
		if idx then
			local nm = e.name
			FAT.RemoveEntry(idx)
			p(Tr("Supprime : %s", nm))
			FAT.RefreshAll()
		else
			p(Tr("Sort introuvable : %s", rest))
		end
	elseif cmd == "mode" then
		local words, n = FAT.SplitArgs(rest)
		-- "<sort> <mode> [repli]" : on essaie "mode + repli" puis "mode" seul (un sort peut finir par un mot de mode : Flash Heal)
		local function refOf(last)
			local r = ""
			local i = 1
			while i <= last do r = r .. (i > 1 and " " or "") .. words[i]; i = i + 1 end
			return r
		end
		local m1, m2, e = nil, nil, nil
		-- libelles a deux mots ("Plus proche", "Plus faible") : fusionner les deux derniers mots, puis le couple precedent
		if n >= 3 and FAT.ParseMode(words[n - 1] .. " " .. words[n]) then
			words[n - 1] = words[n - 1] .. " " .. words[n]
			words[n] = nil
			n = n - 1
		end
		if n >= 3 and FAT.ParseMode(words[n - 2] .. " " .. words[n - 1]) and FAT.ParseMode(words[n]) then
			words[n - 2] = words[n - 2] .. " " .. words[n - 1]
			words[n - 1] = words[n]
			words[n] = nil
			n = n - 1
		end
		local a = FAT.ParseMode(words[n] or "")
		local b = (n >= 2) and FAT.ParseMode(words[n - 1]) or nil
		if a and b and n >= 3 then
			e = FAT.ResolveSpell(refOf(n - 2))
			if e then m1, m2 = b, a end
		end
		if (not e) and a and n >= 2 then
			e = FAT.ResolveSpell(refOf(n - 1))
			if e then m1, m2 = a, nil end
		end
		if e and m1 then
			e.mode = m1
			if m2 and FAT.ValidFallback(m2) then e.fb = m2 end
			FAT.SyncEvents()
			p(e.name .. " -> " .. FAT.MODE_LABEL[m1] .. (m2 and (" > " .. FAT.MODE_LABEL[m2]) or ""))
			FAT.RefreshAll()
		else
			p(Tr("Utilisation : /fat mode <n|sort> <mode> [repli]  (modes : keep range nearest assist mark weak caster heal none)"))
		end
	elseif cmd == "set" or cmd == "reglage" then
		local words, n = FAT.SplitArgs(rest)
		if n == 0 then
			FAT.Status()
			return
		end
		local k1 = FAT.SETTING_ALIAS[string.lower(words[1])] or words[1]
		if FAT.DEFAULTS[k1] ~= nil then
			local val = words[2] or ""
			local tail = {}
			local i = 2
			while i <= n do tinsert(tail, words[i]); i = i + 1 end
			if k1 == "fallback" and n >= 3 then
					val = words[2] .. " " .. words[3] -- libelle a deux mots ("Plus proche")
				end
				local ok, m = FAT.SetSetting(k1, val, tail, n - 1)
			p(m)
		else
			local e = FAT.ResolveSpell(words[1])
			if e and n >= 3 then
				local ok, m = FAT.SetSpellField(e, words[2], words[3])
				p(e.name .. " : " .. m)
				FAT.RefreshAll()
			else
				p(Tr("Utilisation : /fat set <reglage> <valeur>  ou  /fat set <n|sort> <champ> <valeur|auto>"))
			end
		end
	elseif cmd == "pull" then
		local b = ParseBool(rest)
		if b == nil then b = not S.pull end
		S.pull = b
		p(b and Tr("pull AUTORISE hors combat") or Tr("pull INTERDIT hors combat"))
		FAT.RefreshAll()
	elseif cmd == "key" then
		-- /fat key <sort> <n> : rattache le sort a la touche (groupe) n
		local _, _, nm, num = string.find(rest, "^(.-)%s+(%d+)$")
		num = tonumber(num)
		local e, idx = FAT.ResolveSpell(nm or "")
		if idx and num and num >= 1 and num <= FAT.MAX_SLOTS then
			e.key = num
			FAT.UpdateBindingNames()
			p(Tr("%s -> touche %d", e.name, num))
			FAT.RefreshAll()
		else
			p(Tr("Utilisation : /fat key <sort> <1-%d>", FAT.MAX_SLOTS))
		end
	elseif cmd == "cast" then
		FredoAutoTarget_Cast(rest)
	elseif cmd == "use" then
		local num = tonumber(rest)
		if num then
			FredoAutoTarget_UseSlot(num)
		end
	elseif cmd == "select" or cmd == "cible" then
		if FAT.DoSelect(string.lower(rest)) == nil then
			p(Tr("Utilisation : /fat select next|prev|player|lowest|assist|mark|caster|heal|clear"))
		end
	elseif cmd == "test" then
		local e
		if rest == "" then
			e = FAT.ST.lastEntry
			if not e then
				-- premier sort de la liste
				local i = 1
				while i <= FAT.MAX_SLOTS and not e do
					e = FAT.DB.spells[i]
					i = i + 1
				end
			end
		else
			e = FAT.ResolveSpell(rest)
		end
		if not e then
			p(Tr("Sort introuvable (ajoute-en un, ou /fat test <n|sort>)."))
		else
			local lines = FAT.Explain(e)
			local i = 1
			while lines[i] do p(lines[i]); i = i + 1 end
			FAT.testLines = lines
			if FAT.RefreshPanel then FAT.RefreshPanel() end
		end
	elseif cmd == "preset" then
		local cls = rest ~= "" and string.upper(rest) or FAT.PlayerClass()
		local byLabel = nil
		local k, v
		for k, v in pairs(FAT.FR.CLASS_LABEL) do
			if string.upper(FAT.Fold(v)) == string.upper(FAT.Fold(rest)) or string.upper(FAT.Fold(FAT.EN[v] or v)) == string.upper(FAT.Fold(rest)) then byLabel = k end
		end
		cls = byLabel or cls
		if not FAT.PRESETS[cls or ""] then
			p(Tr("Classe inconnue : %s", tostring(cls)))
		else
			local added = FAT.AddPreset(cls)
			p(Tr("Preset %s : %d sort(s) ajoute(s) (seulement ceux de ton livre de sorts).", tostring(FAT.CLASS_LABEL[cls] or cls), added))
			FAT.RefreshAll()
		end
	elseif cmd == "profile" or cmd == "profil" then
		local _, _, sub, nm = string.find(rest, "^(%S*)%s*(.*)$")
		sub = string.lower(sub or "")
		local ok, m
		if sub == "save" or sub == "sauver" then
			ok, m = FAT.ProfileSave(nm)
			p(ok and Tr("Profil sauvegarde : %s", m) or m)
		elseif sub == "load" or sub == "charger" then
			ok, m = FAT.ProfileLoad(nm)
			p(ok and Tr("Profil charge : %s", m) or m)
		elseif sub == "del" or sub == "delete" or sub == "suppr" then
			ok, m = FAT.ProfileDelete(nm)
			p(ok and Tr("Profil supprime : %s", m) or m)
		elseif sub == "bind" or sub == "lier" then
			ok, m = FAT.ProfileBind(nm)
			p(ok and Tr("Profil lie a la specialisation %s (charge automatiquement).", m) or m)
		elseif sub == "unbind" then
			ok, m = FAT.ProfileUnbind()
			p(ok and Tr("Liaison retiree pour %s", m) or Tr("Aucune liaison pour cette specialisation."))
		elseif sub == "list" or sub == "liste" or sub == "" then
			local names = FAT.ProfileNames()
			if names[1] == nil then
				p(Tr("Aucun profil. /fat profile save <nom>"))
			else
				local i = 1
				while names[i] do
					local binds = {}
					local k2, v2
					for k2, v2 in pairs(FAT.DB.specBind) do
						if v2 == names[i] then tinsert(binds, k2) end
					end
					p(names[i] .. (FAT.DB.activeProfile == names[i] and Tr(" (actif)") or "")
						.. (binds[1] and (" [" .. table.concat(binds, ",") .. "]") or ""))
					i = i + 1
				end
			end
		else
			p(Tr("Utilisation : /fat profile save|load|del|bind|unbind|list <nom>"))
		end
		FAT.RefreshAll()
	elseif cmd == "export" then
		local s = FAT.Export()
		FAT.exportText = s
		if FAT.ShowExport then
			FAT.ShowExport(s)
			p(Tr("Chaine d'export affichee dans le panneau (Ctrl+A, Ctrl+C pour copier)."))
		else
			p(s)
		end
	elseif cmd == "import" then
		local ok, m = FAT.Import(rest)
		p(m)
		FAT.RefreshAll()
	elseif cmd == "lang" or cmd == "langue" or cmd == "language" then
		if rest == "" then
			p(Tr("Langue : %s. /fat lang auto|fr|en", FAT.LangLabel()))
		elseif FAT.SetLang(rest) then
			p(Tr("Langue : %s", FAT.LangLabel()))
			FAT.RefreshAll()
		else
			p(Tr("Utilisation : /fat lang auto|fr|en"))
		end
	elseif cmd == "reset" then
		if string.lower(rest) == "confirm" then
			local i = 1
			while i <= FAT.MAX_SLOTS do
				if FAT.DB.spells[i] then FAT.RemoveEntry(i) end
				i = i + 1
			end
			local keep = { enabled = S.enabled, debug = S.debug }
			FAT.DB.settings = FAT.CopyTable(FAT.DEFAULTS)
			FAT.DB.settings.enabled = keep.enabled
			FAT.DB.settings.debug = keep.debug
			FAT.S = FAT.DB.settings
			FAT.DB.activeProfile = nil
			FAT.SyncEvents()
			p(Tr("Liste et reglages remis a zero (les profils sont conserves)."))
			FAT.RefreshAll()
		else
			p(Tr("Ceci efface ta liste de sorts et tes reglages (pas les profils). Confirme avec : /fat reset confirm"))
		end
	else
		FAT.Help()
	end
end

SLASH_FREDOAUTOTARGET1 = "/fat"
SLASH_FREDOAUTOTARGET2 = "/fredo"
SlashCmdList["FREDOAUTOTARGET"] = function(msg)
	local ok, err = pcall(FAT.Slash, msg)
	if not ok then
		FAT.p("|cffff5555" .. Tr("ERREUR") .. "|r " .. tostring(err))
	end
end

-- ========= Premier lancement / changement de specialisation =========
function FAT.OnWorld(ev)
	if not FAT.DB then
		return
	end
	if ev == "PLAYER_ENTERING_WORLD" then
		local DB = FAT.DB
		if DB.migrated and not DB.noticed then
			DB.noticed = true
			FAT.p(Tr("FredoAutoTarget 2.0 : tes sorts sont conserves. Le ciblage ne prend plus que des mobs en combat, a portee, non controles. /fat set pull on pour pouvoir pull un mob hors combat. /fat help."))
		end
		if not DB.hintDone and FAT.CountEntries() == 0 then
			DB.hintDone = true
			local cls = FAT.PlayerClass()
			if cls and FAT.PRESETS[cls] then
				local n = 0
				local known = FAT.PresetKnown(cls)
				while known[n + 1] do n = n + 1 end
				FAT.p(Tr("FredoAutoTarget : %s detecte. /fat preset ajoute %d sort(s) courant(s) de ton livre de sorts ; /fat ouvre le panneau.", tostring(FAT.CLASS_LABEL[cls] or cls), n))
			else
				FAT.p(Tr("FredoAutoTarget : /fat ouvre le panneau, /fat add <sort> ajoute un sort."))
			end
		end
	end
	if ev == "PLAYER_ENTERING_WORLD" then
		FAT.LocalizeEntries()
	end
	FAT.AutoProfile()
end

-- Les noms de la liste suivent le client : "Heroic Strike" (profil importe, ancienne saisie) devient
-- "Frappe heroique" sur un client francais, et inversement. Seuls les sorts presents dans le livre sont touches.
function FAT.LocalizeEntries()
	if not FAT.DB then
		return 0
	end
	local changed = 0
	local i = 1
	while i <= FAT.MAX_SLOTS do
		local e = FAT.DB.spells[i]
		if e and e.name then
			local kn = FAT.SpellKnown(e.name)
			if kn and kn ~= e.name then
				e.name = kn
				changed = changed + 1
			end
		end
		i = i + 1
	end
	if changed > 0 then
		FAT.UpdateBindingNames()
	end
	return changed
end

-- ========= Livre de sorts : shift-clic = ajouter =========
function FAT.TakeSpellButton(btn)
	local bookType = "spell"
	local sb = getglobal("SpellBookFrame")
	if sb and sb.bookType then bookType = sb.bookType end
	local idf = FAT.Api("SpellBook_GetSpellID")
	local id = btn:GetID()
	if idf then id = idf(id) end
	local name = GetSpellName(id, bookType)
	if name and FAT.addBox then
		FAT.addBox:SetText(FAT.BaseName(name))
		if FAT.UIAdd then FAT.UIAdd() end
		return true
	end
	return false
end

function FAT.InstallSpellHook()
	local f = FAT.Api("SpellButton_OnClick")
	if (not f) or FAT.orig.SpellButton_OnClick then
		return
	end
	FAT.orig.SpellButton_OnClick = f
	SpellButton_OnClick = function(drag)
		if FAT.addBox and FAT.addBox:HasFocus() and IsShiftKeyDown() then
			local ok, res = pcall(FAT.TakeSpellButton, this)
			if ok and res then
				return
			end
		end
		return FAT.orig.SpellButton_OnClick(drag)
	end
end
FAT.InstallSpellHook()

FAT.UpdateBindingNames()
