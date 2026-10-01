-- Recognition is not a claim about installed dictionaries or model capability.
local M = {
	version = 1,
	provenance = {
		reviewed = "2026-09-28",
		ltex = "https://ltex-plus.github.io/ltex-plus/supported-languages.html",
		ltex_tags = "18.7.x+ documentation; runtime verification is profile-specific",
		vim = "https://ftp.nluug.nl/pub/vim/runtime/spell/",
		regions = "Neovim 0.12.5 :help spell (Vim spell-file format)",
	},
	identities = {},
}

local function language(id, name, aliases, variants)
	local entry = {
		id = id,
		name = name,
		translation_name = name,
		aliases = aliases,
		variants = {},
		default = variants[1][1],
	}
	for _, v in ipairs(variants) do
		entry.variants[v[1]] = {
			id = v[1],
			name = v[2],
			instruction = v[2],
			spell = v[3] or false,
			ltex = v[4] or false,
			hosted_only = v[5] or false,
		}
	end
	M.identities[id] = entry
end

language("ca", "Catalan", { "cat" }, {
	{ "ca-ES", "Catalan (Spain)", "ca", "ca-ES" },
	{ "ca-ES-valencia", "Valencian Catalan", "ca", "ca-ES-valencia" },
	{ "ca-ES-balear", "Balearic Catalan", "ca", "ca-ES-balear" },
})
language("de", "German", { "deu", "ger" }, {
	{ "de-DE", "German (Germany)", "de_de", "de-DE" },
	{ "de-AT", "German (Austria)", "de_at", "de-AT" },
	{ "de-CH", "German (Switzerland)", "de_ch", "de-CH" },
	{ "de-DE-1996", "German (Germany, new spelling)", "de_20", "de-DE" },
	{ "de-DE-x-simple-language", "Simple German", "de_de", "de-DE-x-simple-language" },
})
language("en", "English", { "eng" }, {
	{ "en-US", "English (US)", "en_us", "en-US" },
	{ "en-GB", "English (Great Britain)", "en_gb", "en-GB" },
	{ "en-AU", "English (Australia)", "en_au", "en-AU" },
	{ "en-CA", "English (Canada)", "en_ca", "en-CA" },
	{ "en-NZ", "English (New Zealand)", "en_nz", "en-NZ" },
	{ "en-ZA", "English (South Africa)", false, "en-ZA" },
})
language("fr", "French", { "fra", "fre" }, {
	{ "fr-FR", "French (France)", "fr", "fr-FR" },
	{ "fr-BE", "French (Belgium)", "fr", "fr-BE" },
	{ "fr-CA", "French (Canada)", "fr", "fr-CA" },
	{ "fr-CH", "French (Switzerland)", "fr", "fr-CH" },
})
language("es", "Spanish", { "spa" }, {
	{ "es-ES", "Spanish (Spain)", "es", "es-ES" },
	{ "es-AR", "Spanish (Argentina, voseo)", "es", "es-AR" },
})
language("pt", "Portuguese", { "por" }, {
	{ "pt-PT", "Portuguese (Portugal)", "pt_pt", "pt-PT" },
	{ "pt-BR", "Portuguese (Brazil)", "pt_br", "pt-BR" },
	{ "pt-AO", "Portuguese (Angola, pre-AO)", false, "pt-AO" },
	{ "pt-MZ", "Portuguese (Mozambique, pre-AO)", false, "pt-MZ" },
})
language("nl", "Dutch", { "nld", "dut" }, {
	{ "nl-NL", "Dutch (Netherlands)", "nl", "nl-NL" },
	{ "nl-BE", "Dutch (Belgium)", "nl", "nl-BE" },
})

-- Explicit checker mappings; never inferred from a BCP-47 spelling.
local rows = {
	{ "ar", "Arabic", "ara", "ar", false, "ar" },
	{ "ast", "Asturian", nil, "ast-ES", false, "ast-ES" },
	{ "be", "Belarusian", "bel", "be-BY", false, "be-BY" },
	{ "br", "Breton", "bre", "br-FR", "br", "br-FR" },
	{ "zh", "Chinese", "zho,chi", "zh-CN", false, "zh-CN" },
	{ "crh", "Crimean Tatar", nil, "crh-UA", false, "crh-UA" },
	{ "da", "Danish", "dan", "da-DK", "da", "da-DK" },
	{ "eo", "Esperanto", "epo", "eo", "eo", "eo" },
	{ "gl", "Galician", "glg", "gl-ES", "gl", "gl-ES" },
	{ "el", "Greek", "ell,gre", "el-GR", "el", "el-GR" },
	{ "ga", "Irish", "gle", "ga-IE", "ga", "ga-IE" },
	{ "it", "Italian", "ita", "it-IT", "it", "it-IT" },
	{ "ja", "Japanese", "jpn", "ja-JP", false, "ja-JP" },
	{ "km", "Khmer", "khm", "km-KH", false, "km-KH" },
	{ "nb", "Norwegian Bokmal", "nob,no", "nb", "nb", "nb", true },
	{ "fa", "Persian", "fas,per", "fa-IR", false, "fa-IR" },
	{ "pl", "Polish", "pol", "pl-PL", "pl", "pl-PL" },
	{ "ro", "Romanian", "ron,rum", "ro-RO", "ro", "ro-RO" },
	{ "ru", "Russian", "rus", "ru-RU", "ru", "ru-RU" },
	{ "sk", "Slovak", "slk,slo", "sk-SK", "sk", "sk-SK" },
	{ "sl", "Slovenian", "slv", "sl-SI", "sl", "sl-SI" },
	{ "sv", "Swedish", "swe", "sv-SE", "sv", "sv-SE" },
	{ "tl", "Tagalog", "tgl", "tl-PH", "tl", "tl-PH" },
	{ "ta", "Tamil", "tam", "ta-IN", false, "ta-IN" },
	{ "uk", "Ukrainian", "ukr", "uk-UA", "uk", "uk-UA" },
	{ "af", "Afrikaans", "afr", "af", "af" },
	{ "am", "Amharic", "amh", "am", "am" },
	{ "bg", "Bulgarian", "bul", "bg", "bg" },
	{ "cs", "Czech", "ces,cze", "cs", "cs" },
	{ "cy", "Welsh", "cym,wel", "cy", "cy" },
	{ "eu", "Basque", "eus,baq", "eu", "eu" },
	{ "fo", "Faroese", "fao", "fo", "fo" },
	{ "gd", "Scottish Gaelic", "gla", "gd", "gd" },
	{ "he", "Hebrew", "heb", "he", "he" },
	{ "hr", "Croatian", "hrv", "hr", "hr" },
	{ "hu", "Hungarian", "hun", "hu", "hu" },
	{ "id", "Indonesian", "ind", "id", "id" },
	{ "ku", "Kurdish", "kur", "ku", "ku" },
	{ "la", "Latin", "lat", "la", "la" },
	{ "lt", "Lithuanian", "lit", "lt", "lt" },
	{ "lv", "Latvian", "lav", "lv", "lv" },
	{ "mg", "Malagasy", "mlg", "mg", "mg" },
	{ "mi", "Maori", "mri,mao", "mi", "mi" },
	{ "ms", "Malay", "msa,may", "ms", "ms" },
	{ "nn", "Norwegian Nynorsk", "nno", "nn", "nn" },
	{ "ny", "Chichewa", "nya", "ny", "ny" },
	{ "rw", "Kinyarwanda", "kin", "rw", "rw" },
	{ "sr", "Serbian", "srp", "sr", "sr" },
	{ "sw", "Swahili", "swa", "sw", "sw" },
	{ "tet", "Tetum", nil, "tet", "tet" },
	{ "th", "Thai", "tha", "th", "th" },
	{ "tn", "Tswana", "tsn", "tn", "tn" },
	{ "tr", "Turkish", "tur", "tr", "tr" },
	{ "yi", "Yiddish", "yid", "yi", "yi" },
	{ "zu", "Zulu", "zul", "zu", "zu" },
}
for _, row in ipairs(rows) do
	local aliases = {}
	for alias in (row[3] or ""):gmatch("[^,]+") do
		aliases[#aliases + 1] = alias
	end
	language(row[1], row[2], aliases, { { row[4], row[2], row[5], row[6], row[7] } })
end
return M
