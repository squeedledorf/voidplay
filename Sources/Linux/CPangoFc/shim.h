#include <fontconfig/fontconfig.h>
#include <fontconfig/fcfreetype.h>
#include <pango/pangofc-fontmap.h>
#include <pango/pangocairo.h>

static inline PangoFcFontMap *cpangofc_fc_font_map(PangoFontMap *map) { return PANGO_FC_FONT_MAP(map); }
