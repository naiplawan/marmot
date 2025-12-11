#!/bin/bash

# Duplicate File Finder for Marmot
# Finds and manages duplicate files efficiently

duplicate_init() {
    # Ensure duplicate directory exists
    mkdir -p "$MARMOT_DUPLICATE_DIR"

    # Initialize duplicate database
    if [[ ! -f "$MARMOT_DUPLICATE_DIR/duplicates.db" ]]; then
        sqlite3 "$MARMOT_DUPLICATE_DIR/duplicates.db" << 'EOF'
CREATE TABLE IF NOT EXISTS file_hashes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_path TEXT UNIQUE,
    file_hash TEXT,
    file_size BIGINT,
    file_modified DATETIME,
    last_scanned DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS duplicate_groups (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    group_hash TEXT UNIQUE,
    file_size BIGINT,
    file_count INTEGER,
    total_size BIGINT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS duplicate_files (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    group_id INTEGER,
    file_path TEXT,
    file_modified DATETIME,
    FOREIGN KEY (group_id) REFERENCES duplicate_groups (id)
);

CREATE INDEX IF NOT EXISTS idx_file_hashes_hash ON file_hashes(file_hash);
CREATE INDEX IF NOT EXISTS idx_file_hashes_size ON file_hashes(file_size);
CREATE INDEX IF NOT EXISTS idx_duplicate_groups_size ON duplicate_groups(file_size);
EOF
    fi
}

# Calculate file hash
duplicate_calculate_hash() {
    local file_path=$1

    # For large files, use fast hash (first 1MB + last 1MB)
    local file_size=$(stat -c%s "$file_path" 2>/dev/null)
    if [[ $? -ne 0 ]]; then
        echo ""
        return 1
    fi

    if [[ $file_size -lt 1048576 ]]; then  # Less than 1MB
        sha256sum "$file_path" 2>/dev/null | cut -d' ' -f1
    else
        # Fast hash for large files
        {
            head -c 1048576 "$file_path"
            tail -c 1048576 "$file_path"
        } 2>/dev/null | sha256sum | cut -d' ' -f1
    fi
}

# Scan directory for duplicates
duplicate_scan() {
    local scan_path=${1:-/}
    local min_file_size=${2:-1K}
    local parallel_jobs=${3:-$(nproc)}

    log "info" "Starting duplicate file scan in $scan_path..."
    log "info" "Minimum file size: $min_file_size"
    log "info" "Using $parallel_jobs parallel jobs"

    # Clear previous scan data
    sqlite3 "$MARMOT_DUPLICATE_DIR/duplicates.db" "DELETE FROM file_hashes;"
    sqlite3 "$MARMOT_DUPLICATE_DIR/duplicates.db" "DELETE FROM duplicate_groups;"
    sqlite3 "$MARMOT_DUPLICATE_DIR/duplicates.db" "DELETE FROM duplicate_files;"

    # Phase 1: Find files and group by size
    local temp_dir=$(mktemp -d)
    local size_groups="$temp_dir/sizes.txt"
    local file_list="$temp_dir/files.txt"

    log "info" "Phase 1: Finding files..."

    # Find all files meeting minimum size
    find "$scan_path" -type f -size +"$min_file_size" -printf "%s\t%p\n" 2>/dev/null | \
    sort -n > "$file_list"

    # Group files by size
    cut -f1 "$file_list" | uniq -c | awk '$1 > 1 {print $2 "\t" $1}' > "$size_groups"

    local total_files=$(wc -l < "$file_list")
    local potential_groups=$(wc -l < "$size_groups")
    local total_size=$(awk '{sum += $1} END {print sum}' "$file_list")

    log "info" "Found $total_files files ($(format_bytes $total_size))"
    log "info" "$potential_groups potential duplicate groups"

    # Phase 2: Calculate hashes for files in size groups
    log "info" "Phase 2: Calculating file hashes..."

    # Process files in parallel
    local processed=0
    while read -r size count; do
        # Extract files of this size
        grep "^$size\t" "$file_list" | cut -f2 > "$temp_dir/group_$size.txt"

        # Process in parallel batches
        xargs -P "$parallel_jobs" -n 10 -a "$temp_dir/group_$size.txt" -I{} \
            bash -c "hash=\$(duplicate_calculate_hash '{}'); \
                     [[ -n \$hash ]] && echo \"\$hash\t$size\t{}\"" \
            >> "$temp_dir/hashes.txt"

        ((processed += count))
        printf "\rProgress: %d/%d groups (%.1f%%)" "$processed" "$potential_groups" \
               "$(echo "scale=1; $processed * 100 / $potential_groups" | bc -l)"
    done < "$size_groups"

    echo ""

    # Phase 3: Group by hash
    log "info" "Phase 3: Grouping duplicates..."

    # Import to database
    sqlite3 "$MARMOT_DUPLICATE_DIR/duplicates.db" << EOF
.mode tabs
.import "$temp_dir/hashes.txt" temp_hashes

-- Create duplicate groups
INSERT INTO duplicate_groups (group_hash, file_size, file_count, total_size)
SELECT file_hash, file_size, COUNT(*), file_size * COUNT(*)
FROM temp_hashes
GROUP BY file_hash, file_size
HAVING COUNT(*) > 1;

-- Link files to groups
INSERT INTO duplicate_files (group_id, file_path, file_modified)
SELECT g.id, t.file_path, t.file_modified
FROM temp_hashes t
JOIN duplicate_groups g ON t.file_hash = g.group_hash;

DROP TABLE temp_hashes;
EOF

    # Clean up temp files
    rm -rf "$temp_dir"

    # Show summary
    local duplicate_groups=$(sqlite3 "$MARMOT_DUPLICATE_DIR/duplicates.db" \
        "SELECT COUNT(*) FROM duplicate_groups;")

    local duplicate_files=$(sqlite3 "$MARMOT_DUPLICATE_DIR/duplicates.db" \
        "SELECT SUM(file_count) FROM duplicate_groups;")

    local wasted_space=$(sqlite3 "$MARMOT_DUPLICATE_DIR/duplicates.db" \
        "SELECT SUM(total_size) FROM duplicate_groups;")

    success "Duplicate scan completed!"
    echo "Found $duplicate_groups duplicate groups"
    echo "Total duplicate files: $duplicate_files"
    echo "Wasted space: $(format_bytes $wasted_space)"
}

# List duplicate files
duplicate_list() {
    local sort_by=${1:-size}  # size, count, path
    local group_only=${2:-false}

    local order_by="total_size DESC"
    case $sort_by in
        count) order_by="file_count DESC" ;;
        path) order_by="MIN(d.file_path)" ;;
    esac

    if $group_only; then
        echo "Duplicate Groups Summary"
        echo "======================="
        echo ""

        sqlite3 "$MARMOT_DUPLICATE_DIR/duplicates.db" << EOF
.headers on
.mode table

SELECT
    dg.group_hash as Hash,
    dg.file_count as Files,
    ROUND(dg.file_size / 1024/1024, 2) || ' MB' as 'File Size',
    ROUND(dg.total_size / 1024/1024/1024, 2) || ' GB' as 'Total Wasted',
    dg.created_at as 'Found'
FROM duplicate_groups dg
ORDER BY $order_by;
EOF
    else
        echo "Duplicate Files Details"
        echo "======================"
        echo ""

        sqlite3 "$MARMOT_DUPLICATE_DIR/duplicates.db" << EOF
.headers on
.mode table

SELECT
    dg.group_hash as Group,
    df.file_path as Path,
    ROUND(dg.file_size / 1024/1024, 2) || ' MB' as Size,
    datetime(df.file_modified) as Modified
FROM duplicate_files df
JOIN duplicate_groups dg ON df.group_id = dg.id
ORDER BY dg.group_hash, df.file_modified DESC;
EOF
    fi
}

# Interactive duplicate management
duplicate_interactive() {
    while true; do
        echo
        echo "Duplicate File Manager"
        echo "===================="
        echo "1) List duplicate groups"
        echo "2) Show files in group"
        echo "3) Select files to keep"
        echo "4) Auto-select (keep newest/oldest)"
        echo "5) Delete selected duplicates"
        echo "6) Move duplicates to folder"
        echo "7) Exit"
        echo
        read -p "Choose an option: " choice

        case $choice in
            1)
                duplicate_list size true
                ;;
            2)
                read -p "Enter group hash: " group_hash
                duplicate_show_group "$group_hash"
                ;;
            3)
                duplicate_select_files
                ;;
            4)
                duplicate_auto_select
                ;;
            5)
                duplicate_delete_selected
                ;;
            6)
                duplicate_move_selected
                ;;
            7)
                break
                ;;
            *)
                echo "Invalid option"
                ;;
        esac
    done
}

# Show files in a duplicate group
duplicate_show_group() {
    local group_hash=$1

    echo "Files in Group: $group_hash"
    echo "==========================="

    sqlite3 "$MARMOT_DUPLICATE_DIR/duplicates.db" << EOF
.headers on
.mode table

SELECT
    df.file_path as Path,
    datetime(df.file_modified) as Modified,
    (SELECT COUNT(*) FROM file_selection fs WHERE fs.file_path = df.file_path) as Selected
FROM duplicate_files df
JOIN duplicate_groups dg ON df.group_id = dg.id
WHERE dg.group_hash = '$group_hash'
ORDER BY df.file_modified DESC;
EOF
}

# Auto-select files to keep
duplicate_auto_select() {
    local strategy=${1:-newest}  # newest, oldest, shortest_path

    echo "Auto-Selection Strategy"
    echo "======================"
    echo "1) Keep newest file"
    echo "2) Keep oldest file"
    echo "3) Keep shortest path"
    echo
    read -p "Choose strategy: " choice

    case $choice in
        1) strategy="newest" ;;
        2) strategy="oldest" ;;
        3) strategy="shortest" ;;
        *) return ;;
    esac

    # Clear previous selections
    sqlite3 "$MARMOT_DUPLICATE_DIR/duplicates.db" "DELETE FROM file_selection;"

    # Create temporary table for selections
    sqlite3 "$MARMOT_DUPLICATE_DIR/duplicates.db" << EOF
CREATE TEMPORARY TABLE IF NOT EXISTS file_selection (
    file_path TEXT PRIMARY KEY
);

-- Auto-select based on strategy
INSERT INTO file_selection
EOF

    case $strategy in
        newest)
            sqlite3 "$MARMOT_DUPLICATE_DIR/duplicates.db" << EOF
INSERT INTO file_selection
SELECT df.file_path
FROM duplicate_files df
JOIN (
    SELECT group_id, MAX(file_modified) as max_modified
    FROM duplicate_files
    GROUP BY group_id
) latest ON df.group_id = latest.group_id AND df.file_modified = latest.max_modified;
EOF
            ;;
        oldest)
            sqlite3 "$MARMOT_DUPLICATE_DIR/duplicates.db" << EOF
INSERT INTO file_selection
SELECT df.file_path
FROM duplicate_files df
JOIN (
    SELECT group_id, MIN(file_modified) as min_modified
    FROM duplicate_files
    GROUP BY group_id
) oldest ON df.group_id = oldest.group_id AND df.file_modified = oldest.min_modified;
EOF
            ;;
        shortest)
            sqlite3 "$MARMOT_DUPLICATE_DIR/duplicates.db" << EOF
INSERT INTO file_selection
SELECT df.file_path
FROM duplicate_files df
JOIN (
    SELECT group_id, MIN(LENGTH(file_path)) as min_length
    FROM duplicate_files
    GROUP BY group_id
) shortest ON df.group_id = shortest.group_id AND LENGTH(df.file_path) = shortest.min_length;
EOF
            ;;
    esac

    success "Auto-selected files to keep using '$strategy' strategy"
}

# Delete selected duplicates
duplicate_delete_selected() {
    local space_freed=0
    local files_deleted=0

    echo "Preparing to delete duplicates..."
    echo "This will permanently delete selected files."
    echo
    read -p "Are you sure? (y/N): " confirm

    if [[ $confirm != [yY] ]]; then
        echo "Cancelled"
        return
    fi

    # Get files to delete (all except selected)
    sqlite3 "$MARMOT_DUPLICATE_DIR/duplicates.db" \
        "SELECT df.file_path, dg.file_size
         FROM duplicate_files df
         JOIN duplicate_groups dg ON df.group_id = dg.id
         LEFT JOIN file_selection fs ON df.file_path = fs.file_path
         WHERE fs.file_path IS NULL;" \
    | while read -r file_path file_size; do
        if [[ -f "$file_path" ]]; then
            # Calculate space before deletion
            local size_before=$(stat -c%s "$file_path" 2>/dev/null || echo 0)

            # Attempt deletion
            if rm -f "$file_path" 2>/dev/null; then
                ((space_freed += size_before))
                ((files_deleted++))
                echo "Deleted: $file_path"
            else
                echo "Failed to delete: $file_path"
            fi
        fi
    done

    success "Deleted $files_files_deleted duplicate files"
    echo "Space freed: $(format_bytes $space_freed)"

    # Update database
    sqlite3 "$MARMOT_DUPLICATE_DIR/duplicates.db" \
        "DELETE FROM duplicate_files
         WHERE file_path NOT IN (SELECT file_path FROM file_selection);"
}

# Move duplicates to folder
duplicate_move_selected() {
    local dest_dir="$MARMOT_DUPLICATE_DIR/duplicates_$(date +%Y%m%d_%H%M%S)"

    echo "This will move all duplicates (except selected) to:"
    echo "$dest_dir"
    echo
    read -p "Continue? (y/N): " confirm

    if [[ $confirm != [yY] ]]; then
        echo "Cancelled"
        return
    fi

    mkdir -p "$dest_dir"

    # Get files to move
    sqlite3 "$MARMOT_DUPLICATE_DIR/duplicates.db" \
        "SELECT df.file_path
         FROM duplicate_files df
         LEFT JOIN file_selection fs ON df.file_path = fs.file_path
         WHERE fs.file_path IS NULL;" \
    | while read -r file_path; do
        if [[ -f "$file_path" ]]; then
            # Create destination path maintaining directory structure
            local relative_path="${file_path#/}"
            local dest_path="$dest_dir/$relative_path"
            local dest_dirname=$(dirname "$dest_path")

            mkdir -p "$dest_dirname"
            mv -f "$file_path" "$dest_path" 2>/dev/null && \
                echo "Moved: $file_path"
        fi
    done

    success "Duplicates moved to: $dest_dir"
}

# Generate duplicate report
duplicate_report() {
    local output_file="$MARMOT_LOG_DIR/duplicate_report_$(date +%Y%m%d).txt"

    {
        echo "Duplicate File Report"
        echo "===================="
        echo "Generated: $(date)"
        echo ""

        # Summary statistics
        sqlite3 "$MARMOT_DUPLICATE_DIR/duplicates.db" << EOF
.headers off

SELECT '=== Summary ===';
SELECT 'Total duplicate groups: ' || COUNT(*) FROM duplicate_groups;
SELECT 'Total duplicate files: ' || SUM(file_count) FROM duplicate_groups;
SELECT 'Total wasted space: ' || ROUND(SUM(total_size) / 1024/1024/1024, 2) || ' GB'
FROM duplicate_groups;
SELECT '';

SELECT '=== Top 10 Duplicate Groups by Size ===';
SELECT group_hash,
       file_count || ' files',
       ROUND(file_size / 1024/1024, 2) || ' MB',
       ROUND(total_size / 1024/1024, 2) || ' MB'
FROM duplicate_groups
ORDER BY total_size DESC
LIMIT 10;
EOF

        echo ""
        echo "=== File Type Breakdown ==="
        sqlite3 "$MARMOT_DUPLICATE_DIR/duplicates.db" << EOF
SELECT
    substr(df.file_path, length(df.file_path) - instr(reverse(df.file_path), '.') + 2) as Type,
    COUNT(*) as Count,
    ROUND(SUM(dg.file_size) / 1024/1024/1024, 2) || ' GB' as Total_Size
FROM duplicate_files df
JOIN duplicate_groups dg ON df.group_id = dg.id
GROUP BY Type
ORDER BY Total_Size DESC;
EOF

    } > "$output_file"

    success "Duplicate report generated: $output_file"
}

# Find similar files (fuzzy matching)
duplicate_find_similar() {
    local dir=${1:-.}
    local similarity=${2:-80}

    log "info" "Finding similar files in $dir (similarity: $similarity%)"

    # This would require implementing fuzzy matching algorithm
    # For now, just find files with similar names
    find "$dir" -type f -exec basename {} \; | \
    sort | \
    uniq -D | \
    while read -r filename; do
        # Find files with similar names
        find "$dir" -name "*$(echo "$filename" | cut -d. -f1)*" -type f
    done | sort | uniq -c | sort -nr
}

# Cleanup duplicate database
duplicate_cleanup() {
    local days=${1:-30}

    sqlite3 "$MARMOT_DUPLICATE_DIR/duplicates.db" << EOF
DELETE FROM file_hashes
WHERE last_scanned < datetime('now', '-$days days');
EOF

    success "Cleaned duplicate database entries older than $days days"
}