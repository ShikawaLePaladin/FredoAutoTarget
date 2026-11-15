---------------------------------------------------------------
-- FAT_Data.lua - donnees de FredoAutoTarget 2.0 (aucune logique)
-- Modes, textes, reglages par defaut, presets de classe, listes de
-- debuffs de controle (FR + EN). Lua 5.0 / source ASCII : les lettres
-- accentuees sont ecrites en octets UTF-8 decimaux (\195\169 = e aigu).
---------------------------------------------------------------

FredoAutoTarget = FredoAutoTarget or {}
local FAT = FredoAutoTarget

FAT.VERSION = "2.1.1"
FAT.DB_VERSION = 2
FAT.MAX_SLOTS = 24

-- ========= Modes de selection =========
FAT.MODES = { "keep", "range", "nearest", "assist", "mark", "weak", "caster", "heal", "none" }
-- modes acceptes comme repli (assist/heal/none n'ont pas de sens ici sauf none)
FAT.FALLBACKS = { "nearest", "keep", "mark", "weak", "caster", "none" }

FAT.MODE_LABEL = {
	keep = "Garder",
	range = "A portee",
	nearest = "Plus proche",
	assist = "Assister",
	mark = "Prioritaire",
	weak = "Plus faible",
	caster = "Lanceur",
	heal = "Soigner",
	none = "Pas de changement",
}

FAT.MODE_HELP = {
	keep = "Garde ta cible si elle est ennemie et vivante, sinon prend l'ennemi valide le plus proche.",
	range = "Garde ta cible si elle est a portee du sort, sinon prend l'ennemi valide le plus proche.",
	nearest = "Prend l'ennemi valide le plus proche (max 1 changement par intervalle, 0.25 s par defaut).",
	assist = "Prend la cible de ton tank / chef de groupe (ou du joueur choisi avec /fat set assist <nom>).",
	mark = "Prend le mob marque dans l'ordre choisi (crane, croix, carre...), sinon le plus proche.",
	weak = "Prend l'ennemi valide qui a le moins de PV (en %).",
	caster = "Prefere les mobs qui sont en train de lancer un sort, sinon le plus proche.",
	heal = "Cible l'allie le plus blesse (toi, groupe, raid, familiers). Jamais d'ennemi, pas d'auto-attaque.",
	none = "Ne change jamais la cible : le sort part sur la cible actuelle.",
}

-- fragments pour l'apercu textuel
FAT.MODE_DESC = {
	keep = "garde ta cible si elle est valide, sinon prend le plus proche",
	range = "garde ta cible si elle est a portee du sort, sinon prend le plus proche",
	nearest = "prend toujours le plus proche",
	assist = "prend la cible de ton tank / chef",
	mark = "prend le mob marque en priorite (puis le plus proche)",
	weak = "prend l'ennemi le plus faible (PV %)",
	caster = "prefere les mobs qui lancent un sort (puis le plus proche)",
	heal = "cible l'allie le plus blesse",
	none = "ne change pas la cible",
}

-- ========= Reglages par defaut (DB.settings) =========
FAT.DEFAULTS = {
	enabled = true,
	debug = false,
	-- filtres d'acquisition (globaux ; chaque sort peut les remplacer)
	combat = true,       -- seulement les mobs en combat (contre moi / mon groupe)
	dist = 30,           -- distance max en metres (0 = portee du sort)
	pets = true,         -- ignorer familiers, totems, bestioles, civils
	cc = true,           -- ignorer les mobs controles (poly, sap, gel, piege...)
	tapped = true,       -- ignorer les mobs deja tapes par un autre groupe
	los = true,          -- ligne de vue (si UnitXP est present)
	pvpsafe = true,      -- ignorer les joueurs ennemis si je ne suis pas en PvP
	pull = false,        -- autoriser a choisir un mob hors combat (pull) quand je suis hors combat
	-- re-ciblage / modes
	retarget = true,     -- nouvelle cible quand la mienne meurt en combat
	retargetGap = 0.5,   -- au plus un changement automatique par intervalle (s)
	minInterval = 0.25,  -- mode "Plus proche" : intervalle mini entre deux changements (s)
	scan = 8,            -- candidats examines au maximum (1 a 16)
	fallback = "nearest",-- mode de repli par defaut (assister/prioritaire/plus faible/lanceur)
	assist = "",         -- nom du joueur a assister (vide = chef de groupe / assistants)
	marks = { 8, 7, 6, 5, 4, 3, 2, 1 },  -- ordre des marqueurs (8 = crane ... 1 = etoile)
	healMin = 100,       -- Soigner : seuls les allies sous ce % de PV comptent
	healPets = true,     -- Soigner : inclure les familiers
	healRestore = false, -- Soigner : revenir a la cible d'avant apres le sort
	indicator = false,   -- petit cadre d'etat
	lang = "auto",       -- langue de l'interface : auto (selon GetLocale), fr ou en
}

-- reglages que les profils sauvegardent (le reste est personnel)
FAT.PROFILE_KEYS = {
	"combat", "dist", "pets", "cc", "tapped", "los", "pvpsafe", "pull", "retarget",
	"retargetGap", "minInterval", "scan", "fallback", "assist", "marks", "healMin",
	"healPets", "healRestore",
}

-- filtres que chaque sort peut remplacer
FAT.FILTER_KEYS = { "combat", "dist", "pets", "cc", "tapped", "los", "pvpsafe", "pull" }

FAT.FILTER_LABEL = {
	combat = "En combat seulement",
	dist = "Distance max",
	pets = "Sans familiers/totems",
	cc = "Sans mobs controles",
	tapped = "Sans mobs tapes",
	los = "Ligne de vue",
	pvpsafe = "Sans joueurs (hors PvP)",
	pull = "Autoriser le pull",
}

FAT.FILTER_HELP = {
	combat = "Ne prend que des mobs en combat (contre toi ou ton groupe). Evite les mobs lointains ou passifs.",
	dist = "Distance maximale en metres. 0 = portee du sort. Precis avec UnitXP ; sinon limite a 28 m (11 m / 10 m pour les petites valeurs).",
	pets = "Ignore les familiers pacifiques, bestioles, totems, civils et les familiers de joueurs.",
	cc = "Ignore les mobs sous controle : metamorphose, assommer, piege givrant, gel, entraves, bannissement, peur...",
	tapped = "Ignore les mobs deja engages par un autre joueur/groupe (barre grise), sauf s'ils attaquent ton groupe.",
	los = "Ignore les mobs hors ligne de vue (necessite UnitXP_SP3).",
	pvpsafe = "Ignore les joueurs ennemis quand tu n'es pas marque PvP (evite de te marquer ou d'attaquer un duel).",
	pull = "Hors combat, permet de prendre un mob au repos. Desactive : l'addon ne choisit jamais un mob au hasard hors combat.",
}

-- ========= Raisons de refus =========
FAT.REASON = {
	none = "aucun ennemi",
	dead = "mort",
	friend = "allie / non attaquable",
	notplayer = "pas un joueur",
	pet = "familier / totem",
	critter = "bestiole pacifique",
	civil = "civil",
	cc = "controle (poly/sap/gel/piege...)",
	tapped = "deja tape par un autre",
	combat = "pas en combat",
	far = "trop loin",
	los = "hors ligne de vue",
	pvp = "joueur (tu n'es pas en PvP)",
	incant = "incantation en cours",
	pvponly = "aucun joueur ennemi",
	nochange = "cible inchangee",
	ok = "ok",
}

-- ========= Marqueurs =========
FAT.MARK_NAME = {
	[1] = "Etoile", [2] = "Cercle", [3] = "Losange", [4] = "Triangle",
	[5] = "Lune", [6] = "Carre", [7] = "Croix", [8] = "Crane",
}
-- noms acceptes en commande (minuscules, sans accent) -> numero
FAT.MARK_ALIAS = {
	star = 1, etoile = 1, circle = 2, cercle = 2, orange = 2, diamond = 3, losange = 3,
	triangle = 4, moon = 5, lune = 5, square = 6, carre = 6, cross = 7, croix = 7,
	skull = 8, crane = 8,
}

-- ========= Types de creature ignores =========
-- UnitCreatureType renvoie le mot du CLIENT (Bete / Beast, Mort-vivant / Undead...). Cles : FAT.TypeKey()
-- (minuscules, sans accent, tirets et espaces multiples ramenes a un espace). Valeur : raison du refus.
-- Les types normaux (bete, demon, elementaire, humanoide, mort-vivant, gangrelle...) ne sont JAMAIS ignores.
FAT.IGNORED_TYPES = {
	["critter"] = "critter", ["bestiole"] = "critter", ["bestioles"] = "critter",
	["non combat pet"] = "critter", ["noncombat pet"] = "critter", ["non combat pets"] = "critter",
	["familier pacifique"] = "critter", ["familier non combattant"] = "critter",
	["familier non combattants"] = "critter", ["mascotte"] = "critter", ["vanity pet"] = "critter",
	["pet"] = "pet", ["familier"] = "pet", ["companion"] = "pet", ["compagnon"] = "pet",
	["totem"] = "pet", ["totems"] = "pet",
}

-- ========= Controle : textures (sous-chaines, minuscules) et noms =========
FAT.CC_TEXTURES = {
	"polymorph", "ability_sap", "ability_gouge", "spell_frost_chainsofice",
	"spell_frost_frostnova", "spell_nature_slow", "spell_shadow_cripple",
	"spell_nature_sleep", "spell_shadow_possession", "spell_shadow_psychicscream",
	"spell_shadow_deathcoil", "spell_shadow_mindsteal", "ability_druid_cower",
	"ability_golemstormbolt", "inv_spear_02", "spell_holy_prayerofhealing",
	"spell_holy_turnundead", "spell_shadow_shadowworddominate",
	"spell_shadow_enslavedemon", "ability_hunter_pet_turtle",
	"spell_shadow_deathscream", "spell_nature_stranglevines",
}
-- noms de debuffs (minuscules, sans accent) FR + EN. Noms de 4 lettres ou moins ("sap", "gel", "peur",
-- "hex", "fear") : mot entier seulement ; les autres : sous-chaine. Lus dans l'infobulle du client
-- (donc dans la langue du client) et compares sans accent ni casse.
FAT.CC_NAMES = {
	-- metamorphose / polymorph (toutes les variantes : poulet, cochon, tortue...)
	"polymorph", "metamorphose",
	-- assommer / sap, suriner / gouge, cecite / blind
	"sap", "assommer", "gouge", "suriner", "blind", "cecite",
	-- pieges et gel : piege givrant, nova de givre, gel (elementaire d'eau), freeze
	"freezing trap", "piege givrant", "frost nova", "nova de givre", "freeze", "gel",
	-- entraves des morts-vivants, bannissement, hibernation, maleficio (hex)
	"shackle undead", "entraves des morts", "banish", "bannir", "bannissement",
	"hibernate", "hibernation", "hex", "malefice",
	-- peur : peur / fear, cri psychique, hurlement de terreur, voile mortel, cri d'intimidation
	"fear", "peur", "psychic scream", "cri psychique", "howl of terror", "hurlement de terreur",
	"death coil", "voile mortel", "intimidating shout", "cri d'intimidation",
	"seduction", "scare beast", "effrayer une bete", "scatter shot", "fleche de dispersion", "tir dispersant",
	"wyvern sting", "piqure de wyverne", "repentance", "repentir", "turn undead", "renvoi des morts",
	"mind control", "controle mental", "enslave demon", "asservir", "entangling roots", "sarments",
}

-- ========= Presets par classe =========
-- { nom EN, nom FR, mode, auto-attaque, { autres noms FR facultatifs } }. Un nom ne compte que si le sort est
-- dans TON livre de sorts (EN ou FR) : un nom inconnu est simplement ignore.
FAT.CLASS_LABEL = {
	WARRIOR = "Guerrier", ROGUE = "Voleur", PALADIN = "Paladin", SHAMAN = "Chaman",
	DRUID = "Druide", HUNTER = "Chasseur", MAGE = "Mage", WARLOCK = "D\195\169moniste",
	PRIEST = "Pr\195\170tre",
}

FAT.PRESETS = {
	WARRIOR = {
		{ "Charge", "Charge", "range", true },
		{ "Heroic Strike", "Frappe h\195\169ro\195\175que", "range", true },
		{ "Mortal Strike", "Frappe mortelle", "range", true },
		{ "Bloodthirst", "Sanguinaire", "range", true },
		{ "Overpower", "Fulgurance", "range", true },
		{ "Rend", "Pourfendre", "range", true },
		{ "Hamstring", "Brise-genou", "range", true },
		{ "Execute", "Ex\195\169cution", "range", true },
		{ "Sunder Armor", "Fracasser armure", "range", true, { "Brise-armure" } },
		{ "Revenge", "Vengeance", "range", true },
		{ "Intercept", "Interception", "range", true },
		{ "Shield Bash", "Coup de bouclier", "range", true },
		{ "Pummel", "Vol\195\169e de coups", "range", true },
		{ "Taunt", "Provocation", "keep", false },
		{ "Slam", "Heurtoir", "range", true },
	},
	ROGUE = {
		{ "Sinister Strike", "Attaque pernicieuse", "range", true },
		{ "Backstab", "Attaque sournoise", "range", true },
		{ "Eviscerate", "\195\137visc\195\169ration", "range", true },
		{ "Cheap Shot", "Coup bas", "range", true },
		{ "Ambush", "Embuscade", "range", true },
		{ "Gouge", "Suriner", "range", true },
		{ "Kick", "Coup de pied", "range", true },
		{ "Hemorrhage", "H\195\169morragie", "range", true },
		{ "Garrote", "Garrot", "range", true },
		{ "Rupture", "Rupture", "range", true },
		{ "Expose Armor", "Exposer l'armure", "range", true },
		{ "Ghostly Strike", "Frappe fantomatique", "range", true },
	},
	PALADIN = {
		{ "Crusader Strike", "Frappe du crois\195\169", "range", true },
		{ "Holy Strike", "Frappe sacr\195\169e", "range", true },
		{ "Judgement", "Jugement", "range", true },
		{ "Hammer of Wrath", "Marteau de courroux", "range", true },
		{ "Exorcism", "Exorcisme", "range", true },
		{ "Holy Shock", "Horion sacr\195\169", "keep", true },
		{ "Hammer of Justice", "Marteau de la justice", "keep", false },
		{ "Holy Light", "Lumi\195\168re sacr\195\169e", "heal", false },
		{ "Flash of Light", "\195\137clair lumineux", "heal", false },
	},
	SHAMAN = {
		{ "Earth Shock", "Horion de terre", "keep", true },
		{ "Flame Shock", "Horion de flammes", "keep", true },
		{ "Frost Shock", "Horion de givre", "keep", true },
		{ "Lightning Bolt", "\195\137clair", "keep", true },
		{ "Chain Lightning", "Cha\195\174ne d'\195\169clairs", "keep", true },
		{ "Stormstrike", "Frappe-temp\195\170te", "range", true, { "Courroux naturel" } },
		{ "Primal Strike", "Frappe primordiale", "range", true },
		{ "Healing Wave", "Vague de soins", "heal", false },
		{ "Lesser Healing Wave", "Vague de soins inf\195\169rieurs", "heal", false, { "Vague de soins mineure" } },
		{ "Chain Heal", "Salve de gu\195\169rison", "heal", false },
	},
	DRUID = {
		{ "Wrath", "Col\195\168re", "keep", true },
		{ "Moonfire", "\195\137clat lunaire", "keep", true },
		{ "Starfire", "Feu stellaire", "keep", true },
		{ "Insect Swarm", "Essaim d'insectes", "keep", true },
		{ "Faerie Fire", "Lucioles", "keep", true },
		{ "Faerie Fire (Feral)", "Lucioles (farouche)", "keep", true },
		{ "Claw", "Griffe", "range", true },
		{ "Rake", "Griffure", "range", true },
		{ "Shred", "Lambeau", "range", true },
		{ "Rip", "D\195\169chirure", "range", true },
		{ "Ferocious Bite", "Morsure f\195\169roce", "range", true },
		{ "Maul", "Mutiler", "range", true },
		{ "Bash", "Sonner", "range", true },
		{ "Growl", "Grondement", "keep", false },
		{ "Healing Touch", "Toucher gu\195\169risseur", "heal", false, { "Toucher de gu\195\169rison" } },
		{ "Regrowth", "R\195\169tablissement", "heal", false },
		{ "Rejuvenation", "R\195\169cup\195\169ration", "heal", false },
	},
	HUNTER = {
		{ "Arcane Shot", "Tir des arcanes", "keep", true },
		{ "Multi-Shot", "Fl\195\168ches multiples", "keep", true, { "Fusillade", "Fl\195\168che multiple" } },
		{ "Serpent Sting", "Piq\195\187re de serpent", "keep", true, { "Morsure de serpent" } },
		{ "Aimed Shot", "Vis\195\169e", "keep", true },
		{ "Concussive Shot", "Trait de choc", "keep", true, { "Tir de commotion" } },
		{ "Hunter's Mark", "Marque du chasseur", "keep", true },
		{ "Steady Shot", "Tir assur\195\169", "keep", true, { "Tir stable" } },
		{ "Raptor Strike", "Attaque du raptor", "range", true },
		{ "Mongoose Bite", "Morsure de la mangouste", "range", true },
		{ "Wing Clip", "Coupure d'ailes", "range", true },
	},
	MAGE = {
		{ "Fireball", "Boule de feu", "keep", true },
		{ "Frostbolt", "\195\137clair de givre", "keep", true },
		{ "Arcane Missiles", "Projectiles des arcanes", "keep", true },
		{ "Fire Blast", "Trait de feu", "keep", true, { "Explosion de feu" } },
		{ "Scorch", "Br\195\187lure", "keep", true },
		{ "Pyroblast", "Explosion pyrotechnique", "keep", true },
		{ "Counterspell", "Contresort", "keep", false },
	},
	WARLOCK = {
		{ "Shadow Bolt", "Trait de l'ombre", "keep", true },
		{ "Immolate", "Immolation", "keep", true },
		{ "Corruption", "Corruption", "keep", true },
		{ "Curse of Agony", "Mal\195\169diction d'agonie", "keep", true },
		{ "Drain Life", "Drain de vie", "keep", true },
		{ "Drain Soul", "Siphon d'\195\162me", "keep", true, { "Drain d'\195\162me" } },
		{ "Siphon Life", "Siphon de vie", "keep", true },
		{ "Searing Pain", "Douleur br\195\187lante", "keep", true },
		{ "Conflagrate", "Conflagration", "keep", true },
	},
	PRIEST = {
		{ "Smite", "Ch\195\162timent", "keep", true },
		{ "Mind Blast", "Attaque mentale", "keep", true },
		{ "Holy Fire", "Flammes sacr\195\169es", "keep", true },
		{ "Flash Heal", "Soins rapides", "heal", false },
		{ "Heal", "Soins", "heal", false },
		{ "Greater Heal", "Soins sup\195\169rieurs", "heal", false },
		{ "Lesser Heal", "Soins inf\195\169rieurs", "heal", false },
		{ "Renew", "R\195\169novation", "heal", false },
	},
}

-- ========= Noms des raccourcis (Raccourcis > Fredo AutoTarget) =========
-- Poses (ou reposes apres /fat lang) par FAT.ApplyLang : BINDING_HEADER_ / BINDING_NAME_ dans la langue active.
-- Les cles FR ci-dessous sont aussi les cles du catalogue anglais (FAT_LocEN.lua).
function FAT.ApplyBindingNames()
	local T = FAT.Tr
	BINDING_HEADER_FREDOAUTOTARGET = T("Fredo AutoTarget")
	BINDING_NAME_FREDOAUTOTARGET_TOGGLE = T("Activer / d\195\169sactiver l'auto-cible")
	BINDING_NAME_FREDOAUTOTARGET_OPTIONS = T("Ouvrir / fermer le panneau d'options")
	BINDING_NAME_FREDOAUTOTARGET_NEXT = T("Cible suivante filtr\195\169e")
	BINDING_NAME_FREDOAUTOTARGET_PREV = T("Cible pr\195\169c\195\169dente filtr\195\169e")
	BINDING_NAME_FREDOAUTOTARGET_PLAYER = T("Cibler un joueur ennemi")
	BINDING_NAME_FREDOAUTOTARGET_LOWEST = T("Cibler l'ennemi le plus bas en PV")
	BINDING_NAME_FREDOAUTOTARGET_ASSIST = T("Assister le tank / chef")
	BINDING_NAME_FREDOAUTOTARGET_MARK = T("Cibler le mob marqu\195\169 prioritaire")
	BINDING_NAME_FREDOAUTOTARGET_CASTER = T("Cibler un lanceur de sorts")
	BINDING_NAME_FREDOAUTOTARGET_HEAL = T("Cibler l'alli\195\169 le plus bless\195\169")
	BINDING_NAME_FREDOAUTOTARGET_CLEAR = T("Vider la cible")
end

-- Langue : photographie des textes FR ci-dessus, puis application de la langue active
-- (les noms de touches, libelles de modes, filtres, raisons... sont recrees dans la bonne langue).
FAT.ApplyLang()
