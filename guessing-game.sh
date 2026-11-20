#!/bin/bash

#this is a guessing game

usage() {
    printf "usage: %s <name> [level]\n" "$0"
    printf "  name  : name of the user playing the game\n"
    printf "  level : easy, normal, or hard (optional, defaults to normal)\n"
    exit 1
}

if [[ "$#" -lt 1 || "$#" -gt 2 ]]; then
    usage
fi

name="$1"
if [[ -z "$name" ]]; then
    usage
fi

level="${2:-normal}"
level="${level,,}"

case "$level" in
    easy)
        min=1
        max=50
        ;;
    normal)
        min=1
        max=100
        ;;
    hard)
        min=1
        max=1000
        ;;
    *)
        usage
        ;;
esac

log_file="history.log"

show_history() {
    echo ""
    echo "=== History for $name ==="
    if [[ ! -f "$log_file" ]]; then
        echo "No games recorded yet."
        return
    fi

    local games=0 total_tries=0 total_sec=0 best_tries=""
    printf "%-8s | %-19s | %-5s | %-7s\n" "Level" "Start Time" "Tries" "Seconds"
    echo "------------------------------------------------"

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" ]] && continue
        local pipe_count
        pipe_count=$(echo -n "$line" | tr -cd '|' | wc -c)
        (( pipe_count != 5 )) && continue

        local f_player f_level f_start f_tries f_seconds
        f_player=$(echo "$line" | cut -d'|' -f1)
        f_level=$(echo "$line" | cut -d'|' -f2)
        f_start=$(echo "$line" | cut -d'|' -f3)
        f_tries=$(echo "$line" | cut -d'|' -f5)
        f_seconds=$(echo "$line" | cut -d'|' -f6)

        [[ ! "$f_level" =~ ^(easy|normal|hard)$ ]] && continue
        [[ ! "$f_tries" =~ ^[0-9]+$ || ! "$f_seconds" =~ ^[0-9]+$ ]] && continue

        if [[ "$f_player" == "$name" ]]; then
            printf "%-8s | %-19s | %-5s | %-7s\n" "$f_level" "$f_start" "$f_tries" "$f_seconds"
            ((games++))
            ((total_tries += f_tries))
            ((total_sec += f_seconds))
            if [[ -z "$best_tries" ]] || (( f_tries < best_tries )); then
                best_tries=$f_tries
            fi
        fi
    done < "$log_file"

    echo "------------------------------------------------"
    if (( games == 0 )); then
        echo "No valid games found for $name."
    else
        local avg_tries=$(( total_tries / games ))
        echo "Summary: $games game(s) | Best: $best_tries tries | Avg: $avg_tries tries | Total time: ${total_sec}s"
    fi
}

show_leaderboard() {
    echo ""
    echo "=== Top 5 Leaderboard ($level level) ==="
    if [[ ! -f "$log_file" ]]; then
        echo "No games recorded yet."
        return
    fi

    awk -F'|' -v lvl="$level" '
        NF == 6 && $2 == lvl && $5 ~ /^[0-9]+$/ && $6 ~ /^[0-9]+$/ {
            player = $1
            tries = $5 + 0
            secs = $6 + 0
            if (!(player in best_tries) || tries < best_tries[player] || (tries == best_tries[player] && secs < best_secs[player])) {
                best_tries[player] = tries
                best_secs[player] = secs
            }
        }
        END {
            for (p in best_tries) {
                printf "%d|%d|%s\n", best_tries[p], best_secs[p], p
            }
        }
    ' "$log_file" | sort -t'|' -k1,1n -k2,2n | head -n 5 | awk -F'|' '
        BEGIN { printf "%-4s | %-15s | %-5s | %-7s\n", "Rank", "Player", "Tries", "Seconds"; print "----------------------------------------" }
        { printf "%-4s | %-15s | %-5s | %-7s\n", NR, $3, $1, $2 }
    '
}

delete_history() {
    if [[ ! -f "$log_file" ]]; then
        echo "No history file found."
        return
    fi

    read -r -p "Are you sure you want to delete all history for '$name'? (y/n): " confirm
    case "${confirm,,}" in
        y|yes)
            local tmp_file
            tmp_file=$(mktemp)
            awk -F'|' -v p="$name" '$1 != p' "$log_file" > "$tmp_file" && mv "$tmp_file" "$log_file"
            echo "History for '$name' has been deleted."
            ;;
        *)
            echo "Deletion cancelled."
            ;;
    esac
}

play_game() {
    local damaged_count=0
    local old_best=""

    if [[ -f "$log_file" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            #skip empty lines
            [[ -z "$line" ]] && continue

            #rule 1: must have exactly 6 fields (which means exactly 5 pipe characters)
            local pipe_count
            pipe_count=$(echo -n "$line" | tr -cd '|' | wc -c)
            if (( pipe_count != 5 )); then
                ((damaged_count++))
                continue
            fi

            #extract fields to test them without overwriting current game variables
            local f_player f_level f_tries f_seconds
            f_player=$(echo "$line" | cut -d '|' -f1)
            f_level=$(echo "$line" | cut -d '|' -f2)
            f_tries=$(echo "$line" | cut -d '|' -f5)
            f_seconds=$(echo "$line" | cut -d '|' -f6)

            #player must be non-empty, level must be easy/hard/normal, tries and seconds must be whole numbers
            if [[ -z "$f_player" ]] || [[ ! "$f_level" =~ ^(easy|normal|hard)$ ]] || [[ ! "$f_tries" =~ ^[0-9]+$ ]] || [[ ! "$f_seconds" =~ ^[0-9]+$ ]]; then
                ((damaged_count++))
                continue
            fi

            if [[ "$f_player" == "$name" && "$f_level" == "$level" ]]; then
                if [[ -z "$old_best" ]] || (( f_tries < old_best )); then
                    old_best=$f_tries
                fi
            fi
        done < "$log_file"
    fi

    #show the warning if any broken lines exist
    if (( damaged_count > 0 )); then
        echo "Warning: $damaged_count damaged line(s) were found and skipped"
    fi

    local guess=-1
    local count=0
    local start_time start_sec end_time end_second duration number

    start_time=$(date '+%Y-%m-%d %H:%M:%S')
    start_sec=$(date +%s)
    number=$(( RANDOM % max + min ))

    echo ""
    while (( guess != number )); do
        read -r -p "Please guess a number between $min and $max (or 'q' to quit round): " guess

        if [[ "${guess,,}" == "q" ]]; then
            echo "Round cancelled."
            return
        fi

        if [[ ! "$guess" =~ ^[0-9]+$ ]]; then
            echo "Please enter a valid number."
            guess=-1
            continue
        fi

        ((count++))

        if (( guess > number )); then
            echo "Your guess is higher than the number"
        elif (( guess < number )); then
            echo "Your guess is lower than the number"
        fi
    done

    end_time=$(date '+%Y-%m-%d %H:%M:%S')
    end_second=$(date +%s)
    duration=$(( end_second - start_sec ))

    #write exact 6-field format: player|level|start|end|tries|seconds
    echo "${name}|${level}|${start_time}|${end_time}|${count}|${duration}" >> "$log_file"

    echo ""
    echo "Performance summary"
    if [[ -z "$old_best" ]]; then
        echo "First time playing $level level! Record saved"
    elif (( count < old_best )); then
        echo "New personal best for $level level!"
    else
        echo "Your personal best of $level level is still $old_best tries."
    fi
    echo "Congratulations!! you guessed correctly after trying $count number time(s)"
}

echo "=========================="
echo "Hi $name, Welcome to our guessing game."
echo "==========================="

while true; do
    echo ""
    echo "Menu:"
    echo "  1) Play"
    echo "  2) My History"
    echo "  3) Leaderboard ($level)"
    echo "  4) Delete My History"
    echo "  q) Quit"
    read -r -p "Choose an option: " choice

    case "${choice,,}" in
        1) play_game ;;
        2) show_history ;;
        3) show_leaderboard ;;
        4) delete_history ;;
        q)
            echo "Goodbye, $name!"
            exit 0
            ;;
        *)
            echo "Invalid option. Please choose 1, 2, 3, 4, or q."
            ;;
    esac
done
