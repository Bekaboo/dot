#!/usr/bin/env bash
# vim: ft=sh ts=4 sw=4 sts=4 et :

bleopt input_encoding=UTF-8
bleopt prompt_eol_mark=
bleopt filename_ls_colors=$LS_COLORS
bleopt term_index_colors=auto
# bleopt term_modifyOtherKeys_passthrough_kitty_protocol=1

#
# Color settings
#
ble_yellow='#FFC552'
ble_earth='#C1933E'
ble_orange='#FF761A'
ble_scarlet='#FF3600'
ble_ochre='#E84E31'
ble_wine='#B31F1F'
ble_pink='#F0989A'
ble_tea='#C1E587'
ble_aqua='#6EC4CC'
ble_skyblue='#8ECAFF'
ble_turquoise='#55ABB3'
ble_flashlight='#B9DEFF'
ble_cerulean='#79A9F5'
ble_lavender='#BB99E3'
ble_magenta='#DE05A1'
ble_purple='#8966D1'
ble_thunder='#2D1078'
ble_white='#E5E5EB'
ble_beige='#CFC1B2'
ble_pigeon='#8F9FBC'
ble_steel='#666C84'
ble_smoke='#B4B4B9'
ble_iron='#313742'
ble_deepsea='#12244C'
ble_ocean='#0F172B'
ble_space='#070D1F'
ble_black='#000004'

ble-face -s argument_option           fg="$ble_lavender"
ble-face -s auto_complete             fg="$ble_steel"
ble-face -s cmdinfo_cd_cdpath         fg="$ble_pigeon"
ble-face -s command_alias             fg="$ble_aqua",italic
ble-face -s command_builtin           fg="$ble_orange"
ble-face -s command_builtin_dot       fg="$ble_orange",bold
ble-face -s command_directory         fg="$ble_skyblue"
ble-face -s command_file              fg="$ble_tea",bold
ble-face -s command_function          fg="$ble_yellow"
ble-face -s command_jobs              fg="$ble_scarlet",bold
ble-face -s command_keyword           fg="$ble_magenta"
ble-face -s disabled                  fg="$ble_iron"
ble-face -s filename_block            fg="$ble_yellow",bg="$ble_black",bold
ble-face -s filename_character        fg="$ble_yellow",bg="$ble_black",bold
ble-face -s filename_directory        fg="$ble_skyblue",bold
ble-face -s filename_directory_sticky fg="$ble_black",bg="$ble_tea"
ble-face -s filename_executable       fg="$ble_tea",bold
ble-face -s filename_link             fg="$ble_turquoise",bold
ble-face -s filename_ls_colors        none
ble-face -s filename_orphan           fg="$ble_white",bg="$ble_scarlet",bold,blink
ble-face -s filename_other            fg="$ble_white"
ble-face -s filename_pipe             fg="$ble_yellow"
ble-face -s filename_setgid           fg="$ble_black",bg="$ble_yellow"
ble-face -s filename_setuid           fg="$ble_white",bg="$ble_scarlet"
ble-face -s filename_socket           fg="$ble_lavender",bold
ble-face -s filename_url              fg="$ble_flashlight",underline
ble-face -s filename_warning          fg="$ble_white",bg="$ble_wine",bold,blink
ble-face -s overwrite_mode            fg="$ble_iron"
ble-face -s prompt_status_line        fg="$ble_white"
ble-face -s region                    fg="$ble_smoke",bg="$ble_thunder"
ble-face -s region_insert             fg="$ble_pigeon"
ble-face -s region_match              fg="$ble_flashlight",bold
ble-face -s region_target             fg="$ble_pigeon"
ble-face -s syntax_brace              fg="$ble_smoke"
ble-face -s syntax_command            fg="$ble_smoke"
ble-face -s syntax_comment            fg="$ble_steel"
ble-face -s syntax_default            fg="$ble_pigeon"
ble-face -s syntax_delimiter          fg="$ble_smoke"
ble-face -s syntax_document           fg="$ble_earth"
ble-face -s syntax_document_begin     fg="$ble_earth",bold
ble-face -s syntax_error              fg="$ble_steel",italic,strike
ble-face -s syntax_escape             fg="$ble_orange"
ble-face -s syntax_expr               fg="$ble_orange"
ble-face -s syntax_function_name      fg="$ble_yellow"
ble-face -s syntax_glob               fg="$ble_orange"
ble-face -s syntax_history_expansion  fg="$ble_steel"
ble-face -s syntax_param_expansion    fg="$ble_magenta"
ble-face -s syntax_quotation          fg="$ble_beige"
ble-face -s syntax_quoted             fg="$ble_beige"
ble-face -s syntax_tilde              fg="$ble_smoke"
ble-face -s syntax_varname            fg="$ble_pigeon",bold
ble-face -s varname_array             fg="$ble_pigeon"
ble-face -s varname_empty             fg="$ble_steel",bold
ble-face -s varname_export            fg="$ble_pigeon",bold
ble-face -s varname_expr              fg="$ble_pigeon",bold
ble-face -s varname_hash              fg="$ble_beige",italic
ble-face -s varname_number            fg="$ble_pigeon",bold
ble-face -s varname_readonly          fg="$ble_pigeon",bold
ble-face -s varname_transform         fg="$ble_pigeon",bold
ble-face -s varname_unset             fg="$ble_steel",bold
ble-face -s vbell                     reverse
ble-face -s vbell_erase               invis
ble-face -s vbell_flash               fg="$ble_yellow",reverse

#
# Settings for vim editing mode
#
function my/vim-load-hook {
    # Vim mode mode line settings
    # bleopt keymap_vi_mode_show=
    bleopt keymap_vi_mode_string_nmap=$'\e[1m-- NORMAL --\e[m'

    # Vim mode status line settings
    ble-import lib/vim-airline
    bleopt vim_airline_section_a='\e[1m\q{lib/vim-airline/mode}'
    bleopt vim_airline_section_b='\q{lib/vim-airline/gitstatus}'
    bleopt vim_airline_section_c='\w'
    bleopt vim_airline_section_x=
    bleopt vim_airline_section_y='$_ble_util_locale_encoding'
    bleopt vim_airline_section_z='\e[1m\q{history-index}/\!\e[22m \q{position} \q{history-percentile}'
    bleopt vim_airline_left_sep=
    bleopt vim_airline_left_alt_sep=
    bleopt vim_airline_right_sep=
    bleopt vim_airline_right_alt_sep=
    bleopt vim_airline_symbol_branch=$'\uE0A0 '
    bleopt vim_airline_symbol_dirty=' +'

    ble-face -s vim_airline_a_normal               fg=magenta,bg=none,bold
    ble-face -s vim_airline_a_insert               fg=purple,bg=none,bold
    ble-face -s vim_airline_a_replace              fg=olive,bg=none,bold
    ble-face -s vim_airline_a_visual               fg=orange,bg=none,bold
    ble-face -s vim_airline_a_commandline          fg=purple,bg=none,bold
    ble-face -s vim_airline_a_inactive             fg=white,bg=none,bold

    local modes=(normal insert replace visual commandline inactive)
    for mode in "${modes[@]}" ; do
        ble-face -s vim_airline_b_"$mode"           fg=green,bg=none
        ble-face -s vim_airline_c_"$mode"           fg=navy,bg=none,bold
        ble-face -s vim_airline_x_"$mode"           fg=silver,bg=none
        ble-face -s vim_airline_y_"$mode"           fg=silver,bg=none
        ble-face -s vim_airline_z_"$mode"           ref:vim_airline_a_"$mode"
        ble-face -s vim_airline_error_"$mode"       fg=silver,bg=brown,bold,blink
        ble-face -s vim_airline_term_"$mode"        bg=none
        ble-face -s vim_airline_warning_"$mode"     bg=none
    done

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
