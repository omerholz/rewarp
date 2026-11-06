# Runs as the first executable user conf.d snippet, with native Fish startup
# and universal-variable synchronization enabled.
status is-interactive; or return
begin
    set -l fish_trace
    set -g --unexport _rewarp_helper "$REWARP_SHELL_HELPER"
    set -g --unexport _rewarp_socket "$REWARP_SOCKET"
    set -g --unexport _rewarp_init "$REWARP_SHELL_INIT"
    set -g --unexport _rewarp_token ("$_rewarp_helper" token "$_rewarp_socket" 2>/dev/null)
    set -g _rewarp_authenticated 0
    if test -n "$_rewarp_token"
        set -g _rewarp_authenticated 1
    end
    set -e REWARP_SOCKET REWARP_SHELL_HELPER REWARP_SHELL_INIT
end

function _rewarp_report --argument-names key value
    set -l fish_trace
    begin
        builtin printf '%s\n' "$_rewarp_token"
        builtin printf '%s' "$value"
    end | "$_rewarp_helper" report "$key"
end

if test $_rewarp_authenticated = 1
    _rewarp_report hello
end

# Restore the user's XDG paths before loading user snippets. Fish's native
# configuration loop retains basename precedence through the wrapper's masks.
if test "$REWARP_USER_XDG_CONFIG_HOME_SET" = 1
    set -gx XDG_CONFIG_HOME "$REWARP_USER_XDG_CONFIG_HOME"
else
    set -e XDG_CONFIG_HOME
end
set -g _rewarp_user_config "$HOME/.config/fish"
if test -n "$XDG_CONFIG_HOME"
    set -g _rewarp_user_config "$XDG_CONFIG_HOME/fish"
end
for name in fish_function_path fish_complete_path
    set -l replacement
    for item in $$name
        switch "$item"
            case "$__fish_config_dir/functions"
                set -a replacement "$_rewarp_user_config/functions"
            case "$__fish_config_dir/completions"
                set -a replacement "$_rewarp_user_config/completions"
            case '*'
                set -a replacement "$item"
        end
    end
    set -g $name $replacement
end
set -g __fish_config_dir "$_rewarp_user_config"
set -e REWARP_USER_XDG_CONFIG_HOME REWARP_USER_XDG_CONFIG_HOME_SET
for file in "$_rewarp_user_config"/conf.d/*.fish
    if test -f "$file"; and test -r "$file"
        source "$file"
    end
end
