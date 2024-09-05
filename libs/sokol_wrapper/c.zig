pub usingnamespace @cImport({
    @cInclude("sokol_app.h");
    @cInclude("sokol_gfx.h");
    @cInclude("sokol_log.h");
    @cInclude("sokol_glue.h");

    @cDefine("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", "");
    @cInclude("cimgui.h");
    @cInclude("cimplot.h");
    @cInclude("sokol_imgui.h");
});
