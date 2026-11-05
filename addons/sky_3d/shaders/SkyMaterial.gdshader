// Copyright (c) 2023-2026 Cory Petkovsek and Contributors
// Copyright (c) 2021 J. Cuellar
//
// Forward+ / Mobile variant of the Sky3D sky shader. The quarter-res sky subpass
// marches the cumulus raymarch at 1/16th resolution and this pass samples it via
// QUARTER_RES_COLOR. Godot defines USE_QUARTER_RES_PASS only in subpass
// invocations, and Compatibility never runs the subpass at all — on GLES3 the
// template's sampler block for the builtin cannot even compile — so SkyDome
// assigns SkyMaterial-Compat.gdshader there. All uniforms, functions and sky()
// live in SkyCode.gdshaderinc; the two wrappers are one line of real
// differences each.
//
// See SkyDome._apply_sky_shader_variant().

shader_type sky;
render_mode use_debanding, use_quarter_res_pass;

#define QUARTER_RES_READ
#include "SkyCode.gdshaderinc"
