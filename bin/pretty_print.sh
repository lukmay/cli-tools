#!/bin/bash
# pretty_print.sh v0.0.2
#
# This script prints the content of text files based on specified criteria.
# It allows users to specify multiple input paths, exclude specific paths,
# filter by file extension, and control handling of hidden files.
#
# Features:
#   - Specify multiple input paths (files or directories)
#   - Recursively process directories
#   - Exclude specific paths (files or directories)
#   - Filter by file extension (whitelist or blacklist mode)
#   - Control handling of hidden files/folders
#
# Usage examples:
#   ./pretty_print.sh .                                     # Process current directory
#   ./pretty_print.sh file1.py dir1 dir2/file.js            # Process specific files and directories
#   ./pretty_print.sh . --exclude=node_modules,build,*.log  # Exclude specific paths
#   ./pretty_print.sh . --whitelist=py,js,md                # Only include specific extensions
#   ./pretty_print.sh . --blacklist=json,svg,png            # Exclude specific extensions
#   ./pretty_print.sh . --no-hidden                         # Exclude hidden files/folders
#   ./pretty_print.sh . --max-lines=2000                    # Set maximum allowed lines
#
# Usage in WSL -> Windows clipboard:
#   ./pretty_print.sh . --whitelist=py,js | clip.exe

# Disable pathname expansion so patterns like *.log aren't expanded by the shell
set -f

#---------------------------------
# Default configuration
#---------------------------------
MAX_LINE_COUNT=1000
PROCESS_HIDDEN=true
PRINT_STRUCTURE=true
PRINT_FULL_STRUCTURE=false
DEBUG_MODE=false
INCLUDE_BINARY=false
USE_ASCII=true  # Use ASCII characters for tree structure by default

# List of file extensions considered binary
# Edit this list to customize what's considered binary
BINARY_EXTENSIONS=(
    "pdf" "png" "jpg" "jpeg" "gif" "bmp" "ico" "svg" "webp"
    "mp3" "mp4" "wav" "ogg" "flac" "avi" "mov" "mkv" "wmv"
    "zip" "tar" "gz" "bz2" "xz" "7z" "rar"
    "exe" "dll" "so" "dylib" "class" "pyc" "pyo" 
    "o" "obj" "a" "lib" "bin"
)

#---------------------------------
# Help and debug functions
#---------------------------------
print_usage() {
    echo "Usage: $0 [OPTIONS] [PATH...]"
    echo
    echo "Options:"
    echo "  --exclude=PATH1,PATH2,...    Exclude specific paths (files or directories)"
    echo "                               Also accepts directory paths ending with / (tab-completion friendly)"
    echo "  --whitelist=EXT1,EXT2,...    Only include files with specified extensions"
    echo "  --blacklist=EXT1,EXT2,...    Exclude files with specified extensions"
    echo "  --no-hidden                  Exclude hidden files and directories"
    echo "  --include-binary             Include binary files (disabled by default)"
    echo "  --max-lines=NUM              Set maximum allowed lines (default: 1000)"
    echo "  --print-full-structure       Print the entire file structure"
    echo "  --no-structure               Don't print file structure at all"
    echo "  --utf8                       Use UTF-8 characters in tree structure (default: ASCII)"
    echo "  --debug                      Show debug information"
    echo "  --help                       Display this help message and exit"
    echo
    echo "Examples:"
    echo "  $0 .                                     # Process current directory"
    echo "  $0 file1.py dir1 dir2/file.js            # Process specific files and directories"
    echo "  $0 . --exclude=node_modules,build,*.log  # Exclude specific paths"
    echo "  $0 . --whitelist=py,js,md                # Only include specific extensions"
    echo "  $0 . --blacklist=json,svg,png            # Exclude specific extensions"
    echo "  $0 . --print-full-structure              # Print full file structure"
    echo "  $0 . --no-structure                      # Don't print file structure"
    exit 1
}

debug_print() {
    if [ "$DEBUG_MODE" = true ]; then
        echo "DEBUG: $1" >&2
    fi
}

#---------------------------------
# Utility functions
#---------------------------------
# Function to remove trailing slashes from paths (except for root directory)
normalize_path() {
    local path="$1"
    if [[ "$path" != "/" ]]; then
        path="${path%/}"
    fi
    echo "$path"
}

# Split comma-separated values into an array
parse_csv_to_array() {
    local input="$1"
    local array=()
    
    if [ -z "$input" ]; then
        echo ""
        return
    fi
    
    # Handle comma-separated values
    IFS=',' read -ra array <<< "$input"
    
    # Filter out empty values
    for item in "${array[@]}"; do
        if [ -n "$item" ]; then
            echo "$item"
        fi
    done
}

#---------------------------------
# Filter functions
#---------------------------------
# Check if path is hidden
is_hidden() {
    local path="$1"
    local rel_path="${path#./}"
    
    # Check for folders starting with "__" (like __pycache__)
    if [[ "$rel_path" == __*/ || "$rel_path" == __* || "$rel_path" == */__* ]]; then
        return 0  # Treat as hidden
    fi
    
    # Check each component in the path
    while [[ "$rel_path" == */* ]]; do
        local dir="${rel_path%%/*}"
        if [[ "$dir" == .* && "$dir" != "." && "$dir" != ".." ]]; then
            return 0  # Hidden
        fi
        rel_path="${rel_path#*/}"
    done
    
    # Check the filename itself
    if [[ "$rel_path" == .* && "$rel_path" != "." && "$rel_path" != ".." ]]; then
        return 0  # Hidden
    fi
    
    return 1  # Not hidden
}

# Check if a file is binary based on extension
is_binary() {
    local file="$1"
    
    # Files with no extension are considered binary
    if [[ ! "$file" =~ \.[^./]+$ ]]; then
        debug_print "File with no extension considered binary: $file"
        return 0  # Is binary
    fi
    
    # Extract extension
    local ext=""
    if [[ "$file" =~ \.([^./]+)$ ]]; then
        ext="${BASH_REMATCH[1]}"
        ext="${ext,,}"  # Convert to lowercase
    fi
    
    # Check if extension is in binary list
    for bin_ext in "${BINARY_EXTENSIONS[@]}"; do
        if [[ "$ext" == "$bin_ext" ]]; then
            debug_print "File with binary extension: $file ($ext)"
            return 0  # Is binary
        fi
    done
    
    return 1  # Not binary
}

# Check if a path matches an exclusion pattern
path_matches_pattern() {
    local path="$1"
    local pattern="$2"
    
    # Normalize both paths
    path="$(normalize_path "$path")"
    pattern="$(normalize_path "$pattern")"
    
    # Check for simple directory/path match
    if [[ "$path" == "$pattern" || "$path" == "$pattern"/* ]]; then
        return 0  # Match
    fi
    
    # Convert glob pattern to regex
    if [[ "$pattern" == *"*"* || "$pattern" == *"?"* ]]; then
        # Escape dots and convert glob to regex
        local regex="${pattern//\./\\.}"
        regex="${regex//\*/.*}"
        regex="${regex//\?/.}"
        
        # Match against regex
        if [[ "$path" =~ ^$regex$ || "$path" =~ ^$regex/ || "$path" =~ /$regex/ || "$path" =~ /$regex$ ]]; then
            return 0  # Match
        fi
    fi
    
    return 1  # No match
}

# Check if a path should be excluded
is_excluded() {
    local path="$1"
    local rel_path="${path#./}"
    
    for excl in "${EXCLUSIONS[@]}"; do
        if path_matches_pattern "$rel_path" "$excl"; then
            debug_print "Excluding due to pattern match: $path matches $excl"
            return 0  # Exclude
        fi
        
        # Special case for __pycache__
        if [[ "$excl" == "__pycache__" && ("$rel_path" == "__pycache__" || "$rel_path" == *"/__pycache__"* || "$rel_path" == "__pycache__"/*) ]]; then
            debug_print "Excluding __pycache__ folder: $path"
            return 0  # Exclude
        fi
    done
    
    return 1  # Don't exclude
}

# Check if file extension passes filters
passes_extension_filter() {
    local file="$1"
    
    # Extract extension without the dot
    local ext=""
    if [[ "$file" =~ \.([^./]+)$ ]]; then
        ext="${BASH_REMATCH[1]}"
        ext="${ext,,}"  # Convert to lowercase
    else
        # No extension
        if [ ${#WHITELIST[@]} -gt 0 ]; then
            debug_print "No extension on $file, fails whitelist"
            return 1  # Fail (no extension = not in whitelist)
        fi
        # In blacklist mode, a file with no extension passes
        return 0
    fi
    
    # Whitelist check
    if [ ${#WHITELIST[@]} -gt 0 ]; then
        for allowed in "${WHITELIST[@]}"; do
            allowed="${allowed,,}"  # Convert to lowercase
            if [[ "$ext" == "$allowed" ]]; then
                return 0  # Pass
            fi
        done
        debug_print "Failed whitelist: $file ($ext) not in [${WHITELIST[*]}]"
        return 1  # Fail (not in whitelist)
    fi
    
    # Blacklist check
    if [ ${#BLACKLIST[@]} -gt 0 ]; then
        for disallowed in "${BLACKLIST[@]}"; do
            disallowed="${disallowed,,}"  # Convert to lowercase
            if [[ "$ext" == "$disallowed" ]]; then
                debug_print "Failed blacklist: $file ($ext) is in [${BLACKLIST[*]}]"
                return 1  # Fail (in blacklist)
            fi
        done
    fi
    
    # Pass by default
    return 0
}

# Check if a file should be included in the output
should_include_file() {
    local file="$1"
    local explicit="$2"
    
    # Skip if file doesn't exist or isn't readable
    if [ ! -f "$file" ] || [ ! -r "$file" ]; then
        debug_print "Skipping unreadable file: $file"
        return 1
    fi
    
    # First priority: Exclusions (even for explicit files)
    if is_excluded "$file"; then
        return 1
    fi
    
    # Explicit files bypass other filters
    if [ "$explicit" = "true" ]; then
        return 0
    fi
    
    # Skip hidden files if configured
    if [ "$PROCESS_HIDDEN" = false ] && is_hidden "$file"; then
        debug_print "Skipping hidden file: $file"
        return 1
    fi
    
    # Skip binary files if configured
    if [ "$INCLUDE_BINARY" = false ] && is_binary "$file"; then
        debug_print "Skipping binary file: $file"
        return 1
    fi
    
    # Apply extension filter
    if ! passes_extension_filter "$file"; then
        return 1
    fi
    
    # Check line count
    local line_count
    line_count=$(wc -l < "$file" 2>/dev/null || echo 0)
    if [ "$line_count" -gt "$MAX_LINE_COUNT" ]; then
        debug_print "Skipping file exceeding MAX_LINE_COUNT: $file ($line_count > $MAX_LINE_COUNT)"
        return 1
    fi
    
    # All checks passed
    return 0
}

#---------------------------------
# File collection and processing
#---------------------------------
# Get a list of files to process
collect_files() {
    local output_file="$1"
    
    # Create an empty file first (in case we don't find any matches)
    > "$output_file"
    
    for target in "${TARGETS[@]}"; do
        debug_print "Processing target: $target"
        
        if [ -f "$target" ]; then
            # Single file target
            if should_include_file "$target" "true"; then
                echo "${target#./}" >> "$output_file"
                debug_print "Including file: ${target#./}"
            fi
        elif [ -d "$target" ]; then
            # Directory target - find all files recursively
            debug_print "Recursively processing directory: $target"
            
            # Check if we have permission to read the directory
            if [ ! -r "$target" ]; then
                echo "Warning: Cannot read directory $target (permission denied)" >&2
                continue
            fi
            
            # Find all files, handling errors
            find "$target" -type f -print0 2>/dev/null | while IFS= read -r -d '' file; do
                if should_include_file "$file" "false"; then
                    echo "${file#./}" >> "$output_file"
                    debug_print "Including file: ${file#./}"
                fi
            done
        else
            echo "Warning: Target not found: $target" >&2
        fi
    done
    
    # Sort the file list for consistent output
    if [ -s "$output_file" ]; then
        # Create a temporary file for sorting
        temp_sort=$(mktemp)
        sort "$output_file" > "$temp_sort"
        mv "$temp_sort" "$output_file"
    fi
}

# Process a file and append to output
process_file() {
    local file="$1"
    local output_file="$2"
    
    # Extract extension for code block
    local extension=""
    if [[ "$file" =~ \.([^./]+)$ ]]; then
        extension="${BASH_REMATCH[1]}"
    fi
    
    {
        # echo "~~~~~~~~~~~~~~~~"
        echo "Path: $file"
        echo "\`\`\`$extension"
        echo

        # Output file content
        if ! cat "$file" 2>/dev/null; then
            echo "Error: Unable to read file $file"
        fi
        
	echo
        echo "\`\`\`"
        # echo "~~~~~~~~~~~~~~~~"
        echo
        echo
        echo
    } >> "$output_file"
}

#---------------------------------
# File structure display
#---------------------------------
# Print directory structure in markdown format
print_structure() {
    local base_dir="$1"
    local included_files="$2"  # File containing list of included files
    local prefix="$3"
    local is_last_item="$4"
    local use_ascii="${5:-false}"  # Whether to use ASCII instead of UTF-8
    
    # Skip excluded directories
    if is_excluded "$base_dir"; then
        return
    fi
    
    # Skip hidden directories if configured
    if [ "$PROCESS_HIDDEN" = false ] && is_hidden "$base_dir"; then
        return
    fi
    
    # Get all entries in the directory
    local dirs=()
    local files=()
    
    # Make sure the directory exists and is readable
    if [ ! -d "$base_dir" ] || [ ! -r "$base_dir" ]; then
        return
    fi
    
    # Find all entries in this directory
    while IFS= read -r -d '' entry; do
        local entry_name="${entry##*/}"
        
        # Skip excluded entries
        if is_excluded "$entry"; then
            continue
        fi
        
        # Skip hidden entries if configured
        if [ "$PROCESS_HIDDEN" = false ] && is_hidden "$entry"; then
            continue
        fi
        
        if [ -d "$entry" ]; then
            # Check if this directory contains any included files
            local dir_has_files=false
            if [ "$PRINT_FULL_STRUCTURE" = true ]; then
                dir_has_files=true
            else
                # Check if any included files are in this directory
                while IFS= read -r included_file; do
                    if [[ "$included_file" == "${entry#./}"/* || "$included_file" == "${entry#./}" ]]; then
                        dir_has_files=true
                        break
                    fi
                done < "$included_files"
            fi
            
            if [ "$dir_has_files" = true ]; then
                dirs+=("$entry_name")
            fi
        elif [ -f "$entry" ]; then
            # Include file if it's in the included_files list or if we're showing all files
            if [ "$PRINT_FULL_STRUCTURE" = true ] || grep -q "^${entry#./}$" "$included_files" 2>/dev/null; then
                files+=("$entry_name")
            fi
        fi
    done < <(find "$base_dir" -mindepth 1 -maxdepth 1 -print0 2>/dev/null | sort -z)
    
    # Skip empty directories when not printing full structure
    if [ "$PRINT_FULL_STRUCTURE" = false ] && [ ${#dirs[@]} -eq 0 ] && [ ${#files[@]} -eq 0 ]; then
        return
    fi
    
    # Set up symbols based on ASCII or UTF-8
    local t_branch="├── "
    local l_branch="└── "
    local v_line="│   "
    local empty="    "
    local folder_icon="📁"
    
    # Use ASCII if requested
    if [ "$use_ascii" = "true" ]; then
        t_branch="|-- "
        l_branch="\`-- "  # Escaped backtick
        v_line="|   "
        empty="    "
        folder_icon="+"
    fi
    
    # Print current directory name (except for the root directory when it's '.')
    if [ "$base_dir" != "." ] || [ "$PRINT_FULL_STRUCTURE" = true ]; then
        local display_name="${base_dir##*/}"
        if [ "$display_name" = "" ]; then
            display_name="/"
        fi
        
        # Determine the symbol to use based on whether this is the last item
        local symbol="$t_branch"
        if [ "$is_last_item" = "true" ]; then
            symbol="$l_branch"
        fi
        
        # Don't show prefix+symbol for the root directory when printing just '.'
        if [ "$base_dir" = "." ] && [ "$prefix" = "" ]; then
            if [ "$use_ascii" = "true" ]; then
                echo "Project Structure"
            else
                echo "📁 **Project Structure**"
            fi
        else
            if [ "$use_ascii" = "true" ]; then
                echo "${prefix}${symbol}${display_name}/"
            else
                echo "${prefix}${symbol}${folder_icon} **${display_name}/**"
            fi
        fi
    fi
    
    # Prepare prefix for children
    local new_prefix="$prefix"
    if [ "$is_last_item" = "true" ]; then
        new_prefix="${prefix}${empty}"
    else
        new_prefix="${prefix}${v_line}"
    fi
    
    # If current dir is '.', don't modify the prefix
    if [ "$base_dir" = "." ] && [ "$prefix" = "" ]; then
        new_prefix=""
    fi
    
    # Print directories first, then files
    local dir_count=${#dirs[@]}
    local file_count=${#files[@]}
    local total_items=$((dir_count + file_count))
    local item_index=0
    
    for dir in "${dirs[@]}"; do
        item_index=$((item_index + 1))
        local dir_is_last="false"
        if [ $item_index -eq $total_items ]; then
            dir_is_last="true"
        fi
        
        local full_path
        if [ "$base_dir" = "." ]; then
            full_path="$dir"
        else
            full_path="$base_dir/$dir"
        fi
        
        print_structure "$full_path" "$included_files" "$new_prefix" "$dir_is_last" "$use_ascii"
    done
    
    # Print files
    for file in "${files[@]}"; do
        item_index=$((item_index + 1))
        local file_is_last="false"
        if [ $item_index -eq $total_items ]; then
            file_is_last="true"
        fi
        
        local symbol="$t_branch"
        if [ "$file_is_last" = "true" ]; then
            symbol="$l_branch"
        fi
        
        # Default file icon or ASCII equivalent
        local file_icon="📄"
        if [ "$use_ascii" = "true" ]; then
            file_icon="-"
        fi
        
        # Determine file icon based on extension
        if [ "$use_ascii" = "false" ]; then
            case "$file" in
                *.sh|*.bash|*.zsh|*.fish)
                    file_icon="📜"  # Script
                    ;;
                *.py)
                    file_icon="🐍"  # Python
                    ;;
                *.js|*.jsx|*.ts|*.tsx)
                    file_icon="📊"  # JavaScript/TypeScript
                    ;;
                *.html|*.htm)
                    file_icon="🌐"  # HTML
                    ;;
                *.css|*.scss|*.sass|*.less)
                    file_icon="🎨"  # CSS
                    ;;
                *.json|*.xml|*.yaml|*.yml)
                    file_icon="🔧"  # Config
                    ;;
                *.md|*.markdown|*.txt)
                    file_icon="📝"  # Markdown/Text
                    ;;
                *.c|*.cpp|*.h|*.hpp|*.go|*.rs|*.java)
                    file_icon="🔨"  # Compiled language
                    ;;
                *.git*|.gitignore)
                    file_icon="🔄"  # Git-related
                    ;;
                *)
                    file_icon="📄"  # Default
                    ;;
            esac
        fi
        
        echo "${new_prefix}${symbol}${file_icon} ${file}"
    done
}

#---------------------------------
# Main script processing
#---------------------------------
# Parse command-line arguments
TARGETS=()
EXCLUSIONS=()
WHITELIST=()
BLACKLIST=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --exclude=*|-e=*)
            # Get value after equals sign
            value="${1#*=}"
            if [ -n "$value" ]; then
                # Add each non-empty item to EXCLUSIONS
                while IFS= read -r item; do
                    if [ -n "$item" ]; then
                        EXCLUSIONS+=("$item")
                    fi
                done < <(parse_csv_to_array "$value")
            fi
            shift
            ;;
        --exclude|-e)
            # Process next argument if it doesn't start with --
            if [[ $# -gt 1 && ! "$2" =~ ^-- ]]; then
                # Add each non-empty item to EXCLUSIONS
                while IFS= read -r item; do
                    if [ -n "$item" ]; then
                        EXCLUSIONS+=("$item")
                    fi
                done < <(parse_csv_to_array "$2")
                shift 2
            else
                echo "Error: Missing value for --exclude" >&2
                print_usage
            fi
            ;;
        --whitelist=*|-w=*)
            value="${1#*=}"
            if [ -n "$value" ]; then
                while IFS= read -r item; do
                    if [ -n "$item" ]; then
                        WHITELIST+=("$item")
                    fi
                done < <(parse_csv_to_array "$value")
            fi
            shift
            ;;
        --whitelist|-w)
            if [[ $# -gt 1 && ! "$2" =~ ^-- ]]; then
                while IFS= read -r item; do
                    if [ -n "$item" ]; then
                        WHITELIST+=("$item")
                    fi
                done < <(parse_csv_to_array "$2")
                shift 2
            else
                echo "Error: Missing value for --whitelist" >&2
                print_usage
            fi
            ;;
        --blacklist=*|-b=*)
            value="${1#*=}"
            if [ -n "$value" ]; then
                while IFS= read -r item; do
                    if [ -n "$item" ]; then
                        BLACKLIST+=("$item")
                    fi
                done < <(parse_csv_to_array "$value")
            fi
            shift
            ;;
        --blacklist|-b)
            if [[ $# -gt 1 && ! "$2" =~ ^-- ]]; then
                while IFS= read -r item; do
                    if [ -n "$item" ]; then
                        BLACKLIST+=("$item")
                    fi
                done < <(parse_csv_to_array "$2")
                shift 2
            else
                echo "Error: Missing value for --blacklist" >&2
                print_usage
            fi
            ;;
        --no-hidden)
            PROCESS_HIDDEN=false
            shift
            ;;
        --include-binary)
            INCLUDE_BINARY=true
            shift
            ;;
        --max-lines=*)
            MAX_LINE_COUNT="${1#*=}"
            shift
            ;;
        --max-lines)
            if [[ $# -gt 1 && ! "$2" =~ ^-- ]]; then
                MAX_LINE_COUNT="$2"
                shift 2
            else
                echo "Error: Missing value for --max-lines" >&2
                print_usage
            fi
            ;;
        --print-full-structure)
            PRINT_STRUCTURE=true
            PRINT_FULL_STRUCTURE=true
            shift
            ;;
        --no-structure)
            PRINT_STRUCTURE=false
            shift
            ;;
        --utf8)
            USE_ASCII=false
            shift
            ;;
        --debug)
            DEBUG_MODE=true
            shift
            ;;
        --help)
            print_usage
            ;;
        -*)
            echo "Unknown option: $1" >&2
            print_usage
            ;;
        *)
            TARGETS+=("$1")
            shift
            ;;
    esac
done

# If no targets specified, use current directory
if [ ${#TARGETS[@]} -eq 0 ]; then
    TARGETS=(".")
fi

# Check if both whitelist and blacklist are specified
if [ ${#WHITELIST[@]} -gt 0 ] && [ ${#BLACKLIST[@]} -gt 0 ]; then
    echo "Error: Cannot specify both whitelist and blacklist" >&2
    exit 1
fi

# Print debug information if enabled
if [ "$DEBUG_MODE" = true ]; then
    echo "DEBUG: Targets: ${TARGETS[*]}" >&2
    echo "DEBUG: Exclusions: ${EXCLUSIONS[*]}" >&2
    echo "DEBUG: Whitelist: ${WHITELIST[*]}" >&2
    echo "DEBUG: Blacklist: ${BLACKLIST[*]}" >&2
    echo "DEBUG: Process hidden: $PROCESS_HIDDEN" >&2
    echo "DEBUG: Include binary: $INCLUDE_BINARY" >&2
    echo "DEBUG: Print structure: $PRINT_STRUCTURE" >&2
    echo "DEBUG: Print full structure: $PRINT_FULL_STRUCTURE" >&2
    echo "DEBUG: Use ASCII: $USE_ASCII" >&2
    echo "DEBUG: Max line count: $MAX_LINE_COUNT" >&2
    echo "DEBUG: Binary extensions: ${BINARY_EXTENSIONS[*]}" >&2
fi

# Create temporary files for processing
files_list=$(mktemp)
output_file=$(mktemp)

# Step 1: Collect all files that pass filters
collect_files "$files_list"

# Debug: Show list of files that passed filters
if [ "$DEBUG_MODE" = true ]; then
    echo "DEBUG: Files to process:" >&2
    cat "$files_list" >&2
    # Count files
    file_count=$(wc -l < "$files_list" 2>/dev/null || echo 0)
    echo "DEBUG: Found $file_count files matching criteria" >&2
fi

# Exit early if no files were found
if [ ! -s "$files_list" ] && [ "$DEBUG_MODE" = true ]; then
    echo "DEBUG: No files matched the criteria. Check your filters and paths." >&2
fi

# Step 2: Process each file
while IFS= read -r file; do
    process_file "$file" "$output_file"
done < "$files_list"

# Step 3: Print file structure if enabled
if [ "$PRINT_STRUCTURE" = true ]; then
    structure_output=$(mktemp)
    
    # Check if we have any files to display
    if [ -s "$files_list" ]; then
        {
            echo "# File Structure"
            echo
            print_structure "." "$files_list" "" "false" "$USE_ASCII"
            echo
            echo "---"
            echo
            echo "# File Contents"
            echo
        } > "$structure_output"
    else
        # No files to display
        echo "# No files matched the specified criteria" > "$structure_output"
    fi
    
    # Output structure followed by file contents
    cat "$structure_output" "$output_file"
    rm "$structure_output"
else
    # Output just file contents
    if [ -s "$output_file" ]; then
        cat "$output_file"
    else
        echo "No files matched the specified criteria"
    fi
fi

# Clean up temporary files
rm "$files_list"
rm "$output_file"
