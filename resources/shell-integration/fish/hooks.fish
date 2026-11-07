test $_rewarp_authenticated = 1; or return

function _rewarp_preexec --on-event fish_preexec --argument-names command
    _rewarp_report start "$command"
    set -g _rewarp_running 1
end

function _rewarp_postexec --on-event fish_postexec
    set -l command_status $status
    if test "$_rewarp_running" = 1
        _rewarp_report done "$command_status"
        set -g _rewarp_running 0
    end
end

# The reader preserves the previous command's status while rendering prompts.
# Call the user's prompt first so both $status and $pipestatus remain intact.
function _rewarp_prompt_wrapper
    _rewarp_user_prompt
    _rewarp_report ready
end

function _rewarp_precmd --on-event fish_prompt
    set -l command_status $status
    if test "$_rewarp_running" = 1
        _rewarp_report done "$command_status"
        set -g _rewarp_running 0
    end
    set -l path_value (string join : -- $PATH)
    set -l names (string join ' ' -- (functions --names | string match -rv '^_') (abbr --list))
    if test "$path_value" != "$_rewarp_last_path"
        _rewarp_report path "$path_value"
        set -g _rewarp_last_path "$path_value"
    end
    if test "$names" != "$_rewarp_last_names"
        _rewarp_report names "$names"
        set -g _rewarp_last_names "$names"
    end
    _rewarp_report cwd "$PWD"
    _rewarp_report prompt

    # Prompt managers can replace fish_prompt after startup. Wrap the new prompt
    # on the next reader cycle, retaining its definition and right prompt.
    if test (functions fish_prompt | string collect) != "$_rewarp_wrapped_prompt"
        functions --erase _rewarp_user_prompt
        functions --copy fish_prompt _rewarp_user_prompt
        functions --erase fish_prompt
        functions --copy _rewarp_prompt_wrapper fish_prompt
        set -g _rewarp_wrapped_prompt (functions fish_prompt | string collect)
    end
end
