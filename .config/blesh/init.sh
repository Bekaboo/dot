#!/usr/bin/env bash
# vim: ft=sh ts=4 sw=4 sts=4 et :

bleopt input_encoding=UTF-8
bleopt prompt_eol_mark=''
bleopt filename_ls_colors="$LS_COLORS"
# bleopt term_modifyOtherKeys_passthrough_kitty_protocol=1

#
# Settings for vim editing mode
#
function my/vim-load-hook {
    # Vim mode mode line settings
    # bleopt keymap_vi_mode_string_nmap=$'\e[1m-- NORMAL --\e[m'
    bleopt keymap_vi_mode_show=

    # Vim mode cursor shape settings
    ble-bind -m vi_cmap --cursor 0
    ble-bind -m vi_imap --cursor 1
    ble-bind -m vi_nmap --cursor 2
    ble-bind -m vi_omap --cursor 4
    ble-bind -m vi_smap --cursor 2
    ble-bind -m vi_xmap --cursor 2

    # Vim mode vim-surround support
    source "$_ble_base/lib/vim-surround.sh"
}
blehook/eval-after-load keymap_vi my/vim-load-hook

#
# Color settings
#
local yellow='#FFC552'
local earth='#C1933E'
local orange='#FF761A'
local scarlet='#FF3600'
local ochre='#E84E31'
local wine='#B31F1F'
local pink='#F0989A'
local tea='#C1E587'
local aqua='#6EC4CC'
local skyblue='#8ECAFF'
local turquoise='#55ABB3'
local flashlight='#B9DEFF'
local cerulean='#79A9F5'
local lavender='#BB99E3'
local magenta='#DE05A1'
local purple='#8966D1'
local thunder='#2D1078'
local white='#E5E5EB'
local beige='#CFC1B2'
local pigeon='#8F9FBC'
local steel='#666C84'
local smoke='#B4B4B9'
local iron='#313742'
local deepsea='#12244C'
local ocean='#0F172B'
local space='#070D1F'
local black='#000004'

ble-face -s argument_option           fg="$lavender"
ble-face -s auto_complete             fg="$steel"
ble-face -s cmdinfo_cd_cdpath         fg="$pigeon"
ble-face -s command_alias             fg="$aqua",italic
ble-face -s command_builtin           fg="$orange"
ble-face -s command_builtin_dot       fg="$orange",bold
ble-face -s command_directory         fg="$skyblue"
ble-face -s command_file              fg="$tea",bold
ble-face -s command_function          fg="$yellow"
ble-face -s command_jobs              fg="$scarlet",bold
ble-face -s command_keyword           fg="$magenta"
ble-face -s disabled                  fg="$iron"
ble-face -s filename_block            fg="$yellow",bg="$black",bold
ble-face -s filename_character        fg="$yellow",bg="$black",bold
ble-face -s filename_directory        fg="$skyblue",bold
ble-face -s filename_directory_sticky fg="$black",bg="$tea"
ble-face -s filename_executable       fg="$tea",bold
ble-face -s filename_link             fg="$turquoise",bold
ble-face -s filename_ls_colors        none
ble-face -s filename_orphan           fg="$white",bg="$scarlet",bold,blink
ble-face -s filename_other            fg="$white"
ble-face -s filename_pipe             fg="$yellow"
ble-face -s filename_setgid           fg="$black",bg="$yellow"
ble-face -s filename_setuid           fg="$white",bg="$scarlet"
ble-face -s filename_socket           fg="$lavender",bold
ble-face -s filename_url              fg="$flashlight",underline
ble-face -s filename_warning          fg="$white",bg="$wine",bold,blink
ble-face -s overwrite_mode            fg="$iron"
ble-face -s prompt_status_line        fg="$white"
ble-face -s region                    fg="$smoke",bg="$thunder"
ble-face -s region_insert             fg="$pigeon"
ble-face -s region_match              fg="$flashlight",bold
ble-face -s region_target             fg="$pigeon"
ble-face -s syntax_brace              fg="$smoke"
ble-face -s syntax_command            fg="$smoke"
ble-face -s syntax_comment            fg="$steel"
ble-face -s syntax_default            fg="$pigeon"
ble-face -s syntax_delimiter          fg="$smoke"
ble-face -s syntax_document           fg="$earth"
ble-face -s syntax_document_begin     fg="$earth",bold
ble-face -s syntax_error              fg="$steel",italic,strike
ble-face -s syntax_escape             fg="$orange"
ble-face -s syntax_expr               fg="$orange"
ble-face -s syntax_function_name      fg="$yellow"
ble-face -s syntax_glob               fg="$orange"
ble-face -s syntax_history_expansion  fg="$steel"
ble-face -s syntax_param_expansion    fg="$magenta"
ble-face -s syntax_quotation          fg="$beige"
ble-face -s syntax_quoted             fg="$beige"
ble-face -s syntax_tilde              fg="$smoke"
ble-face -s syntax_varname            fg="$pigeon",bold
ble-face -s varname_array             fg="$pigeon"
ble-face -s varname_empty             fg="$steel",bold
ble-face -s varname_export            fg="$pigeon",bold
ble-face -s varname_expr              fg="$pigeon",bold
ble-face -s varname_hash              fg="$beige",italic
ble-face -s varname_number            fg="$pigeon",bold
ble-face -s varname_readonly          fg="$pigeon",bold
ble-face -s varname_transform         fg="$pigeon",bold
ble-face -s varname_unset             fg="$steel",bold
ble-face -s vbell                     reverse
ble-face -s vbell_erase               invis
ble-face -s vbell_flash               fg="$yellow",reverse
