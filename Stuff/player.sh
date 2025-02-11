#!/bin/bash

# Configuration
VOLUME_STEP=5           # Volume change step size
MAX_VOLUME=100         # Maximum allowed volume
MIN_VOLUME=0          # Minimum allowed volume
CONFIG_DIR="$HOME/.config/modern-audio-controller"
CONFIG_FILE="$CONFIG_DIR/config"

if [ "$1" = "--player" ]; then
    
    echo -en "\033]0;Modern Audio Controller\007"
    
    # Dependencies check
    dependencies=("dialog" "pactl" "playerctl" "grep" "awk" "sed")
    missing_deps=()
    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing_deps+=("$dep")
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo "Error: The following dependencies are missing:"
        printf '%s\n' "${missing_deps[@]}"
        exit 1
    fi

    # Terminal colors
    BLUE='\033[38;5;75m'    # Light blue like in screenshot
    RED='\033[38;5;203m'    # Soft red
    YELLOW='\033[38;5;221m' # Warm yellow
    WHITE='\033[97m'        # Bright white
    GRAY='\033[38;5;242m'   # Dim text
    NC='\033[0m'

    # Cursor movement
    SAVE_CURSOR='\033[s'
    RESTORE_CURSOR='\033[u'
    CLEAR_LINE='\033[2K'
    MOVE_UP='\033[1A'
    HIDE_CURSOR='\033[?25l'
    SHOW_CURSOR='\033[?25h'

    # Global variables
    VOLUME=0
    PLAYING=false
    CURRENT_SINK=""
    IS_MUTED=false
    LAST_TRACK_CHANGE=0  
    TERMINAL_WIDTH=$(tput cols)
    MAX_TITLE_LENGTH=50
    VOLUME_LINE=4    
    STATUS_LINE=7    
    SINK_LINE=8     

    # Save terminal settings
    ORIGINAL_STTY=$(stty -g)

    # Get current volume
    get_current_volume() {
        VOLUME=$(pactl get-sink-volume @DEFAULT_SINK@ | grep -Po '\d+(?=%)' | head -n1)
    }

    # Truncate text with ellipsis
    truncate_text() {
        local text="$1"
        local max_length="$2"
        if [ ${#text} -gt $max_length ]; then
            echo "${text:0:$((max_length-3))}..."
        else
            echo "$text"
        fi
    }

    # Get default sink
    get_default_sink() {
        CURRENT_SINK=$(pactl get-default-sink)
        CURRENT_SINK=$(truncate_text "$CURRENT_SINK" 30)
    }

    # Set volume and update display
    set_volume() {
        local vol=$1
        pactl set-sink-volume @DEFAULT_SINK@ ${vol}%
    }

    # Update volume display without clearing screen
    update_volume_display() {
        # Move to volume line and clear it
        echo -en "\033[${VOLUME_LINE}H${CLEAR_LINE}"
        show_volume_bar
    }

    # Update status display without clearing screen
    update_status_display() {
        local title_info="$(get_track_info)"
        # Clear and update status line
        echo -en "\033[${STATUS_LINE}H${CLEAR_LINE}"
        echo -e "    ■ ${title_info}"
        echo -en "\033[${SINK_LINE}H${CLEAR_LINE}"
        echo -e "    ♪ ${GRAY}Output:${NC} ${WHITE}$CURRENT_SINK${NC}"
    }

    # Toggle play/pause
    toggle_play() {
        playerctl play-pause
        PLAYING=!$PLAYING
    }

    # Toggle mute
    toggle_mute() {
        pactl set-sink-mute @DEFAULT_SINK@ toggle
        IS_MUTED=$(pactl get-sink-mute @DEFAULT_SINK@ | grep -q "yes" && echo true || echo false)
        update_volume_display
    }

    # Volume up with error handling
    volume_up() {
        if [ $VOLUME -lt $MAX_VOLUME ]; then
            VOLUME=$((VOLUME + VOLUME_STEP))
            [ $VOLUME -gt $MAX_VOLUME ] && VOLUME=$MAX_VOLUME
            if ! set_volume $VOLUME; then
                echo "Error: Failed to increase volume" >&2
                return 1
            fi
        fi
    }

    # Volume down with error handling
    volume_down() {
        if [ $VOLUME -gt $MIN_VOLUME ]; then
            VOLUME=$((VOLUME - VOLUME_STEP))
            [ $VOLUME -lt $MIN_VOLUME ] && VOLUME=$MIN_VOLUME
            if ! set_volume $VOLUME; then
                echo "Error: Failed to decrease volume" >&2
                return 1
            fi
        fi
    }

    # Get current track info
    get_track_info() {
        local title=$(playerctl metadata title 2>/dev/null)
        local artist=$(playerctl metadata artist 2>/dev/null)
        
        if [ -n "$title" ]; then
            if [ -n "$artist" ]; then
                local full_text="$title - $artist"
                echo -e "${WHITE}$(truncate_text "$full_text" $MAX_TITLE_LENGTH)${NC}"
            else
                echo -e "${WHITE}$(truncate_text "$title" $MAX_TITLE_LENGTH)${NC}"
            fi
        else
            echo -e "${RED}No track playing${NC}"
        fi
    }

    # Show initial volume section
    show_volume() {
        echo -e "    ${GRAY}volume${NC}"
        show_volume_bar
    }

    # Show volume bar
    show_volume_bar() {
        local bars=$((VOLUME / 5))
        echo -ne "    ["
        if [ "$IS_MUTED" = true ]; then
            for ((i=0; i<20; i++)); do
                echo -ne "${RED}▁${NC}"  # Show muted state with red bars
            done
            echo -e "] ${RED}MUTED${NC}"
        else
            for ((i=0; i<20; i++)); do
                if [ $i -lt $bars ]; then
                    echo -ne "${BLUE}▇${NC}"
                else
                    echo -ne "${GRAY}▁${NC}"  # Using bottom line for empty space
                fi
            done
            echo -e "] ${VOLUME}%"
        fi
    }

    # Enhanced track control functions with error handling
    next_track() {
        if ! playerctl next 2>/dev/null; then
            return 1
        fi
        update_status_display
    }

    previous_track() {
        if ! playerctl previous 2>/dev/null; then
            return 1
        fi
        update_status_display
    }

    # Handle player events
    handle_player_events() {
        # Monitor metadata changes with rate limiting
        (
            playerctl --follow --format '{{title}} - {{artist}}' 2>/dev/null | while read -r line; do
                update_status_display
            done
        ) &
        PLAYER_PID=$!
        
        # Monitor volume changes with debouncing
        (
            last_update=0
            pactl subscribe 2>/dev/null | grep --line-buffered "sink" | while read -r line; do
                if [[ $line == *"change"* ]]; then
                    current_time=$(date +%s%N)
                    # Only update if more than 50ms has passed since last update
                    if (( (current_time - last_update) > 50000000 )); then
                        get_current_volume
                        IS_MUTED=$(pactl get-sink-mute @DEFAULT_SINK@ | grep -q "yes" && echo true || echo false)
                        update_volume_display
                        last_update=$current_time
                    fi
                fi
            done
        ) &
        PACTL_PID=$!
        
        trap "kill $PLAYER_PID $PACTL_PID 2>/dev/null" EXIT
    }

    # Draw initial interface
    draw_interface() {
        # Clear screen and hide cursor
        clear
        echo -en "${HIDE_CURSOR}"
        
        # Get initial volume and mute state
        get_current_volume
        IS_MUTED=$(pactl get-sink-mute @DEFAULT_SINK@ | grep -q "yes" && echo true || echo false)
        
        # Draw interface
        echo
        echo -e "    ${BLUE}Modern Audio Controller${WHITE}_${NC}"
        echo
        echo -e "    ${GRAY}volume${NC}"
        show_volume_bar
        echo
        echo -e "    ${GRAY}status${NC}"
        echo -e "    ■ $(get_track_info)"
        echo -e "    ♪ ${GRAY}Output:${NC} ${WHITE}$CURRENT_SINK${NC}"
        echo
        echo -e "    ${GRAY}controls${NC}"
        echo -e "    ${YELLOW}↑/↓${GRAY}    Volume Control"
        echo -e "    ${YELLOW}←/→${GRAY}    Previous/Next Track"
        echo -e "    ${YELLOW}m${GRAY}      Mute/Unmute"
        echo -e "    ${YELLOW}s${GRAY}      Select Audio Source"
        echo -e "    ${YELLOW}q${GRAY}      Quit${NC}"
    }

    # Save current settings
    save_settings() {
        mkdir -p "$CONFIG_DIR"
        {
            echo "VOLUME=$VOLUME"
            echo "VOLUME_STEP=$VOLUME_STEP"
            echo "CURRENT_SINK=$CURRENT_SINK"
        } > "$CONFIG_FILE"
    }

    # Load saved settings
    load_settings() {
        if [ -f "$CONFIG_FILE" ]; then
            source "$CONFIG_FILE"
        fi
    }

    # Enhanced cleanup function
    cleanup_and_exit() {
        # Save settings before exit
        save_settings
        
        # Restore terminal settings
        stty "$ORIGINAL_STTY"
        
        # Kill background processes
        if [ -n "$PLAYER_PID" ]; then
            kill $PLAYER_PID 2>/dev/null
        fi
        if [ -n "$PACTL_PID" ]; then
            kill $PACTL_PID 2>/dev/null
        fi
        
        # Reset terminal
        echo -en "${SHOW_CURSOR}"
        tput cnorm
        clear
        exit 0
    }

    # Main menu with optimized input handling
    main_menu() {
        # Set up cleanup trap for all signals
        trap cleanup_and_exit EXIT INT TERM HUP
        
        # Configure terminal for optimal input handling
        stty -echo -icanon -isig min 1 time 0
        
        # Draw initial interface
        draw_interface
        
        # Start monitoring events
        handle_player_events
        
        # Handle user input with improved buffering
        local key
        local esc_seq
        local input_buffer=""
        
        while true; do
            read -r -n1 key
            
            case "$key" in
                $'\x1b')  # Handle escape sequences (arrow keys)
                    read -r -n2 -t 0.01 esc_seq  # Increased timeout for better reliability
                    case "$esc_seq" in
                        "[A") volume_up ;;        # Up arrow
                        "[B") volume_down ;;      # Down arrow
                        "[D") previous_track ;;   # Left arrow
                        "[C") next_track ;;       # Right arrow
                    esac
                    ;;
                "q"|"Q")
                    cleanup_and_exit
                    break
                    ;;
                "m"|"M")
                    toggle_mute
                    ;;
                "s"|"S")
                    # Show cursor for dialog
                    echo -en "${SHOW_CURSOR}"
                    # Restore terminal settings temporarily
                    stty "$ORIGINAL_STTY"
                    clear
                    
                    # Cache sink list to reduce lag
                    sinks=$(pactl list short sinks | awk '{print $2}')
                    dialog --title "Select Audio Source" --menu "Choose your audio output:" 15 50 5 $(echo "$sinks" | awk '{print NR, $0}') 2>/tmp/sink_choice
                    if [ $? -eq 0 ]; then
                        choice=$(cat /tmp/sink_choice)
                        selected_sink=$(echo "$sinks" | sed -n "${choice}p")
                        pactl set-default-sink "$selected_sink"
                        get_default_sink
                    fi
                    
                    # Clean up temporary file
                    rm -f /tmp/sink_choice
                    
                    # Restore our custom terminal settings
                    stty -echo -icanon -isig min 1 time 0
                    # Redraw and hide cursor
                    draw_interface
                    ;;
            esac
        done
    }

    # Initialize
    get_default_sink
    load_settings  # Load saved settings before starting
    main_menu
else
    # Launch in kitty
    exec kitty \
        --class="modern-audio-controller" \
        --title="Modern Audio Controller" \
        --override "remember_window_size=no" \
        --override "initial_window_width=500" \
        --override "initial_window_height=300" \
        --override "confirm_os_window_close=0" \
        -e "$0" --player 2>/dev/null
    exit 0
fi
