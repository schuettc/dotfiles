---
name: running-long-jobs
description: Runs a long command that only needs to finish (a deploy, build, test suite, benchmark, migration, data load) in a named tmux window Court can watch, checks it from a log file, and closes the window when done. Use before running any command likely to take more than a minute.
---

# Running long jobs in a tmux window

A command that only needs to finish runs in its own window in your tmux session. Court sees it in the status bar and can watch it live; you spend no turns watching it. Work that needs judgment while it runs (implementing, reviewing, investigating) belongs in a subagent instead.

If `$TMUX` is empty you are not in tmux and Court cannot see a window: run the command in a subagent instead.

## Start it

Name the window for the job in a few words (`cdk-deploy`, `api-tests`, `load-orders`). Start it without taking focus, and keep the window id it prints:

```sh
tmux new-window -d -P -F '#{window_id}' -n api-tests -c "$PWD" \
  '{ just test; echo "exit=$?"; } 2>&1 | tee /tmp/pi-job-api-tests.log; exec zsh'
```

- `-d` leaves Court where they are; `-P -F '#{window_id}'` prints the id (like `@12`) you close it by later.
- `tee` shows the output in the window and keeps it in the log you read.
- The last line of the log is `exit=N`: that is the verdict, not your reading of the output.
- `exec zsh` keeps the window open after the command ends, so the output stays scrollable.

Tell Court the window name and what it runs, in one line.

## Check on it

- Done yet: `grep '^exit=' /tmp/pi-job-api-tests.log`.
- Progress or the failure: `tail -n 40 /tmp/pi-job-api-tests.log`.
- Not done: call `schedule_wakeup` with a delay that fits the job; never sleep or loop in a tool call.

## Clean up

Once you have read the exit line and reported the result, close the window and remove the log:

```sh
tmux kill-window -t @12; rm -f /tmp/pi-job-api-tests.log
```

Leave the window open only if it failed and Court is likely to look at it, and say so.
