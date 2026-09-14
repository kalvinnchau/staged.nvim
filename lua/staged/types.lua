---@meta
-- This file contains type definitions only (no runtime code)

---@class StagedComment
---@field id string Unique identifier (UUID v4)
---@field file_path string Absolute path to the real file being commented
---@field modified_revision string Revision of the modified side (`WORKING`, `:0`, or commit)
---@field original_revision? string Revision of the original side, when known
---@field start_line integer 1-based start line number
---@field end_line integer 1-based end line number (inclusive)
---@field text string The comment text content
---@field created_at integer Unix timestamp when created
---@field created_order integer Monotonic creation order
---@field code? string Code snippet captured before unload (lets exports survive buffer wipes)
---@field extmark_id integer|nil Extmark ID for position tracking (nil if not yet placed)

---@class StagedFileState
---@field needs_marks? boolean Recreate live and dormant anchors after buffer reload
---@field original_path? string Original-side path for reopening comparisons, including renames
---@field git_root? string Repository owning this comparison
---@field selection? table Snapshot of the codediff panel selection, never mutated upstream
---@field bufnr integer Buffer number for this file (may be invalid for wiped revision buffers)
---@field comments table<string, StagedComment> Comments keyed by their UUID
---@field file_path string Real absolute path of the modified-side file
---@field modified_revision string `WORKING`, `:0`, or commit for the modified side
---@field original_revision? string Revision of the original side, when known

---@class StagedReviewContext
---@field modified_revision? string `WORKING` (canonical for nil), `:0`, or commit
---@field original_revision? string|nil

---@class StagedKeymap
---@field mode string
---@field lhs string

---@class StagedSession
---@field tabpage integer Neovim tabpage ID (from codediff)
---@field active boolean Whether the state-owned session is active
---@field root string Stable root used for relative export paths
---@field files table<string, StagedFileState> File states keyed by review identity (see state.file_key; bare path for working tree)
---@field current_file string|nil Internal file-state key of the active file (not necessarily a path)
---@field sidebar_bufnr integer|nil Sidebar buffer (nil if not created)
---@field sidebar_winid integer|nil Sidebar window (nil if not visible)
---@field visible boolean Whether sidebar is currently visible
---@field ns_id integer Position extmark namespace ID for this session
---@field indicator_ns_id integer Inline indicator namespace ID for this session
---@field history_ns_id integer Dormant history extmark namespace ID for this session
---@field keymaps table<integer, table<string, StagedKeymap>> Buffer-local keymaps owned by the session
---@field history StagedHistory Comment mutation history for this session

---@class StagedHistory
---@field undo StagedHistoryEntry[]
---@field redo StagedHistoryEntry[]

---@class StagedHistoryEntry
---@field action string
---@field snapshot StagedSnapshot

---@class StagedSnapshot
---@field files table<string, StagedSnapshotFile>

---@class StagedSnapshotFile
---@field file_path string
---@field modified_revision string
---@field original_revision? string
---@field original_path? string
---@field git_root? string
---@field selection? table
---@field bufnr integer
---@field comments StagedSavedComment[]

---@class StagedSavedComment
---@field id string
---@field file_path string
---@field modified_revision? string
---@field original_revision? string
---@field start_line integer
---@field end_line integer
---@field text string
---@field created_at integer
---@field created_order integer
---@field code? string
---@field history_extmark_id integer|nil

---@class StagedConfig
---@field activation StagedActivationConfig
---@field keymaps StagedKeymapsConfig
---@field sidebar StagedSidebarConfig
---@field inline StagedInlineConfig
---@field input StagedInputConfig
---@field export StagedExportConfig

---@class StagedActivationConfig
---@field mode 'auto'|'manual' How to activate on codediff sessions

---@class StagedKeymapsConfig
---@field prefix string Leader key prefix (default: '<leader>c')
---@field add string Key for add (appended to prefix)
---@field edit string Key for edit
---@field delete string Key for delete
---@field clear_all string Key for clear all
---@field undo string Key for undo
---@field redo string Key for redo
---@field toggle_sidebar string Key for sidebar toggle
---@field export_clipboard string Key for clipboard export
---@field export_buffer string Key for buffer export
---@field export_file string Key for file export
---@field next_comment string Absolute key for next comment
---@field prev_comment string Absolute key for prev comment

---@class StagedSidebarConfig
---@field position 'left'|'right' Which side to show sidebar
---@field width integer Sidebar width in columns
---@field height integer Sidebar height when split below explorer
---@field auto_show boolean Auto-show when first comment added

---@class StagedInlineConfig
---@field style 'sign'|'virtual_text'|'line_highlight' Indicator style
---@field sign_icon string Icon for sign column
---@field virtual_text_format string Format string for virtual text
---@field priority integer Extmark priority for inline decorations (0..65535, default 150)

---@class StagedInputConfig
---@field style 'floating'|'inline' Input window style

---@class StagedExportConfig
---@field include_code boolean Include code snippets in export
---@field format 'markdown'|'plain'|'json' Export format
