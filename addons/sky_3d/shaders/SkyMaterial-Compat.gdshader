// Copyright (c) 2023-2026 Cory Petkovsek and Contributors
// Copyright (c) 2021 J. Cuellar
//
// Compatibility variant of the Sky3D sky shader. GLES3 never runs the
// quarter-res sky subpass, and on Godot 4.5.x its sky template cannot even
// compile a QUARTER_RES_COLOR read: the template's sampler block references
// Vulkan-only sampler macros (SAMPLER_LINEAR_CLAMP and friends) that GLES3
// never defines, so the whole shader fails with "undefined variable". This
// wrapper omits the render_mode flag and the read — clouds always march in the
// main pass at full resolution, exactly as before the subpass split. SkyDome
// assigns this file when the Compatibility renderer is active.
//
// See SkyDome._apply_sky_shader_variant().

shader_type sky;
render_mode use_debanding;

#include "SkyCode.gdshaderinc"
