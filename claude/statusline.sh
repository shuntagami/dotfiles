#!/usr/bin/env bash

jq -r '
  (.model.display_name // "?") as $model
  | (.workspace.current_dir // .cwd // "") as $dir
  | (env.HOME // "") as $home
  | (if $home != "" and ($dir | startswith($home))
      then "~" + $dir[($home | length):]
      else $dir
    end) as $shortdir
  | (.context_window.used_percentage // 0) as $context_used
  | (if $context_used >= 80 then "\u001b[31m"
      elif $context_used >= 50 then "\u001b[33m"
      else "\u001b[32m"
    end) as $context_color
  | (.rate_limits.seven_day.used_percentage // null) as $weekly_used
  | (if $weekly_used == null then ""
      else
        ([100 - $weekly_used, 0] | max) as $weekly_left_unbounded
        | ([$weekly_left_unbounded, 100] | min) as $weekly_left
        | (if $weekly_left <= 20 then "\u001b[31m"
            elif $weekly_left <= 50 then "\u001b[33m"
            else "\u001b[32m"
          end) as $weekly_color
        | " \u001b[2m·\u001b[0m \($weekly_color)weekly \($weekly_left | floor)% left\u001b[0m"
    end) as $weekly
  | "\u001b[36m\($model)\u001b[0m \u001b[35m\($shortdir)\u001b[0m \($context_color)ctx \($context_used | floor)%\u001b[0m\($weekly)"
'
