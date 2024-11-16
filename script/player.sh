#!/bin/bash

# Check if playerctl is installed
if ! command -v playerctl &> /dev/null; then
    echo "playerctl is not installed. Please install it first."
    echo "On Ubuntu/Debian: sudo apt install playerctl"
    echo "On Fedora: sudo dnf install playerctl"
    echo "On Arch: sudo pacman -S playerctl"
    exit 1
fi

# Function to cleanup on exit
cleanup() {
    echo -e "\033[?25h"  # Show cursor
    stty echo            # Restore echo
    exit 0
}

trap cleanup EXIT INT TERM

# Function to format time (convert seconds to MM:SS)
format_time() {
    local time=${1%.*}  # Remove decimal part
    printf "%02d:%02d" $((time/60)) $((time%60))
}

# Function to draw a simple progress bar
draw_progress_bar() {
    local position=$1
    local length=$2
    local bar_width=40  # Width of the progress bar
    local progress=$(echo "scale=2; $position / $length" | bc)  # Percentage of progress
    
    # Calculate the number of '#' characters
    local filled_length=$(echo "scale=0; $progress * $bar_width / 1" | bc)
    local empty_length=$((bar_width - filled_length))
    
    # Create the progress bar
    local progress_bar=$(printf "%${filled_length}s" | tr ' ' '-')  # Filled part
    local empty_bar=$(printf "%${empty_length}s" | tr ' ' ' ')  # Empty part

    # Output the progress bar and percentage, overwrite the line using \r
    # The `\r` returns the cursor to the beginning of the line.
    printf "\r[${progress_bar}${empty_bar}] %3d%%" "$(echo "$progress * 100" | bc | cut -d'.' -f1)"
}

# Function to truncate strings with ellipsis if they exceed a certain length
truncate_string() {
    local str="$1"
    local length="$2"
    if [ ${#str} -gt $length ]; then
        echo "${str:0:$length}.."
    else
        echo "$str"
    fi
}

# Hide cursor and disable echo
echo -e "\033[?25l"
stty -echo

# Main loop
while true; do
    # Move cursor to the top-left corner instead of clearing the screen
    echo -e "\033[H"

    # Check if any player is running and playing
    if playerctl metadata &>/dev/null; then
        # Get current track information
        status=$(playerctl status 2>/dev/null)
        artist=$(playerctl metadata artist 2>/dev/null)
        title=$(playerctl metadata title 2>/dev/null)
        
        # Get position and length with error checking
        position=$(playerctl position 2>/dev/null || echo "0")
        # Convert length from microseconds to seconds
        length=$(playerctl metadata mpris:length 2>/dev/null | awk '{printf "%.0f", $1/1000000}' || echo "0")
        
        # Display track info
        echo -e "\033[1mNow Playing\033[0m"
        echo "_______________________________________________
_______________________________________________
                                                            "
        echo -e "Status: \033[1m$status\033[0m"
        echo -e "Artist: \033[1m$(truncate_string "$artist" 30)\033[0m"  # Truncate artist name if too long
        echo -e "Title:  \033[1m$(truncate_string "$title" 30)\033[0m"  # Truncate title if too long
        
        # Only show position and length time if we have valid data
        if [[ -n "$position" && -n "$length" && "$length" != "0" ]]; then
            echo -e "\nTime: $(format_time "$position") / $(format_time "$length")"
            # Draw progress bar
            draw_progress_bar "$position" "$length"
        fi
    else
        echo "No media player is active"
    fi
    
    echo -e "\n_______________________________________________
_______________________________________________
                                               "
    echo " [sp]Play/Pause [N]Next [P]Previous [Q]Quit"
    echo "
_______________________________________________
_______________________________________________"
    
    # Non-blocking read with shorter timeout
    read -t 0.1 -N 1 key
    
    case "$key" in
        " ") playerctl play-pause 2>/dev/null ;;
        "n") playerctl next 2>/dev/null ;;
        "p") playerctl previous 2>/dev/null ;;
        "+") playerctl volume 0.1+ 2>/dev/null ;;
        "-") playerctl volume 0.1- 2>/dev/null ;;
        "q") break ;;
    esac
    
    # Shorter sleep for smoother updates
    sleep 0.1
done

cleanup

