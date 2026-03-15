local OP = prisontest
local RT = OP.rename_token_mod or {}
local U = rawget(_G, "prisontest_utils")

if U and type(U.register_public_command) == "function" then
    U.register_public_command("rename")
end

local ITEM_NAME = "prisontest_renametoken:rename_token"
local ITEM_TEX = "renametoken.png"
local KEY_CUSTOM_NAME = "prisontest:custom_pick_name"
local MAX_NAME_LEN = 40

local ESC_WHITE = minetest.get_color_escape_sequence("#ffffff")
local ESC_GRAY = minetest.get_color_escape_sequence("#919191")
local ESC_TITLE = minetest.get_color_escape_sequence("#98775D")
local ESC = minetest.formspec_escape

local runtime = {
    input = {},
    pending_confirm = {},
}

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function give_item(player, stack)
    if not player or not player:is_player() then
        return false
    end
    if U and U.give_item then
        U.give_item(player, stack)
        return true
    end
    local inv = player:get_inventory()
    if inv and inv:room_for_item("main", stack) then
        inv:add_item("main", stack)
        return true
    end
    minetest.add_item(player:get_pos(), stack)
    return true
end

local function read_hex_token(input, index)
    local t8 = input:sub(index, index + 7)
    if t8:match("^&#[%x][%x][%x][%x][%x][%x]$") then
        return t8:sub(2), 8
    end
    local t9 = input:sub(index, index + 8)
    if t9:match("^&#[%x][%x][%x][%x][%x][%x];$") then
        return t9:sub(2, 8), 9
    end
    local t10 = input:sub(index, index + 9)
    local hex10 = t10:match("^<&#([%x][%x][%x][%x][%x][%x])>$")
    if hex10 then
        return "#" .. hex10, 10
    end
    local t11 = input:sub(index, index + 10)
    local hex11 = t11:match("^<&#([%x][%x][%x][%x][%x][%x]);>$")
    if hex11 then
        return "#" .. hex11, 11
    end
    return nil, 0
end

local function visible_name(raw)
    local input = tostring(raw or "")
    local out = {}
    local i = 1
    while i <= #input do
        local _, step = read_hex_token(input, i)
        if step > 0 then
            i = i + step
        else
            out[#out + 1] = input:sub(i, i)
            i = i + 1
        end
    end
    return table.concat(out)
end

local function render_minecraft_hex_name(raw)
    local input = trim(raw):gsub("[\r\n\t]", " ")
    if input == "" then
        return nil, nil, "Name cannot be empty."
    end

    local plain = trim(visible_name(input))
    if plain == "" then
        return nil, nil, "Name cannot be empty."
    end
    if #plain > MAX_NAME_LEN then
        return nil, nil, "Name too long. Max " .. tostring(MAX_NAME_LEN) .. " visible characters."
    end

    local out = {}
    local i = 1
    while i <= #input do
        local hex, step = read_hex_token(input, i)
        if hex then
            out[#out + 1] = minetest.get_color_escape_sequence(hex)
            i = i + step
        else
            out[#out + 1] = input:sub(i, i)
            i = i + 1
        end
    end
    out[#out + 1] = minetest.get_color_escape_sequence("#ffffff")
    return table.concat(out), input, nil
end

local function set_pick_custom_name(stack, raw_name)
    if not (stack and OP.is_pick and OP.is_pick(stack)) then
        return false, "Hold your prison pickaxe first."
    end

    local rendered, stored, err = render_minecraft_hex_name(raw_name)
    if not rendered then
        return false, err
    end

    local meta = stack:get_meta()
    meta:set_string(KEY_CUSTOM_NAME, stored)
    OP.apply_lore(stack, OP.get_enchants(stack))
    return true, "Pickaxe renamed."
end

local function open_gui(player, status, confirm_mode)
    if not player or not player:is_player() then
        return
    end

    local pname = player:get_player_name()
    local input_value = runtime.input[pname]
    if type(input_value) ~= "string" then
        input_value = ""
    end

    local fs = {
        "formspec_version[4]",
        "size[9.6,4.8]",
        "label[0.6,0.5;Rename Token]",
        "label[0.6,1.1;You can use HEX Colors! (e.g: &#54daf4Pickaxe)]",
        "field[0.7,2.0;7.8,0.9;rename_name;New name;" .. ESC(input_value or "") .. "]",
        "button_exit[8.3,0.45;1.0,0.8;close;X]",
    }
    if confirm_mode then
        fs[#fs + 1] = "button[0.7,3.0;2.2,0.9;rename_confirm;Confirm]"
        fs[#fs + 1] = "button[3.0,3.0;2.2,0.9;rename_cancel;Back]"
    else
        fs[#fs + 1] = "button[0.7,3.0;2.2,0.9;rename_apply;Rename]"
        fs[#fs + 1] = "button[3.0,3.0;2.2,0.9;rename_preview;Preview]"
    end

    if status and status ~= "" then
        fs[#fs + 1] = "label[0.7,4.05;" .. ESC(status) .. "]"
    end

    minetest.show_formspec(pname, RT.formname, table.concat(fs))
end

local function consume_token(player)
    local inv = player and player:get_inventory()
    if not inv then
        return false
    end
    if not inv:contains_item("main", ITEM_NAME) then
        return false
    end
    local removed = inv:remove_item("main", ItemStack(ITEM_NAME .. " 1"))
    return (removed and removed:get_count() or 0) > 0
end

local function has_token(player)
    local inv = player and player:get_inventory()
    if not inv then
        return false
    end
    return inv:contains_item("main", ITEM_NAME)
end

local original_apply_lore = OP.apply_lore
if type(original_apply_lore) == "function" then
    OP.apply_lore = function(stack, ench)
        original_apply_lore(stack, ench)
        if not (stack and OP.is_pick and OP.is_pick(stack)) then
            return
        end

        local meta = stack:get_meta()
        local raw_name = trim(meta:get_string(KEY_CUSTOM_NAME))
        if raw_name == "" then
            return
        end

        local rendered = render_minecraft_hex_name(raw_name)
        if not rendered then
            return
        end
        local profile = type(OP.get_pick_profile) == "function" and OP.get_pick_profile(stack) or {}
        local parts_tier = math.max(1, math.floor((tonumber(profile.parts_prestige) or 0) + 1))
        local tier_hex = type(OP.tier_color_hex) == "function" and OP.tier_color_hex(parts_tier) or "#ffffff"
        local tier_color = minetest.get_color_escape_sequence(tier_hex)
        local header = rendered
        if parts_tier > 1 then
            -- Keep the full "(P#)" suffix tinted with the part-tier color.
            header = rendered .. " " .. ESC_GRAY .. "(" .. tier_color .. "P" .. tostring(parts_tier) .. ESC_GRAY .. ")" .. ESC_WHITE
        end

        local desc = meta:get_string("description")
        if desc == "" then
            meta:set_string("description", header)
            return
        end

        local lines = {}
        for line in (desc .. "\n"):gmatch("(.-)\n") do
            lines[#lines + 1] = line
        end
        if #lines <= 0 then
            lines[1] = header
        else
            lines[1] = header
        end
        meta:set_string("description", table.concat(lines, "\n"))
    end
end

minetest.register_craftitem(ITEM_NAME, {
    description = ESC_TITLE .. "Rename Token" .. ESC_WHITE .. "\n" .. ESC_WHITE .. "Hold your pickaxe and do /rename",
    inventory_image = ITEM_TEX,
    stack_max = 99,
    on_use = function(itemstack, user)
        if user and user:is_player() then
            minetest.chat_send_player(user:get_player_name(), "Hold your pickaxe and do /rename")
        end
        return itemstack
    end,
    on_secondary_use = function(itemstack, user)
        if user and user:is_player() then
            minetest.chat_send_player(user:get_player_name(), "Hold your pickaxe and do /rename")
        end
        return itemstack
    end,
})

minetest.register_chatcommand("rename", {
    description = "Open pickaxe rename UI (hold your prison pickaxe).",
    func = function(name)
        local player = minetest.get_player_by_name(name)
        if not player then
            return false, "Player not found."
        end
        if not has_token(player) then
            return false, "You need a Rename Token."
        end
        local wield = player:get_wielded_item()
        if not (wield and OP.is_pick and OP.is_pick(wield)) then
            return false, "Hold your prison pickaxe in hand."
        end
        runtime.input[name] = ""
        runtime.pending_confirm[name] = nil
        open_gui(player)
        return true
    end,
})

minetest.register_chatcommand("grantrename", {
    params = "<amount> <player>",
    description = "Admin: grant rename token item(s).",
    func = function(name, param)
        local amount_raw, target_name = tostring(param or ""):match("^%s*(%S+)%s+(%S+)%s*$")
        if not amount_raw or not target_name then
            return false, "Usage: /grantrename <amount> <player>"
        end
        local parsed = tonumber(amount_raw)
        if not parsed then
            return false, "Amount must be a number."
        end
        local amount = math.max(1, math.min(9999, math.floor(parsed)))
        local target = minetest.get_player_by_name(target_name)
        if not target then
            return false, "Player not online: " .. tostring(target_name)
        end
        give_item(target, ItemStack(ITEM_NAME .. " " .. tostring(amount)))
        return true, "Granted " .. tostring(amount) .. " rename token(s) to " .. target_name .. "."
    end,
})

minetest.register_on_player_receive_fields(function(player, formname, fields)
    if formname ~= RT.formname then
        return false
    end
    if not player or not player:is_player() then
        return true
    end

    local pname = player:get_player_name()
    if type(fields.rename_name) == "string" then
        runtime.input[pname] = fields.rename_name
        if runtime.pending_confirm[pname] and runtime.pending_confirm[pname] ~= runtime.input[pname] then
            runtime.pending_confirm[pname] = nil
        end
    end

    if fields.quit then
        runtime.input[pname] = nil
        runtime.pending_confirm[pname] = nil
        return true
    end

    if fields.rename_preview then
        local render, _, err = render_minecraft_hex_name(runtime.input[pname] or "")
        if not render then
            open_gui(player, err)
            return true
        end
        open_gui(player, "Preview: " .. render)
        return true
    end

    if fields.rename_apply or fields.key_enter_field == "rename_name" then
        local _preview, _, err = render_minecraft_hex_name(runtime.input[pname] or "")
        if not _preview then
            open_gui(player, err)
            return true
        end
        runtime.pending_confirm[pname] = runtime.input[pname] or ""
        open_gui(player, "Press Confirm to apply rename.", true)
        return true
    end

    if fields.rename_cancel then
        runtime.pending_confirm[pname] = nil
        open_gui(player)
        return true
    end

    if fields.rename_confirm then
        local wield = player:get_wielded_item()
        if not (wield and OP.is_pick and OP.is_pick(wield)) then
            open_gui(player, "Hold your prison pickaxe in hand.")
            return true
        end
        if not consume_token(player) then
            open_gui(player, "You need a Rename Token.")
            return true
        end

        local rename_value = runtime.pending_confirm[pname] or runtime.input[pname] or ""
        local ok, msg = set_pick_custom_name(wield, rename_value)
        if not ok then
            give_item(player, ItemStack(ITEM_NAME .. " 1"))
            open_gui(player, msg)
            return true
        end

        player:set_wielded_item(wield)
        runtime.input[pname] = nil
        runtime.pending_confirm[pname] = nil
        minetest.chat_send_player(pname, msg)
        if type(minetest.close_formspec) == "function" then
            minetest.close_formspec(pname, RT.formname)
        else
            minetest.show_formspec(pname, RT.formname, "")
        end
        return true
    end

    return true
end)
