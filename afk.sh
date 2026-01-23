#!/bin/bash
# afk.sh - Autonomous bead processing loop with streaming output
# Usage: ./afk.sh <iterations>

set -e

# Play completion sound (macOS)
play_completion_sound() {
  if command -v afplay &> /dev/null; then
    afplay /System/Library/Sounds/Hero.aiff &
  fi
}

if [ -z "$1" ]; then
  echo "Usage: $0 <iterations>"
  exit 1
fi

read -r -d '' PROMPT << 'EOF' || true
Read AGENTS.md so it is fresh in your mind.
1. **Find the bead to work on:** Use br to find any in-progress bead (which means you started but still need to finish it). If there are no in-progress beads, find the next ready bead.
2. **Set the bead to in-progress** Set the bead you are working on to in-progress. If this is a child bead of a parent, read the parent bead for context and set the parent to in-progress if it isn't already.
3. **Create a plan:** Understand all the details of the bead (make sure you read the comments too) and come up with a plan and implement it.
4. **Implement the bead:** Implement the bead. Ensure all your changes and additions are covered in tests.
5. **Stop if context window is too low** If you are getting low in your context window, get to a stopping point, add a comment to the bead with your progress so the next agent can take over. Include anything you would want to know if you had to finish this bead but had no knowledge of what was done on it. Then stop. Write your progress as output to the user.
6. **Check all feedback loops:** Make sure the project builds, that unit test pass, linters, etc. If there are issues, fix them. You are the only one working on this codebase, so you own all failures even if they seem unrealted to your changes. Do not leave flaky tests behind. Fix them.
If you see issues that need solved, or discover more work, create a bead comprehensively explaining it. Attach the bead to the parent bead of your bead or add a dependency to ensure it gets worked on in the proper order.
7. **Commit your changes:** Use standard commit message formatting and include details of what you did.
8. **Update the bead** Comment on the bead with what you did, then close it.
9. **Close parent bead if all children are complete:** If you just finished the last child bead of a parent, close the parent bead.
10. **Output and Stop:** Then output to the user what you accomplished and anything they should know and stop. Do not take on another task.
**IMPORTANT** If you complete the last bead and/or there are no beads left, output <promise>COMPLETE</promise>.
EOF

# jq filter to extract streaming text from assistant messages
stream_text='select(.type == "assistant").message.content[]? | select(.type == "text").text // empty | gsub("\n"; "\r\n") | . + "\r\n\n"'

# jq filter to extract final result
final_result='select(.type == "result").result // empty'

for ((i=1; i<=$1; i++)); do
  echo "=== AFK iteration $i of $1 ==="

  tmpfile=$(mktemp)
  trap "rm -f $tmpfile" EXIT

  claude \
    --permission-mode acceptEdits \
    --verbose \
    --print \
    --output-format stream-json \
    -p "$PROMPT" \
  | { grep --line-buffered '^{' || true; } \
  | tee "$tmpfile" \
  | jq --unbuffered -rj "$stream_text" || true

  result=$(jq -r "$final_result" "$tmpfile")

  if [[ "$result" == *"<promise>COMPLETE</promise>"* ]]; then
    echo "All beads complete, exiting."
    play_completion_sound
    exit 0
  fi
done

echo "Completed $1 iterations."
play_completion_sound
