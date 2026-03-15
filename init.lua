local OP = rawget(_G, "prisontest")
if type(OP) ~= "table" then
    return
end

if type(OP.enable_feature) == "function" then
    OP.enable_feature("renametoken")
end

local MODPATH = minetest.get_modpath(minetest.get_current_modname())
OP.rename_token_mod = {
    modpath = MODPATH,
    formname = "prisontest_renametoken:anvil",
}

dofile(MODPATH .. "/lib/core.lua")
