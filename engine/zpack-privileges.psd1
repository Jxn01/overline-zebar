# The ONE source of every widget's shell privileges (program -> anchored argsRegex).
#
# Zebar 3.1.1 joins a call's argv with spaces and tests the result with an UNANCHORED
# Regex::is_match, so every pattern here must be ^...$ and describe exactly what the widget
# sends: a ".*foo.*" pattern admits ANY command that merely contains "foo". cmd re-parses its
# whole command line, so cmd patterns must also exclude its metacharacters (& | < > ^ " % ( )).
#
# Applied to zpack.json (and the installed pack) by engine/set-zpack-privileges.ps1;
# guarded by engine/_test/zpack-privileges.tests.ps1, which also proves each real call matches.
@{
    main = @(
        @{ program = 'shutdown'; argsRegex = '^/[as]$' }
        @{ program = 'explorer'; argsRegex = '^ms-settings:network-status$' }
        @{ program = 'cmd';      argsRegex = '^/c type %LOCALAPPDATA%\\overline-updates\\status\.json$' }
    )
    'script-launcher' = @(
        @{ program = 'shutdown'; argsRegex = '^/[sra]( /t [0-9]{1,5})?$' }
    )
    'update-panel' = @(
        @{ program = 'cmd';  argsRegex = '^/c (echo %LOCALAPPDATA%|type [A-Za-z]:\\Users\\[A-Za-z0-9_][A-Za-z0-9_ .-]*\\AppData\\Local\\overline-updates\\(status\.json|ignore\.json|run-[a-z0-9]{1,10}\.log))$' }
        @{ program = 'pwsh'; argsRegex = '^-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File [A-Za-z]:\\Users\\[A-Za-z0-9_][A-Za-z0-9_ .-]*\\AppData\\Local\\overline-updates\\engine\\(apply|check|ignore)\.ps1( .*)?$' }
    )
    power = @(
        @{ program = 'shutdown'; argsRegex = '^/[sr] /t 0$' }
        @{ program = 'rundll32'; argsRegex = '^user32\.dll,LockWorkStation$' }
        @{ program = 'pwsh';     argsRegex = '^-NoProfile -NonInteractive -Command Add-Type -AssemblyName System\.Windows\.Forms; \[void\]\[System\.Windows\.Forms\.Application\]::SetSuspendState\(''Suspend'', \$false, \$false\)$' }
    )
}
