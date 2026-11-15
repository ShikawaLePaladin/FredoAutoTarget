---------------------------------------------------------------
-- FAT_Loc.lua - langue de l'interface (francais / anglais)
--
-- Principe : TOUS les textes du code sont ecrits en francais. FAT.Tr(texte)
-- renvoie le texte tel quel en francais, ou sa traduction du catalogue
-- FAT.EN (fichier FAT_LocEN.lua, genere) en anglais. Un texte absent du
-- catalogue reste en francais (jamais d'erreur). Les arguments eventuels
-- passent par string.format ("%s", "%d").
--
-- Langue : reglage lang = "auto" (defaut : GetLocale() == "frFR" -> fr,
-- sinon en), "fr" ou "en" (/fat lang, onglet Options).
-- Lua 5.0 : pas de '...' ; source ASCII (accents = octets UTF-8 decimaux).
---------------------------------------------------------------

FredoAutoTarget = FredoAutoTarget or {}
local FAT = FredoAutoTarget

FAT.EN = FAT.EN or {}

-- langue effective : "fr" ou "en"
function FAT.Lang()
	local S = FAT.S
	local l = S and S.lang
	if l == "fr" or l == "en" then
		return l
	end
	if GetLocale and GetLocale() == "frFR" then
		return "fr"
	end
	return "en"
end

-- traduit (ou formate) un texte ecrit en francais
function FAT.Tr(s, a, b, c, d)
	if type(s) ~= "string" then
		return s
	end
	local t = s
	if FAT.Lang() == "en" then
		t = FAT.EN[s] or s
	end
	if a ~= nil then
		t = string.format(t, a, b, c, d)
	end
	return t
end

-- tables de textes de FAT_Data.lua (ecrites en francais) retraduites a chaque changement de langue
FAT.LTABLES = { "MODE_LABEL", "MODE_HELP", "MODE_DESC", "FILTER_LABEL", "FILTER_HELP", "REASON", "MARK_NAME", "CLASS_LABEL" }

function FAT.ApplyLang()
	local i = 1
	if not FAT.FR then
		-- premiere fois : les tables contiennent encore le francais d'origine -> photographie
		FAT.FR = {}
		while FAT.LTABLES[i] do
			local name = FAT.LTABLES[i]
			FAT.FR[name] = {}
			local k, v
			for k, v in pairs(FAT[name]) do
				FAT.FR[name][k] = v
			end
			i = i + 1
		end
	end
	i = 1
	while FAT.LTABLES[i] do
		local name = FAT.LTABLES[i]
		local k, v
		for k, v in pairs(FAT.FR[name]) do
			FAT[name][k] = FAT.Tr(v)
		end
		i = i + 1
	end
	if FAT.ApplyBindingNames then
		FAT.ApplyBindingNames()
	end
	if FAT.UpdateBindingNames then
		FAT.UpdateBindingNames()
	end
	if FAT.UIRelocalize then
		FAT.UIRelocalize()
	end
end

-- change la langue ("auto", "fr" ou "en"). Retourne true, ou false si la valeur est invalide.
function FAT.SetLang(v)
	v = string.lower(FAT.Trim(v))
	if v == "francais" or v == "french" then
		v = "fr"
	elseif v == "anglais" or v == "english" then
		v = "en"
	elseif v == "automatique" then
		v = "auto"
	end
	if v ~= "auto" and v ~= "fr" and v ~= "en" then
		return false
	end
	FAT.S.lang = v
	FAT.ApplyLang()
	return true
end

-- libelle de la langue pour le panneau / le chat
function FAT.LangLabel()
	local l = FAT.S and FAT.S.lang or "auto"
	local cur = (FAT.Lang() == "fr") and "Francais" or "English"
	if l == "auto" then
		return FAT.Tr("Auto (%s)", cur)
	end
	return cur
end
